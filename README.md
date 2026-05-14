# GrandMA3 Plugins

A collection of free, open-source plugins for **grandMA3** lighting consoles.

**Author:** t-60
**Tested on:** grandMA3 2.3.2.0
**License:** [t-60 Non-Commercial](LICENSE) — free to use, even on paid jobs. See license for details.

---

## Available Plugins

### Misc

| Plugin | Description | Version | GMA3 |
|--------|-------------|---------|------|
| [Parameter Calculator](Parameter-Calculator/) | Counts real and virtual DMX parameters of all fixtures in the show. Calculates how many Parameter Units (PU M/L/XL) you need to cover the show. | 3.0.0 | 2.3.2.0 |

### Network

| Plugin | Description | Version | GMA3 |
|--------|-------------|---------|------|
| [Ping](Network/Ping/) | Ping a host or IP address directly from the grandMA3 console. | 2.0.0 | 2.3.2.0 |

### Timecode *(coming soon)*

| Plugin | Description |
|--------|-------------|
| TC Create Song | Creates all components for a new timecode song (macro, timecode, sequences, presets, views, page) |
| TC Delete Song | Deletes all components of a timecode song |
| TC Move Song | Moves a timecode song to a new slot or datapool |
| TC Change Label | Renames a timecode song across all its components |
| TC Change Offset | Changes the timecode offset of a song with quick ±h/m/s/f buttons |
| TC BPM Shifter | Scales all timecode events from one BPM to another |

---

## Installation

1. **Download** the `.xml` file of the plugin you want
2. In grandMA3: **Menu → Import/Export → Import**
3. Select the downloaded `.xml` file
4. The plugin will appear in your **Plugin Pool**

> **Note:** The `.lua` file is the readable source code. The `.xml` is the file you import into grandMA3.

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
