# The API, for production.
#
# Two stages so the image that runs does not carry the toolchain that built it:
# dev dependencies are installed to run nothing here, so they are simply never
# copied forward.

# ---- dependencies ----------------------------------------------------------
FROM node:24-alpine AS deps

WORKDIR /app

# The lockfile is copied on its own first, so this layer is only rebuilt when
# dependencies actually change — not on every source edit.
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/

# `npm ci`, not `npm install`: it installs exactly the lockfile and fails if the
# two disagree, which is the difference between a reproducible image and one that
# quietly picked up a new minor version.
RUN npm ci --omit=dev --workspace warehouse-os-backend --include-workspace-root


# ---- runtime ---------------------------------------------------------------
FROM node:24-alpine AS runtime

# mysql-client provides mysqldump, which §33's backups shell out to. Without it
# the backup subsystem starts, accepts a request, and fails on every attempt —
# so it belongs in the image rather than in a runbook step someone forgets.
RUN apk add --no-cache mysql-client tini \
    && rm -rf /var/cache/apk/*

ENV NODE_ENV=production

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY backend ./backend
# `database/` sits beside `backend/` because knexfile.js points migrations at
# "../database/migrations" — so the layout inside the image has to match the
# repository's, or `npm run migrate` resolves to nothing and reports success
# having applied no migrations.
COPY database ./database

# The backup directory is a VOLUME in compose. It is created here with the right
# owner so a non-root process can write to it on a fresh volume.
RUN mkdir -p /var/backups/warehouse-os \
    && chown -R node:node /var/backups/warehouse-os

# Not root. A compromise in the API should not be a compromise of the container,
# and nothing here needs privilege — the port is 4000, well above 1024.
USER node

WORKDIR /app/backend

EXPOSE 4000

# tini as PID 1, so SIGTERM reaches node and `shutdown()` runs — the graceful
# close that drains connections and ends the pool. Without an init, node is PID 1
# and does not get the default signal handlers, so a deploy would kill it mid
# request.
ENTRYPOINT ["/sbin/tini", "--"]

# Checked by compose, so a container that is up but not serving is not treated as
# ready. It hits the app's own health route rather than just opening the port.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4000)+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
