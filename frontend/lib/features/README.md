# Feature modules — deliberately minimal in Phase 0

Mirrors `backend/src/modules/*` one-to-one (architecture §4/§10). Each
business module gets a folder here once its phase starts, following the
pattern `system_status/` already establishes:

```
features/<name>/
  data/
    <name>_models.dart       plain data classes for this feature's API shapes
    <name>_repository.dart   the only thing that calls core/network/api_client.dart
  presentation/
    <name>_screen.dart        route-level screen(s)
    providers/                  Riverpod providers wiring repository → UI state
    widgets/                     feature-specific widgets (shared ones live in
                                   core/widgets/)
```

`system_status/` is Phase 0's only feature — it exists to prove the pattern
works end to end (Flutter → API layer → Express → MySQL), not as a business
module. See the root `README.md` for what Phase 0 actually delivers.
