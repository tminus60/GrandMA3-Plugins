# Changelog — Show Locker

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [1.0.0] — 2026-05-22

### Added
- Initial release
- PIN pad lock screen (1–8 digit PIN, no Close / no ESC)
- Wrong PIN → loads "ShowLocked" show (creates it automatically if it doesn't exist)
- Correct PIN → returns to launcher
- Settings: change PIN, lock message, locked show name — all persisted in GlobalVars
- Launcher window with current config summary
- t-60 Crash Reporter (Discord webhook)
- t-60 Update Checker (GitHub version.txt)
