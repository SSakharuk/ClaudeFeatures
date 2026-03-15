# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is a workspace for small, self-contained projects and features that enhance or extend Claude Code on this machine. Each subdirectory is an independent project.

## Structure

Each project lives in its own subdirectory. Projects are independent — do not assume shared dependencies, build systems, or conventions across subdirectories unless explicitly noted.

When starting work on a new project here:
1. Create a subdirectory with a descriptive name.
2. Add a `README.md` (or inline comments) explaining what the project does and how to run it.
3. Keep scope small and focused — this workspace is for targeted improvements, not large systems.

## Platform

- OS: Windows 11, shell: bash (Git Bash / WSL)
- Use Unix-style paths and commands (forward slashes, `/dev/null`, etc.)
- Claude Code model: `claude-sonnet-4-6` (default); use `claude-opus-4-6` for complex tasks, `claude-haiku-4-5-20251001` for lightweight ones

## Projects

### claude-notifier
Windows toast notification system for Claude Code. Hooks into `Stop` and `Notification` events to show a toast + play a sound when Claude finishes or needs input. Includes a system tray app (`tray.ps1`) for toggling sound/toast and changing the sound file. Settings persisted in `config.json`. Requires the `BurntToast` PowerShell module.

- Install/reinstall: `.\claude-notifier\install.ps1`
- Test: `.\claude-notifier\test.ps1 [-Type stop|permission|idle|question|all]`
- Uninstall: `.\claude-notifier\uninstall.ps1`

## Per-project guidance

If a project has its own `CLAUDE.md` or `README.md`, that takes precedence over this file for anything project-specific (build commands, test runners, architecture, etc.).
