# Changelog — Parameter Calculator

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [3.0.0] — 2026-05-17

### Added
- Crash handler: errors write a timestamped log to GMA3's temp folder and show a MessageBox
- `safe()` wrapper on all signal callbacks so button-click errors are also caught
- Forward declaration for `_recalcTotal` so it can be called from `main()` on startup
- All fields now populate immediately on open (no need to click anything first)
- PU output fields initialised to `0` instead of blank

### Changed
- Complete code rewrite — all logic extracted into named functions
- `Root()` colour references moved into `main()` (safe at runtime, not at module load)
- PU M / L / XL setter unified into a single `_setPuCount()` function
- `_recalcTotal()` extracted and reused across all update paths
- `OnChangeAll` uses a lookup table instead of three separate if-blocks
- `updateUIFromStats()` now computes totals directly from stats — no UI round-trip
- `_updating` guard uses `pcall` so the flag is always reset even on error
- `isOnPc` extracted to avoid checking `sys == 4096` twice in `_recalcTotal()`
- Header, version, GitHub and license block added

### Fixed
- `dialog.missingoutput.text` (lowercase) → `.Text` — was always nil, causing a crash on every recalculation
- `GetPath(Enums.PathType.Temp)` moved out of module scope into the crash handler body
- Duplicate `signalTable.SystemConfigButtonClicked` definition (second silently overwrote the first)
- Seven unguarded `Printf("Debug!")` calls removed from production code
- `colordefault`, `colorgreendark`, `colorgreen`, `coloryellow`, `colorcyan` declared but never used — removed
- `json = require("json")` included but never used — removed
- Debug button present in TitleBar code but missing from UI (column 3 referenced on a 2-column bar) — removed both
- `presetold` / `presetnew` were implicit globals — now `local`
- Variable shadowing: `local a`, `local b`, `local s` declared twice in same scope — renamed

### Removed
- `fct.buildHeader()` — defined but never called
- `colorTransparent` — declared and assigned but never read after `buildHeader` was removed
- Dead keys in dialog result table: `systemconfigButton`, `systemconfigItems`, `systemconfigMapByText`

---

## [2.0] — initial release
