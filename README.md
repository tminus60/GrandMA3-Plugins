# GrandMA3 Plugins

A collection of free, open-source plugins for **grandMA3** lighting consoles.

**Author:** t-60
**Tested on:** grandMA3 2.3.2.0
**License:** [t-60 Non-Commercial](LICENSE) — free to use, even on paid jobs. See license for details.

---

## Available Plugins

| Category | Plugin | Version |
|---|---|---|
| Parameter | [Parameter Calculator](Parameter-Calculator/) | `v3.0.1` |
| Network | [Network Tools](Network-Tools/) | `v3.1.1` |
| Games | [Pong](Games/Pong/) | `v1.3.0` |
| Games | [Minesweeper](Games/Minesweeper/) | `v1.0.0` |
| Utility | [Show Locker](Showlocker/) | `v1.0.0` |

---

## Parameter

### [Parameter Calculator](Parameter-Calculator/) `v3.0.1`

Counts real and virtual DMX parameters of all fixtures in the show. Calculates how many Parameter Units (PU M/L/XL) you need to cover the show.

<table>
  <tr>
    <td><img src="Parameter-Calculator/screenshots/overview.png" width="600"></td>
  </tr>
  <tr>
    <td align="center">Overview</td>
  </tr>
</table>


---

## Network

### [Network Tools](Network-Tools/) `v3.1.1`

A suite of network diagnostic tools for grandMA3. All operations run asynchronously — the UI thread is never blocked.

| Tool | Description |
|---|---|
| **Single Ping** | Ping any host or IP address, see full output |
| **Ping Sweep** | Scan a full /24 range in parallel, add results directly to Favorites |
| **Favorites** | Save hosts by name, quick one-click ping, stored per user |
| **Ping Guard** | Continuously monitor a list of IPs in the background, popup alert when a host goes down or comes back up |

<table>
  <tr>
    <td><img src="Network-Tools/screenshots/launcher.png" width="280"></td>
    <td><img src="Network-Tools/screenshots/single-ping.png" width="280"></td>
    <td><img src="Network-Tools/screenshots/sweep.png" width="280"></td>
  </tr>
  <tr>
    <td align="center">Launcher</td>
    <td align="center">Single Ping</td>
    <td align="center">Ping Sweep</td>
  </tr>
  <tr>
    <td><img src="Network-Tools/screenshots/favorites.png" width="280"></td>
    <td><img src="Network-Tools/screenshots/guard.png" width="280"></td>
    <td><img src="Network-Tools/screenshots/guard-alert.png" width="280"></td>
  </tr>
  <tr>
    <td align="center">Favorites</td>
    <td align="center">Ping Guard</td>
    <td align="center">Guard Alert</td>
  </tr>
</table>

---

## Games

### [Pong](Games/Pong/) `v1.3.0`

A fully-featured Pong game for grandMA3. Control your paddle with a playback master fader. Supports CPU and 2-Player mode, configurable ball speed, paddle height, obstacles, and smooth pixel-precise rendering.

<table>
  <tr>
    <td><img src="Games/Pong/screenshots/game.png" width="400"></td>
    <td><img src="Games/Pong/screenshots/settings.png" width="240"></td>
  </tr>
  <tr>
    <td align="center">Game</td>
    <td align="center">Settings</td>
  </tr>
</table>

### [Minesweeper](Games/Minesweeper/) `v1.0.0`

Classic Minesweeper for grandMA3. Three difficulty levels, score system with persisted highscores per difficulty, flag mode, and chord-reveal. Mines are placed after the first click — the first reveal is always safe.

| Feature | Description |
|---|---|
| **Easy** | 9×9 grid, 10 mines |
| **Medium** | 16×16 grid, 40 mines |
| **Hard** | 16×30 grid, 99 mines |
| **Flag Mode** | Toggle to place/remove flags instead of revealing |
| **Chord Reveal** | Click a revealed number with enough adjacent flags to reveal remaining neighbors |
| **Highscore** | Best score saved per difficulty, persists across sessions |

<table>
  <tr>
    <td><img src="Games/Minesweeper/screenshots/game.png" width="400"></td>
  </tr>
  <tr>
    <td align="center">Game</td>
  </tr>
</table>

---

## Utility

### [Show Locker](Showlocker/) `v1.0.0`

Locks the grandMA3 show with a PIN code. Uses GMA3's native blocking modal — nothing in the background can be interacted with while locked. After 3 wrong attempts the current show is saved and a new empty show is loaded.

| Feature | Description |
|---|---|
| **3-attempt limit** | Wrong PIN can be entered 3 times before the show is wiped |
| **Blocking lock** | GMA3's native TextInput modal — no background interaction possible |
| **Configurable PIN** | Set any numeric or text PIN, stored persistently in GlobalVars |
| **Configurable message** | Custom lock screen message |
| **Show save** | Current show is saved as `Showlock` before wiping — not permanently lost |

<table>
  <tr>
    <td><img src="Showlocker/screenshots/main.png" width="360"></td>
    <td><img src="Showlocker/screenshots/lock.png" width="360"></td>
  </tr>
  <tr>
    <td align="center">Launcher</td>
    <td align="center">Lock Screen</td>
  </tr>
</table>

---

## Requirements

- grandMA3 **2.3.2.0** or newer (earlier versions may work but are untested)

---

## Issues & Feedback

Found a bug or have a feature request?
[Open an issue](https://github.com/tminus60/GrandMA3-Plugins/issues)

---

## License

These plugins are **free to use** — including for paid professional work such as live shows, events, and tours.

**Not permitted:**
- Selling these plugins or any modified version
- Including them in paid products or services
- Republishing them under a different name

See [LICENSE](LICENSE) for full terms.
