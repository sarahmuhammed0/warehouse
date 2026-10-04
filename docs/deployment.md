# Deployment

How to put Warehouse OS in front of real users, and the things that will bite if
you skip them.

Everything below assumes one host running Docker. The stack is MySQL, the API,
and nginx serving the compiled app — three containers plus a one-shot migration
container, defined in `docker-compose.prod.yml`.

---

## 1. Before you start

**You need TLS in front of this.** The stack terminates plain HTTP on
`HTTP_PORT`. Every password typed into the login screen and every access token
returned by it crosses that connection. On a public port 80 they are readable by
anything on the path.

Put Caddy, nginx, a load balancer or Cloudflare in front, set `HTTP_PORT=8080` so
the stack is not on the public port, and point the terminator at it. Then
`PUBLIC_ORIGIN` is the `https://` address — the API's CORS allow-list comes from
it, so getting it wrong means the app cannot call its own backend.

**You need somewhere for backups to go that is not this host.** The stack writes
them to a Docker volume on the same machine as the database. That protects you
from a bad migration or a mistaken delete. It does not protect you from the host
dying. Copy them off — see "Get them off the host" under Backups.

---

## 2. First deployment

```bash
cp .env.production.example .env.production
# fill in PUBLIC_ORIGIN, JWT_SECRET, DB_PASSWORD, MYSQL_ROOT_PASSWORD
```

Generate the secret rather than inventing one:

```bash
openssl rand -hex 48
```

Build the app. **This is the step with a silent failure mode**, so it has its own
script rather than being a `flutter build` someone types from memory:

```bash
npm run build:web -- --api /api
```

`APP_MODE` defaults to `demo`. A plain `flutter build web --release` therefore
produces a complete, working, deployable bundle that **never contacts the server**
and shows invented data — the login screen accepts the demo identities, the
dashboard has numbers on it, and nothing anyone enters is saved. The script
defaults to backend mode, refuses to build without being told where the API is,
and reads the compiled bundle back to confirm the define actually reached the
compiler.

`--api /api` is right when nginx serves both, which is what the compose file does.

> On Windows in Git Bash, `/api` gets rewritten to a Windows path before Node
> sees it. Use PowerShell, or `MSYS_NO_PATHCONV=1` in front of the command.

Then bring it up:

```bash
npm run prod:up
```

Migrations run as their own container, to completion, before the API starts — so
a failed migration stops the deploy instead of leaving the API serving against a
schema it does not expect.

Finally, create the one account that can create the others. There is no other
door in: a System Admin is not self-service, and creating a business requires
being authenticated as one.

```bash
docker compose -f docker-compose.prod.yml exec api npm run admin:create
```

The password is typed at a hidden prompt and never written to a file, a log or
shell history. The script refuses to run without a terminal rather than falling
back to an echoing read.

Sign in at `PUBLIC_ORIGIN`, choose **System Admin**, and create the first
business. Its owner gets a generated password shown once — pass it on.

---

## 3. Checking it actually worked

```bash
curl -fsS https://your-host/api/health
curl -fsS https://your-host/api/health/db
docker compose -f docker-compose.prod.yml logs api | head -40
```

In the API's startup log, confirm:

- `Backups are configured` with a directory. If it says *No backup target is
  configured*, backups are not running, whatever `BACKUP_SCHEDULE` says.
- `Scheduled backups are on` with a time.

And confirm the app is in backend mode: open it, sign in, create something, then
reload. If what you created is still there, the bundle is talking to the server.
If it vanishes, you shipped a demo build — rebuild with `--api`.

---

## 4. Running the tests in a pipeline

Use `npm run test:ci`, not `npm test`.

They differ in one thing that matters a great deal to anything reading the exit
code. Every integration test calls `requireDatabase` first and **skips** when
MySQL is unreachable — right on a developer's machine, where the unit tests are
still useful without a container. But with the database down, `npm test` exits
**zero** having run 104 of 350 tests: the integration suite skips, node:test
counts no failures, and a pipeline sees green having verified almost nothing.

`test:ci` sets `REQUIRE_DATABASE=true`, which turns that skip into a failure:

```
npm test     with no database →  exit 0,  104 passed, 246 skipped
npm test:ci  with no database →  exit 1,  104 passed, 246 FAILED
```

Both are verified behaviours, not intentions.

---

## 5. Deploying a change

```bash
git pull
npm run build:web -- --api /api          # only if the frontend changed
npm run prod:up                          # rebuilds and restarts what changed
```

The migration container runs again and is a no-op when there is nothing new.
nginx serves `frontend/build/web` from a bind mount, so a frontend-only change
needs no image rebuild.

**Take a backup before a deploy that includes a migration:**

```bash
docker compose -f docker-compose.prod.yml exec api npm run db:backup
```

---

## 6. Backups

Three ways in, all the same code path:

| | |
|---|---|
| Nightly | automatic, `BACKUP_SCHEDULE_MINUTE` after midnight, server local time |
| On demand | `docker compose -f docker-compose.prod.yml exec api npm run db:backup` |
| From the API | `POST /api/admin/backups` as a System Admin |

A row's status is the truth about the file. `completed` is written only after
mysqldump exits cleanly **and** a non-empty file exists, with its real size.
Anything else is `failed`, with the reason in `error_message`. Partial files are
deleted rather than left beside the good ones.

Old backups are pruned to `BACKUP_KEEP_LAST`, and only ever **after** a new one
succeeds — a failing dump can never delete the last good copy.

### Check a backup is worth keeping

```bash
docker compose -f docker-compose.prod.yml exec api npm run db:verify-backup -- --latest
```

This checks mysqldump's completion trailer is present (it is written last, so its
absence means the file was cut short), that every table in the database has a
`CREATE TABLE` in the dump, and that tables with rows have data. It exits
non-zero if not, so it works in a cron entry.

### Get them off the host

The whole point. A Docker volume on the same machine as the database does not
survive the machine.

```bash
docker run --rm -v warehouse-os_backups:/b -v "$PWD":/out alpine \
  tar czf /out/warehouse-os-backups.tgz -C /b .
```

Put that on a schedule to object storage or another host. **Until you do, you
have one copy of your data.**

---

## 7. Restoring

Deliberately not possible through the API. One request would replace every
business's data, and a session is the wrong authority for that — a stolen admin
token or a mis-click would destroy the platform, and no confirmation dialog
guards it when the attacker is the one answering it.

```bash
docker compose -f docker-compose.prod.yml stop api
docker compose -f docker-compose.prod.yml exec mysql sh -c 'ls /backups' # locate the file
docker compose -f docker-compose.prod.yml run --rm api npm run db:restore -- /var/backups/warehouse-os/<file>.sql
docker compose -f docker-compose.prod.yml start api
```

The tool refuses to run while the API is answering, takes a safety dump of the
**current** database before touching anything, and makes you type the database
name in full. If the restore fails halfway it tells you where that safety copy is
so you can get back to where you started.

### Rehearse it once

A backup you have never restored is a hope, not a backup. Do this once, on a
scratch database, before you need it:

```sql
CREATE DATABASE warehouse_restore_test
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL ON warehouse_restore_test.* TO 'warehouse_app'@'%';
```

```bash
# with DB_NAME pointed at the scratch database
docker compose -f docker-compose.prod.yml run --rm -e DB_NAME=warehouse_restore_test \
  api npm run db:restore -- /var/backups/warehouse-os/<file>.sql --yes
```

Then compare a few row counts against the real database and drop it. This needs
MySQL admin rights, which the application user does not have — by design.

---

## 8. Settings that matter, and why

**`TRUST_PROXY_HOPS`** is `1` in the compose file: exactly one proxy, the nginx in
front. Do not set it to a larger number than you have, and never make it a
blanket "trust everything".

At `0` behind a proxy, every request appears to come from nginx — §7's login
lockout is counted per IP, so one attacker's failures lock out **every user in the
system**, and every audit row records the proxy's address. Trusting the header
blindly is the opposite failure: a client picks its own IP and never gets locked
out at all. If you add a second proxy, this becomes `2`.

**`DB_CONNECTION_LIMIT` × instances must stay under MySQL's `max-connections`**
(200 in the compose file), with room for your own session.

**`DB_QUEUE_LIMIT`** bounds how many callers wait for a connection before the API
answers 503. Without a bound an overloaded server leaves requests hanging for
ever instead of failing in a way a client or a load balancer can act on.

**`BCRYPT_SALT_ROUNDS`** stays at 12 in production. The test suite lowers it to 4
(`backend/tests/test.env`) because hashing at cost 12 across concurrent test
processes saturates the machine; that file is never read by a production run.

---

## 9. Building the Android app

The same `APP_MODE` rule as the web build applies, and there is no script
guarding it here — so pass the defines explicitly, every time:

```bash
cd frontend
flutter build apk --release \
  --dart-define=APP_MODE=backend \
  --dart-define=API_BASE_URL=https://warehouse.example.com/api
```

**`API_BASE_URL` must be reachable from the phone.** `localhost` means the
phone itself, so a build pointed there reaches nothing. Use the server's real
address.

**It must be `https` for a release APK.** Android blocks cleartext traffic by
default since Android 9, and the release manifest deliberately does not override
that — the app carries passwords and access tokens. A release build pointed at
`http://` will fail every request, and the app will look broken with nothing to
say why.

For testing against a development server on your LAN, use a **debug** build,
where cleartext is allowed for exactly this reason:

```bash
flutter build apk --debug \
  --dart-define=APP_MODE=backend \
  --dart-define=API_BASE_URL=http://192.168.1.50:4000/api
```

You will also need `CORS_ORIGIN` on the API to include wherever the app is
served from, and the host's firewall to allow the port.

### Signing

Without `android/key.properties`, a release APK is signed with the **debug**
key. The build still succeeds — that is deliberate, so internal test builds work
on a machine with no keystore — and it prints a warning saying so.

A debug-signed APK cannot go to the Play Store, and switching to a real key
later means every existing install must be **uninstalled** first, because the
signature changes and Android refuses the upgrade. So create the key before you
distribute anything you intend to update:

```bash
keytool -genkey -v -keystore warehouse-os.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias warehouse-os
```

Then `frontend/android/key.properties`:

```properties
storeFile=C:/secure/path/warehouse-os.jks
storePassword=...
keyAlias=warehouse-os
keyPassword=...
```

That file and `*.jks`/`*.keystore` are already gitignored. **Keep a backup of
the keystore somewhere other than the build machine** — losing it means you can
never publish an update to that app again, with no recovery path.

### The toolchain warnings

`flutter doctor` reports missing `cmdline-tools` and unaccepted Android
licenses. Neither blocks `flutter build apk` — both debug and release build fine
as they are. Accepting the licences (`flutter doctor --android-licenses`) is
worth doing before you set up any automated build, since it is interactive.

---

## 10. What is still not done

Honest list. None of it stops the system being used; all of it is worth knowing.

- **Nobody has reviewed this in a browser.** 291 frontend tests prove every screen
  renders real server data and that the actions send the right requests. They
  cannot tell you a card is clipped at some window width, or that Kurdish and
  Arabic text renders badly right-to-left. Look at it on the devices your users
  have before you hand it over.
- **No monitoring or alerting.** Logs go to stdout and Docker keeps them. Nothing
  tells you the nightly backup failed except reading the backups list, and nothing
  pages you if the API stops. Ship the logs somewhere and alert on
  `status = 'failed'` in `backups`.
- **Backups are not operated from the UI.** They are platform-wide — one dump
  contains every tenant — so they are a System Admin and command-line concern.
  The business Settings → Backup section shows the real recorded state and says
  so; it cannot start one.
- **The profit report is cash-basis** and labels itself so in its own response.
  True cost-of-goods-sold needs each line's cost at the moment it sold;
  `order_items` snapshots the selling price, not the cost.
- **Session timeout and login-lockout attempts** appear in Settings and are not
  stored. The first is the token's TTL; the second is deliberately not
  per-business, because the lockout is checked before a phone is resolved to an
  account precisely so the response cannot reveal whether that account exists.
- **No horizontal scaling has been tested.** The stack runs one API container.
  Nothing in it holds per-instance state — sessions are database rows — so more
  should work, and `alreadyRanToday` makes the nightly backup safe across
  instances. It has not been run that way.
