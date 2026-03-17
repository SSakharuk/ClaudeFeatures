# claude-token-saver

Lightweight token saver for Claude Code on Windows. Intercepts Bash commands via PreToolUse hook, compresses output, and tracks savings. Zero external dependencies — pure Node.js.

## How it works

1. **Hook** (`hook.js`) — registered as a PreToolUse hook in `~/.claude/settings.json`. Fires on every Bash command, checks if it matches known patterns.
2. **Runner** (`runner.js`) — for matching commands, the hook rewrites the command to go through the runner. The runner executes the original command, applies filters, and outputs compressed result.
3. **Tracker** — every filtered command is logged to `~/.claude-token-saver/log.jsonl` with before/after char counts.

Claude sees the compressed output and doesn't know anything was filtered.

## What gets filtered

| Command | Strategy | Typical savings |
|---------|----------|-----------------|
| `git status` | Short format (`-sb`) | ~70% |
| `git diff` | Truncate at 500 lines | ~80% for large diffs |
| `git log` | `--oneline -30` | ~90% |
| `git show` | Truncate at 500 lines | ~80% |
| `npm/yarn/pnpm install` | Summary only | ~85% |
| test runners (jest, pytest, cargo test...) | Failures + summary | ~90% |
| build tools (tsc, cargo build, make...) | Errors/warnings only | ~80% |
| lint (eslint, clippy...) | Truncate at 300 | variable |

**All commands** also get: ANSI escape code stripping, blank line collapsing, long line truncation (500 chars), hard cap at 80K chars.

**Never filtered**: `git commit`, `git push`, `git add`, `git checkout`, `mkdir`, `echo`, `rm`, and any non-matching commands. Also skips compound commands with `|`, `&&`, `;`, `>`.

## Install / Uninstall

```powershell
# Install (registers hook in settings.json)
.\claude-token-saver\install.ps1

# Uninstall (removes hook)
.\claude-token-saver\uninstall.ps1
```

Restart Claude Code after install/uninstall for changes to take effect.

## Usage

Once installed, it works automatically. No changes to your workflow.

**Bypass for a single command**: add `# nofilter` to the command:
```bash
git diff # nofilter
```

**View savings stats**:
```bash
node claude-token-saver/stats.js           # last 7 days
node claude-token-saver/stats.js --today   # today only
node claude-token-saver/stats.js --all     # all time
node claude-token-saver/stats.js --reset   # clear log
```

**Run tests**:
```powershell
.\claude-token-saver\test.ps1              # all tests
.\claude-token-saver\test.ps1 -Type git-diff  # specific filter
```

## Configuration

Edit `config.json` to tune filter limits:

```json
{
  "enabled": true,
  "maxLines": { "gitDiff": 500, "gitLog": 100, "test": 200, "build": 150, "lint": 300 },
  "maxLineWidth": 500,
  "maxTotalChars": 80000,
  "gitLogLimit": 30
}
```

## Requirements

- Node.js (already required by Claude Code)
- No admin rights
- No npm install
- No external binaries
