#!/usr/bin/env node
'use strict';

// PreToolUse hook for Claude Code
// Intercepts Bash commands and rewrites them through the token-saving filter runner
// Zero external dependencies — pure Node.js

const RUNNER_PATH = (__dirname + '/runner.js').replace(/\\/g, '/');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', c => data += c);
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(data);

    // Only intercept Bash commands
    if (input.tool_name !== 'Bash') {
      allow();
      return;
    }

    const cmd = (input.tool_input && input.tool_input.command || '').trim();

    // Skip empty commands
    if (!cmd) {
      allow();
      return;
    }

    // Skip if explicitly bypassed
    if (cmd.includes('# nofilter') || cmd.includes('NO_TOKEN_SAVER=1')) {
      allow();
      return;
    }

    // Skip compound commands (pipes, redirects, chaining) — too risky to rewrite
    if (isCompound(cmd)) {
      allow();
      return;
    }

    // Match known commands
    const filterType = getFilterType(extractBaseCommand(cmd));
    if (filterType) {
      const b64 = Buffer.from(cmd).toString('base64');
      const newCmd = `node "${RUNNER_PATH}" ${filterType} ${b64}`;
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          permissionDecision: 'allow',
          updatedInput: { command: newCmd }
        }
      }));
    } else {
      allow();
    }
  } catch (e) {
    // On any error, let the original command pass through
    allow();
  }
});

function allow() {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { permissionDecision: 'allow' }
  }));
}

// Check for compound operators outside of quotes
function isCompound(cmd) {
  const stripped = cmd.replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, '');
  return /[|><;]|&&|\|\|/.test(stripped);
}

// Strip env var assignments (VAR=val) from start of command
function extractBaseCommand(cmd) {
  return cmd.replace(/^(\w+=\S+\s+)*/, '').trim();
}

function getFilterType(cmd) {
  if (/^git\s+status(\s|$)/.test(cmd)) return 'git-status';
  if (/^git\s+diff(\s|$)/.test(cmd)) return 'git-diff';
  if (/^git\s+log(\s|$)/.test(cmd)) return 'git-log';
  if (/^git\s+show(\s|$)/.test(cmd)) return 'git-show';
  if (/^git\s+branch(\s|$)/.test(cmd)) return 'git-branch';
  if (/^(npm|pnpm)\s+install(\s|$)/.test(cmd)) return 'pkg-install';
  if (/^yarn(\s+install|\s*$)/.test(cmd)) return 'pkg-install';
  if (/^pip\s+install(\s|$)/.test(cmd)) return 'pkg-install';
  if (/^(npm\s+test|npx\s+(jest|vitest|mocha|playwright)|pytest|cargo\s+test|dotnet\s+test|go\s+test)(\s|$)/.test(cmd)) return 'test';
  if (/^(npm\s+run\s+build|tsc|cargo\s+(build|check)|dotnet\s+build|go\s+build|make)(\s|$)/.test(cmd)) return 'build';
  if (/^(eslint|cargo\s+clippy|dotnet\s+format|pylint|flake8|golangci-lint)(\s|$)/.test(cmd)) return 'lint';
  return null;
}
