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

    if (input.tool_name !== 'Bash') { allow(); return; }

    const cmd = (input.tool_input && input.tool_input.command || '').trim();

    if (!cmd) { allow(); return; }

    // Explicit bypass
    if (cmd.includes('# nofilter') || cmd.includes('NO_TOKEN_SAVER=1')) { allow(); return; }

    // Skip if contains pipes or redirects (unsafe to split)
    const stripped = cmd.replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, '');
    if (/[|><]|\|\|/.test(stripped)) { allow(); return; }

    // Try to rewrite: handles both simple and compound (&& / ;) commands
    const rewritten = rewriteCommand(cmd);
    if (rewritten) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          permissionDecision: 'allow',
          updatedInput: { command: rewritten }
        }
      }));
    } else {
      allow();
    }
  } catch (e) {
    allow();
  }
});

function allow() {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { permissionDecision: 'allow' }
  }));
}

// Rewrite a command (simple or compound) — returns null if no filter applies
function rewriteCommand(cmd) {
  const segments = splitOnChaining(cmd);

  // Single segment — fast path
  if (segments.length === 1) {
    const type = getFilterType(extractBaseCommand(segments[0].text));
    if (!type) return null;
    const b64 = Buffer.from(segments[0].text).toString('base64');
    return `node "${RUNNER_PATH}" ${type} ${b64}`;
  }

  // Compound command — rewrite matching segments, pass others through
  let anyMatch = false;
  const parts = segments.map(seg => {
    const type = getFilterType(extractBaseCommand(seg.text));
    if (type) {
      anyMatch = true;
      const b64 = Buffer.from(seg.text).toString('base64');
      return { text: `node "${RUNNER_PATH}" ${type} ${b64}`, op: seg.op };
    }
    return seg;
  });

  if (!anyMatch) return null;

  // Rejoin: each segment's text + its trailing operator (except last which has op=null)
  return parts.map(seg => seg.text + (seg.op ? ` ${seg.op} ` : '')).join('');
}

// Split "cmd1 && cmd2 ; cmd3" into [{text, op}, ...] respecting quotes
// op is the separator AFTER this segment ('&&', ';', or null for last)
function splitOnChaining(cmd) {
  const result = [];
  let current = '';
  let i = 0;
  let inSingle = false, inDouble = false;

  while (i < cmd.length) {
    const c = cmd[i];

    if (c === "'" && !inDouble) { inSingle = !inSingle; current += c; i++; continue; }
    if (c === '"' && !inSingle) { inDouble = !inDouble; current += c; i++; continue; }
    if (c === '\\' && i + 1 < cmd.length) { current += c + cmd[i + 1]; i += 2; continue; }

    if (!inSingle && !inDouble) {
      if (c === '&' && cmd[i + 1] === '&') {
        if (current.trim()) result.push({ text: current.trim(), op: '&&' });
        current = ''; i += 2; continue;
      }
      if (c === ';') {
        if (current.trim()) result.push({ text: current.trim(), op: ';' });
        current = ''; i++; continue;
      }
    }

    current += c; i++;
  }

  if (current.trim()) result.push({ text: current.trim(), op: null });
  return result.length ? result : [{ text: cmd, op: null }];
}

// Strip leading env var assignments: VAR=val VAR2=val2 cmd args
function extractBaseCommand(cmd) {
  return cmd.replace(/^(\w+=\S*\s+)*/, '').trim();
}

function getFilterType(cmd) {
  if (/^git\s+status(\s|$)/.test(cmd))  return 'git-status';
  if (/^git\s+diff(\s|$)/.test(cmd))    return 'git-diff';
  if (/^git\s+log(\s|$)/.test(cmd))     return 'git-log';
  if (/^git\s+show(\s|$)/.test(cmd))    return 'git-show';
  if (/^git\s+branch(\s|$)/.test(cmd))  return 'git-branch';
  if (/^(npm|pnpm)\s+install(\s|$)/.test(cmd))  return 'pkg-install';
  if (/^yarn(\s+install|\s*$)/.test(cmd))        return 'pkg-install';
  if (/^pip\s+install(\s|$)/.test(cmd))          return 'pkg-install';
  if (/^(npm\s+test|npx\s+(jest|vitest|mocha|playwright)|pytest|cargo\s+test|dotnet\s+test|go\s+test)(\s|$)/.test(cmd)) return 'test';
  if (/^(npm\s+run\s+build|tsc|cargo\s+(build|check)|dotnet\s+build|go\s+build|make)(\s|$)/.test(cmd)) return 'build';
  if (/^(eslint|cargo\s+clippy|dotnet\s+format|pylint|flake8|golangci-lint)(\s|$)/.test(cmd)) return 'lint';
  if (/^gh\s+(pr|issue|run|repo|release|workflow)\s/.test(cmd)) return 'gh';
  if (/^docker\s+(ps|images|logs|stats|inspect|diff)(\s|$)/.test(cmd)) return 'docker';
  return null;
}
