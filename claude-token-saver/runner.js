#!/usr/bin/env node
'use strict';

// Token-saving filter runner
// Executes the original command, filters output, tracks savings, saves tee on failure
// Zero external dependencies — pure Node.js

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DATA_DIR = path.join(os.homedir(), '.claude-token-saver');
const LOG_FILE  = path.join(DATA_DIR, 'log.jsonl');
const TEE_DIR   = path.join(DATA_DIR, 'tee');
const CONFIG_FILE = path.join(__dirname, 'config.json');

const DEFAULT_CONFIG = {
  maxLines: { gitDiff: 500, gitShow: 500, gitLog: 100, test: 200, build: 150, lint: 300, docker: 50 },
  maxLineWidth: 500,
  maxTotalChars: 80000,
  gitLogLimit: 30,
  teeOnFailure: true,
  teeMaxFiles: 10,
  enabled: true
};

let config = DEFAULT_CONFIG;
try {
  const userConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  config = { ...DEFAULT_CONFIG, ...userConfig, maxLines: { ...DEFAULT_CONFIG.maxLines, ...(userConfig.maxLines || {}) } };
} catch (e) { /* use defaults */ }

const filterType  = process.argv[2];
const originalCmd = Buffer.from(process.argv[3] || '', 'base64').toString('utf8');

if (!originalCmd) {
  process.stderr.write('claude-token-saver runner: no command provided\n');
  process.exit(1);
}

try {
  run();
} catch (e) {
  fallback();
}

function run() {
  const shell = process.env.SHELL || 'bash';
  const env = { ...process.env, GIT_PAGER: 'cat', PAGER: 'cat', NO_COLOR: '1' };
  const spawnOpts = { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024, env, timeout: 120000 };

  // Pre-process: optionally modify the command before execution
  const cmd = preProcess(originalCmd, filterType);
  const wasPreProcessed = (cmd !== originalCmd);

  // Measure original output for accurate tracking when command was rewritten
  let rawLen;
  if (wasPreProcessed) {
    const rawResult = spawnSync(shell, ['-c', originalCmd], { ...spawnOpts, timeout: 5000 });
    rawLen = ((rawResult.stdout || '') + (rawResult.stderr || '')).length;
  }

  // For git-diff: also capture --stat summary to prepend (shows which files changed)
  let statHeader = '';
  if (filterType === 'git-diff') {
    statHeader = buildDiffStatHeader(cmd, shell, spawnOpts);
  }

  // Execute the (possibly modified) command
  const result = spawnSync(shell, ['-c', cmd], spawnOpts);

  let stdout = result.stdout || '';
  let stderr = result.stderr || '';
  const exitCode = result.status || 0;

  if (rawLen === undefined) rawLen = stdout.length + stderr.length;

  // Save full output to tee file on failure (before filtering)
  if (exitCode !== 0 && config.teeOnFailure) {
    saveTee(originalCmd, stdout + stderr);
  }

  // Filter pipeline
  stdout = stripAnsi(stdout);
  stderr = stripAnsi(stderr);
  stdout = postProcess(stdout, filterType, statHeader);
  stdout = collapseBlankLines(stdout);
  stdout = truncateLines(stdout, config.maxLineWidth);
  stdout = hardCap(stdout, config.maxTotalChars);
  stderr = collapseBlankLines(stderr);

  const filtLen = stdout.length + stderr.length;
  track(originalCmd, filterType, rawLen, filtLen);

  process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  process.exit(exitCode);
}

function fallback() {
  try {
    const r = spawnSync(process.env.SHELL || 'bash', ['-c', originalCmd], {
      encoding: 'utf8', stdio: 'inherit', timeout: 120000
    });
    process.exit(r.status || 0);
  } catch (e) {
    process.exit(1);
  }
}

// --- Pre-processing ---

function preProcess(cmd, type) {
  switch (type) {
    case 'git-status':
      if (!/\s(-s|--short|--porcelain|--long|-v|--verbose)/.test(cmd))
        cmd = cmd.replace(/^(git\s+status)/, '$1 -sb');
      break;

    case 'git-log':
      if (!/--oneline|--format|--pretty/.test(cmd))
        cmd = cmd.replace(/^(git\s+log)/, '$1 --oneline');
      if (!/-n\s+\d+|--max-count|-\d+\b/.test(cmd))
        cmd += ` -${config.gitLogLimit}`;
      break;

    case 'git-branch':
      if (!/--(sort|format)/.test(cmd))
        cmd = cmd.replace(/^(git\s+branch)/, '$1 --sort=-committerdate');
      break;

    case 'docker':
      // docker logs: limit to last 100 lines if no --tail
      if (/^docker\s+logs\s/.test(cmd) && !/(--tail|--since|--until|-n\s)/.test(cmd))
        cmd += ' --tail 100';
      break;
  }
  return cmd;
}

// --- Git diff --stat header ---

function buildDiffStatHeader(diffCmd, shell, opts) {
  try {
    // Build equivalent --stat command: insert --stat after 'diff'
    const statCmd = diffCmd.replace(/^(git(\s+-C\s+\S+)*\s+diff)/, '$1 --stat');
    const r = spawnSync(shell, ['-c', statCmd], { ...opts, timeout: 5000 });
    const stat = stripAnsi(r.stdout || '').trim();
    if (!stat) return '';
    const lines = stat.split('\n');
    // Only use header if diff will actually be truncated (avoid duplication)
    // We'll decide in postProcess whether to show it
    return stat + '\n';
  } catch (e) {
    return '';
  }
}

// --- Post-processing ---

function postProcess(output, type, statHeader) {
  if (!output) return output;
  const lines = output.split('\n');

  switch (type) {
    case 'git-diff':
    case 'git-show': {
      const max = type === 'git-diff' ? config.maxLines.gitDiff : config.maxLines.gitShow;
      if (lines.length > max) {
        const truncated = lines.slice(0, max).join('\n') +
          `\n\n[... truncated ${lines.length - max} more lines. Use \`git diff -- <file>\` for a specific file]\n`;
        // Prepend --stat summary so Claude knows which files changed even in a truncated diff
        if (statHeader) {
          return `=== Changed files ===\n${statHeader}\n=== Diff (first ${max} lines) ===\n` + truncated;
        }
        return truncated;
      }
      return output;
    }

    case 'git-log':
      if (lines.length > config.maxLines.gitLog)
        return lines.slice(0, config.maxLines.gitLog).join('\n') +
          `\n[... truncated. Use \`git log -n N\` for specific count]\n`;
      return output;

    case 'pkg-install': {
      if (lines.length > 30) {
        const summaryIdx = findLastIndex(lines, l =>
          /added|removed|up to date|already satisfied|Successfully installed|packages in/i.test(l)
        );
        if (summaryIdx > 10) {
          const summary = lines.slice(Math.max(0, summaryIdx - 5));
          return `[... filtered ${lines.length - summary.length} lines of install output]\n` + summary.join('\n');
        }
        return `[... filtered ${lines.length - 20} lines of install output]\n` + lines.slice(-20).join('\n');
      }
      return output;
    }

    case 'test':
      return lines.length > config.maxLines.test ? filterTestOutput(lines) : output;

    case 'build':
      return lines.length > config.maxLines.build ? filterBuildOutput(lines) : output;

    case 'lint':
      if (lines.length > config.maxLines.lint)
        return lines.slice(0, config.maxLines.lint).join('\n') +
          `\n[... truncated ${lines.length - config.maxLines.lint} more lint messages]\n`;
      return output;

    case 'gh':
      return filterGhOutput(lines);

    case 'docker':
      return filterDockerOutput(lines, output);

    default:
      return output;
  }
}

// --- gh CLI filter ---
// gh output uses box-drawing chars, ANSI color, wide padding — strip all decoration
function filterGhOutput(lines) {
  if (lines.length <= 30) return lines.join('\n');

  const kept = lines.filter(l => {
    const t = l.trim();
    // Drop pure decoration lines (box borders, separators)
    if (/^[─━╌┄┈─=\-\s]+$/.test(t)) return false;
    if (!t) return false;
    return true;
  });

  // Truncate to 100 lines max (gh tables can be huge)
  if (kept.length > 100)
    return kept.slice(0, 100).join('\n') + `\n[... truncated ${kept.length - 100} more rows]\n`;

  return kept.join('\n');
}

// --- docker filter ---
function filterDockerOutput(lines, raw) {
  // docker ps / images: keep all (usually compact), just strip ANSI (already done) and truncate
  if (lines.length <= config.maxLines.docker) return raw;

  // docker logs can be huge: already limited via --tail 100 in preProcess
  // but if still large, truncate
  return lines.slice(-config.maxLines.docker).join('\n') +
    `\n[... showing last ${config.maxLines.docker} lines]\n`;
}

// --- Test output filter ---
function filterTestOutput(lines) {
  const kept = [];
  let inFailure = false;
  let skippedCount = 0;

  for (const line of lines) {
    const isFailure  = /fail|error|assert|expect.*to|panic|exception|traceback/i.test(line);
    const isSummary  = /tests?\s+(passed|failed|ran|result|suite)|total:|summary|(\d+\s+(passing|failing|passed|failed))/i.test(line);
    const isEmpty    = line.trim() === '';
    const isIndented = /^\s{2,}/.test(line);

    if (isFailure || isSummary || isEmpty) {
      inFailure = isFailure;
      kept.push(line);
    } else if (inFailure && isIndented) {
      kept.push(line);
    } else if (inFailure && !isIndented) {
      inFailure = false;
      skippedCount++;
    } else {
      skippedCount++;
    }
  }

  if (skippedCount > 0)
    return `[... filtered ${skippedCount} lines of passing tests]\n\n` + kept.join('\n');
  return kept.join('\n');
}

// --- Build output filter ---
function filterBuildOutput(lines) {
  const kept = [];
  let skippedCount = 0;

  for (const line of lines) {
    const isImportant = /error|warning|warn|fail|Error|Warning|FAILED|cannot find|not found|undefined|unused/i.test(line);
    const isSummary   = /^(Build|Compil|Finish|Success|FAILED|\d+ error|\d+ warning|Done in)/i.test(line.trim());
    const isEmpty     = line.trim() === '';
    const isPointer   = /^\s*[~^]+\s*$/.test(line);

    if (isImportant || isSummary || isEmpty || isPointer) kept.push(line);
    else skippedCount++;
  }

  if (skippedCount > 0)
    return `[... filtered ${skippedCount} lines of build output, showing errors/warnings only]\n\n` + kept.join('\n');
  return kept.join('\n');
}

// --- Tee mode: save full output on failure ---
function saveTee(cmd, fullOutput) {
  try {
    if (!fs.existsSync(TEE_DIR)) fs.mkdirSync(TEE_DIR, { recursive: true });

    // Rotate: keep only last N files
    const files = fs.readdirSync(TEE_DIR)
      .filter(f => f.endsWith('.log'))
      .map(f => ({ f, t: fs.statSync(path.join(TEE_DIR, f)).mtimeMs }))
      .sort((a, b) => a.t - b.t);

    while (files.length >= config.teeMaxFiles) {
      fs.unlinkSync(path.join(TEE_DIR, files.shift().f));
    }

    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const cmdSlug = cmd.slice(0, 40).replace(/[^a-z0-9_-]/gi, '_');
    const teeFile = path.join(TEE_DIR, `${ts}_${cmdSlug}.log`);

    fs.writeFileSync(teeFile, `Command: ${cmd}\n\n${fullOutput}`);

    // Append reference to stdout so Claude knows where to find full output
    process.stdout.write(
      `\n[Full output saved: ${teeFile.replace(/\\/g, '/')}\n` +
      ` Use Read tool or \`cat "${teeFile.replace(/\\/g, '/')}"\` to see complete output]\n`
    );
  } catch (e) { /* ignore */ }
}

// --- Utilities ---
function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b\([A-B]/g, '');
}

function collapseBlankLines(str) {
  return str.replace(/\n{3,}/g, '\n\n');
}

function truncateLines(str, maxWidth) {
  if (!maxWidth || maxWidth <= 0) return str;
  return str.split('\n').map(l => l.length > maxWidth ? l.slice(0, maxWidth) + ' [...]' : l).join('\n');
}

function hardCap(str, maxChars) {
  if (str.length > maxChars) {
    const lines = str.slice(0, maxChars).split('\n');
    lines.pop();
    return lines.join('\n') + `\n\n[... output truncated at ${maxChars} chars. Total was ${str.length} chars]\n`;
  }
  return str;
}

function findLastIndex(arr, fn) {
  for (let i = arr.length - 1; i >= 0; i--) if (fn(arr[i])) return i;
  return -1;
}

// --- Tracking ---
function track(cmd, type, rawLen, filtLen) {
  try {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    const savedPct = rawLen > 0 ? Math.round((1 - filtLen / rawLen) * 100) : 0;
    fs.appendFileSync(LOG_FILE, JSON.stringify({
      ts: new Date().toISOString(),
      cmd: cmd.slice(0, 120),
      type, rawChars: rawLen, filtChars: filtLen, savedPct
    }) + '\n');
  } catch (e) { /* ignore */ }
}
