# Claude Usage Widget

A floating desktop widget for Windows that shows your Claude Code plan usage in real time — session limit (5h) and weekly limit (7d) with progress bars and reset countdowns.

## How it works

Makes a minimal API call (1 token, Haiku model) using your existing Claude Code OAuth credentials and reads the rate-limit headers from the response. No separate API key needed.

Headers used:
- `anthropic-ratelimit-unified-5h-utilization` / `5h-reset` — session usage
- `anthropic-ratelimit-unified-7d-utilization` / `7d-reset` — weekly usage

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Node.js
- [Claude Code](https://claude.ai/code) (provides OAuth credentials in `~/.claude/.credentials.json`)

## Installation

```powershell
.\install.ps1
```

Registers the widget to launch at Windows startup and starts it immediately. The widget runs detached from any terminal via `wscript.exe` — closing your terminal won't kill it.

## Usage

- **Drag** the purple header bar to reposition. Position is saved automatically.
- **Right-click** anywhere on the widget for options:
  - **Size** — Small / Medium / Large
  - **Auto-refresh** — 1 / 5 / 10 / 30 / 60 minutes
  - **Exit**
- **Refresh button** in the header for an immediate data refresh.

Each refresh makes one minimal API call (~10 tokens). The countdown timers update every 30 seconds without an API call.

## Files

| File | Purpose |
|---|---|
| `widget.ps1` | Main widget application (WinForms floating window) |
| `fetch-usage.js` | Node.js script — makes the API call and outputs JSON |
| `launch.vbs` | Detached launcher — starts widget independent of any terminal |
| `config.json` | Saved position, size, and refresh interval |
| `install.ps1` | Registers startup entry and launches widget |
| `uninstall.ps1` | Removes startup entry and stops widget |

## Uninstall

```powershell
.\uninstall.ps1
```
