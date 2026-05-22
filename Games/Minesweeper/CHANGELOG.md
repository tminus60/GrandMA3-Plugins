# Changelog — Minesweeper

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [1.0.0] — 2026-05-22

### Added
- Initial release
- Three difficulty presets: Easy (9×9, 10 mines), Medium (16×16, 40 mines), Hard (16×30, 99 mines)
- First-click safety — mines placed after first reveal, avoiding the clicked cell and its neighbors
- Flag Mode toggle — click cells to flag/unflag instead of reveal
- Chord reveal — clicking a revealed number whose adjacent flags match its count reveals remaining neighbors
- Mine counter, elapsed timer, face button (restart)
- Difficulty cycling without restarting the plugin
- t-60 Crash Reporter (Discord webhook)
- t-60 Update Checker (GitHub version.txt)
