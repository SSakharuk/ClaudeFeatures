# Claude Notifier

A Windows notification system for [Claude Code](https://claude.ai/code). Get a toast notification and sound when Claude finishes a task or needs your attention — even across multiple terminal sessions.

## How it works

Claude Code fires hook events when it finishes work (`Stop`) or needs user input (`Notification`). This project wires those hooks to a Windows toast notification + sound, so you don't have to watch the terminal.

Each notification includes the **project folder name**, so with multiple Claude Code sessions open you always know which one needs attention.

## Requirements

- Windows 10/11
- PowerShell 5.1+
- [Claude Code](https://claude.ai/code)
- [BurntToast](https://github.com/Windos/BurntToast) PowerShell module (installed automatically)

## Installation

```powershell
# 1. Install BurntToast (one-time)
Install-Module -Name BurntToast -Scope CurrentUser -Force

# 2. Run the installer
.\install.ps1
```

This will:
- Register `Notification` and `Stop` hooks in `~/.claude/settings.json`
- Add the tray app to Windows startup
- Launch the tray app immediately

## Tray app

After install, a blue **"C"** icon appears in the system tray. Right-click it to:

- **Sound** — toggle sound on/off
- **Toast notification** — toggle toast on/off
- **Change Sound** — pick from 7 Windows system sounds (previews on click)
- **Exit** — stop the tray app

The tray app starts automatically with Windows.

## Notification types

| Event | When it fires | Toast title |
|---|---|---|
| `Stop` | Claude finishes a task | `Claude done - <project>` |
| `permission_prompt` | Claude needs your approval to run a command | `Claude needs permission - <project>` |
| `idle_prompt` | Claude is waiting for your next message | `Claude is waiting - <project>` |
| `elicitation_dialog` | Claude is asking you a question | `Claude has a question - <project>` |

## Files

| File | Purpose |
|---|---|
| `notify.ps1` | Hook handler — called by Claude Code on each event |
| `tray.ps1` | Background tray app — manages settings |
| `config.json` | Persisted settings (sound, toast, sound file) |
| `install.ps1` | Registers hooks + startup entry, launches tray |
| `uninstall.ps1` | Removes hooks, startup entry, stops tray |
| `test.ps1` | Manually trigger test notifications |

## Testing

```powershell
.\test.ps1              # fire all 4 notification types
.\test.ps1 -Type stop   # just the "Claude done" notification
.\test.ps1 -Type permission
.\test.ps1 -Type idle
.\test.ps1 -Type question
```

## Uninstall

```powershell
.\uninstall.ps1
```

Removes hooks from `~/.claude/settings.json`, removes the startup registry entry, and stops the tray app.
