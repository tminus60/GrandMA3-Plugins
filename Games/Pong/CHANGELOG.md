# Changelog — Pong

All notable changes to this plugin will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com) — versions follow `MAJOR.MINOR.PATCH`.

---

## [1.3.0] — 2026-05-17

### Added
- Dashed centre line (classic Pong look)
- 2-Player mode: second fader controls the left paddle
- Player 1 / Player 2 name fields in Settings
- Paddle Height setting — applies immediately without restart
- Obstacle system with configurable count and bounce behaviour
- CPU tab info text in Settings
- Crash handler + `safe()` wrappers on all signal callbacks
- Dead-window detection: timer self-terminates when game window is closed

### Changed
- Field enlarged to 960 × 540 px (was 820 × 480)
- Ball enlarged to 18 × 18 px (was 14 × 14)
- Score bar: both score cells highlighted symmetrically
- Settings dialog: tabbed layout (Control / Match | CPU)
- Settings window opens offset from game window
- Start button restarts the game after game over
- `readFader` / `readFader2` unified into a single `readFader(seqNum)` function
- `ballSpeed`, `winScore`, `cpuSpeed` clamped to minimum 1 on Apply
- `obstacleCount` clamped to 1–10 on Apply

### Fixed
- Window resize when ball reaches field edges (all spacer columns Fixed)
- Speed multiplication on restart (timer generation counter)
- Settings window not reopening after closing via X (alive check via pcall)

---

## [1.0.0] — initial release
