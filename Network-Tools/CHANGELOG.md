# Changelog — Network Tools

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [3.1.1] — 2026-05-22

### Added
- **Custom plugin icon** in TitleBar via `AppearancePreview` — displays embedded `NetworkToolsLogo` Appearance
- **t-60 Crash Reporter** — on unhandled error, sends a Discord notification with plugin version, GMA3 version, show name, OS, timestamp, and crash log as file attachment
- **Guard DOWN alert popup** — dedicated `GuardAlert` window stacks multiple state-change events instead of spawning separate dialogs
- **Update checker** — on startup, fetches latest version from GitHub in the background; shows a popup if a newer version is available
- MAC address persisted per Favorite entry across sessions

### Changed
- TitleBar uses `ColorGroups.PoolWindow.Bitmaps` for consistent background across icon, buttons, and title
- TitleBar extended to 5 columns: icon · title · display-picker · fullscreen-toggle · close

### Fixed
- Two `table.insert` calls for new Favorites were missing the `last_mac` field, causing nil errors on subsequent pings

---

## [3.1.0] — 2026-05-18

### Added
- **Table layout** for Sweep results, Favorites, and Guard — pre-allocated rows with color indicators (green=UP, red=DOWN, dim=unknown)
- **Column headers** (IP Address, Name, Status, Avg, etc.) above each table
- Favorites now uses **`UserVars()`** (per-user) instead of `GlobalVars()` — different users on same session have independent lists
- **`TextInput()` prompt** for adding Favorites and Guard IPs — cleaner than inline LineEdit fields

### Changed
- All windows use all-Fixed DialogFrame rows to eliminate GMA3 first-render gap bug
- Favorites: stores last ping result (ok/ms) per entry, shown in Avg column
- Guard: status column shows UP/DOWN/— text in addition to color indicator
- Guard: "Add IP" prompt via TextInput, interval field remains inline

---

## [3.0.0] — 2026-05-18

### Added
- **Favorites** — save hosts by name + IP, quick one-click ping, stored in GlobalVars per user
- **Ping Guard** — continuous background monitoring at a configurable interval; alerts via command line when a host goes down or comes back up; persists across window close
- Plugin renamed from "Network Ping" to "Network Tools"
- Launcher redesigned with 5 colour-coded tool cards

### Changed
- Sweep result lines prefixed with ▶ for visual clarity
- `startPing` accepts configurable ping count (reused by Latency Test)
- Guard config (IPs, interval) persisted to GlobalVars and restored on plugin start

---

## [2.2.0] — 2026-05-17

### Added
- Launcher window with tool selection
- Single Ping and Ping Sweep as separate windows
- Crash handler + `safe()` on all callbacks
- `safePoll()` prevents "LUA engine caught an exception" on Timer ticks

### Changed
- Sweep runs synchronously (`cmd /c`) so GMA3 progress bar plays during the wait

---

## [2.0] — initial release
