# Changelog — Network Ping

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [2.2.0] — 2026-05-17

### Added
- Launcher window: opens first with a card-style selection between Single Ping and Ping Sweep
- Ping Sweep: scans an entire IP range for active devices
  - All pings run in parallel (full /24 in ~3 seconds)
  - GMA3 progress bar shown while sweep runs
  - Results sorted by last octet and displayed as a list
  - Live input validation: shows host count or error while typing
- `safe()` wrapper on all signal callbacks
- `safePoll()` wrapper prevents "LUA engine caught an exception" from Timer callbacks
- Crash handler with log file + MessageBox

### Changed
- Complete rewrite in standard GMA3 plugin structure (TitleBar, DialogFrame, signal table)
- Single Ping and Ping Sweep are now separate windows opened from the launcher
- Section headers, row size policies and unified design (matching Parameter Calculator style)
- Sweep runs synchronously via `cmd /c` so GMA3 progress bar animation plays during the scan
- Removed icon boxes and margins for a cleaner, flatter layout

### Fixed
- `"network_node"` icon replaced with `"object_appear"` 
- `Timer(fn, interval)` with 2 args fires repeatedly in GMA3 — poll now uses a `done` flag to stop cleanly
- Progress bar stuck at 0: `SetProgressRange` cannot update from a Timer callback in GMA3 — sweep is now synchronous

---

## [2.0.0] — 2026-05-15

### Changed
- Rewritten from external-function style to standard GMA3 plugin structure
- IP input via `LineEdit` instead of `TextInput()` dialog
- Ping results displayed inside the plugin dialog
- Cross-platform support retained (Windows / Linux)
- Crash handler and header block added

---

## [1.0.0] — initial release (external function style)
