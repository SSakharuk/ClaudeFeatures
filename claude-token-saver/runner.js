#!/usr/bin/env node
'use strict';

// Token-saving filter runner
// Executes the original command, filters output, tracks savings
// Zero external dependencies — pure Node.js

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DATA_DIR = path.join(os.homedir(), '.claude-token-saver');
const LOG_FILE = path.join(DATA_DIR, 'log.jsonl');
const CONFIG_FILE = path.join(__dirname, 'config.json');

// Load config with defaults
const DEFAULT_CONFIG = {
  maxLines: { gitDiff: 500, gitShow: 500, gitLog: 100, test: 200, build: 150, lint: 300 },
  maxLineWidth: 500,
  maxTotalChars: 80000,
  gitLogLimit: 30,
  enabled: true
};

let config = DEFAULT_CONFIG;
try {
  const userConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  config = { ...DEFAULT_CONFIG, ...userConfig, maxLines: { ...DEFAULT_CONFIG.maxLines, ...(userConfig.maxLines || {}) } };
} catch (e) { /* use defaults */ }

// Parse arguments
const filterType = process.argv[2];
const originalCmd = Buffer.from(process.argv[3] || '', 'base64').toString('utf8');

if (!originalCmd) {
  process.stderr.write('claude-token-saver runner: no command provided\n');
  process.exit(1);
}

try {
  run();
} catch (e) {
  // Fallback: execute original command without filtering
  fallback();
}

function run() {
  const shell = process.env.SHELL || 'bash';
  const env = { ...process.env, GIT_PAGER: 'cat', PAGER: 'cat', NO_COLOR: '1' };
  const spawnOpts = { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024, env, timeout: 120000 };

  // Pre-execution command modification
  const cmd = preProcess(originalCmd, filterType);
  const wasPreProcessed = (cmd !== originalCmd);

  // Measure original output for accurate tracking (only when pre-processed)
  let rawLen;
  if (wasPreProcessed) {
    const rawResult = spawnSync(shell, ['-c', originalCmd], { ...spawnOpts, timeout: 5000 });
    rawLen = ((rawResult.stdout || '') + (rawResult.stderr || '')).length;
  }

  // Execute the (possibly modified) command
  const result = spawnSync(shell, ['-c', cmd], spawnOpts);

  let stdout = result.stdout || '';
  let stderr = result.stderr || '';
  if (rawLen === undefined) rawLen = stdout.length + stderr.length;

  // Filter pipeline
  stdout = stripAnsi(stdout);
  stderr = stripAnsi(stderr);
  stdout = postProcess(stdout, filterType);
  stdout = collapseBlankLines(stdout);
  stdout = truncateLines(stdout, config.maxLineWidth);
  stdout = hardCap(stdout, config.maxTotalChars);
  stderr = collapseBlankLines(stderr);

  const filtLen = stdout.length + stderr.length;

  // Track savings (raw = original command output, filt = final filtered output)
  track(originalCmd, filterType, rawLen, filtLen);

  // Output
  process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  process.exit(result.status || 0);
}

function fallback() {
  try {
    const result = spawnSync(process.env.SHELL || 'bash', ['-c', originalCmd], {
      encoding: 'utf8',
      stdio: 'inherit',
      timeout: 120000
    });
    process.exit(result.status || 0);
  } catch (e2) {
    process.exit(1);
  }
}

// --- Pre-processing: modify commands before execution ---

function preProcess(cmd, type) {
  switch (type) {
    case 'git-status':
      // Add -sb if no format flags present
      if (!/\s(-s|--short|--porcelain|--long|-v|--verbose)/.test(cmd)) {
        cmd = cmd.replace(/^(git\s+status)/, '$1 -sb');
      }
      break;

    case 'git-log':
      // Add --oneline if no custom format
      if (!/--oneline|--format|--pretty/.test(cmd)) {
        cmd = cmd.replace(/^(git\s+log)/, '$1 --oneline');
      }
      // Add count limit if none specified
      if (!/-n\s+\d+|--max-count|-\d+\b/.test(cmd)) {
        cmd += ` -${config.gitLogLimit}`;
      }
      break;

    case 'git-branch':
      // Sort by most recent
      if (!/--(sort|format)/.test(cmd)) {
        cmd = cmd.replace(/^(git\s+branch)/, '$1 --sort=-committerdate');
      }
      break;
  }
  return cmd;
}

// --- Post-processing: filter output after execution ---

function postProcess(output, type) {
  if (!output) return output;
  const lines = output.split('\n');

  switch (type) {
    case 'git-diff':
    case 'git-show': {
      const max = type === 'git-diff' ? config.maxLines.gitDiff : config.maxLines.gitShow;
      if (lines.length > max) {
        return lines.slice(0, max).join('\n') +
          `\n\n[... truncated ${lines.length - max} more lines. Use \`git diff -- <file>\` for a specific file]\n`;
      }
      return output;
    }

    case 'git-log': {
      if (lines.length > config.maxLines.gitLog) {
        return lines.slice(0, config.maxLines.gitLog).join('\n') +
          `\n[... truncated. Use \`git log -n N\` for specific count]\n`;
      }
      return output;
    }

    case 'pkg-install': {
      if (lines.length > 30) {
        // Find summary line
        const summaryIdx = findLastIndex(lines, l =>
          /added|removed|up to date|already satisfied|Successfully installed|packages in/i.test(l)
        );
        if (summaryIdx > 10) {
          const summary = lines.slice(Math.max(0, summaryIdx - 5));
          return `[... filtered ${lines.length - summary.length} lines of install output]\n` +
            summary.join('\n');
        }
        // Fallback: keep last 20 lines
        return `[... filtered ${lines.length - 20} lines of install output]\n` +
          lines.slice(-20).join('\n');
      }
      return output;
    }

    case 'test': {
      if (lines.length > config.maxLines.test) {
        return filterTestOutput(lines);
      }
      return output;
    }

    case 'build': {
      if (lines.length > config.maxLines.build) {
        return filterBuildOutput(lines);
      }
      return output;
    }

    case 'lint': {
      if (lines.length > config.maxLines.lint) {
        return lines.slice(0, config.maxLines.lint).join('\n') +
          `\n[... truncated ${lines.length - config.maxLines.lint} more lint messages]\n`;
      }
      return output;
    }

    default:
      return output;
  }
}

// --- Test output filter ---

function filterTestOutput(lines) {
  const kept = [];
  let inFailure = false;
  let skippedCount = 0;

  for (const line of lines) {
    const lower = line.toLowerCase();
    const isFailure = /fail|error|assert|expect.*to|panic|exception|traceback/i.test(line);
    const isSummary = /tests?\s+(passed|failed|ran|result|suite)|total:|summary|(\d+\s+(passing|failing|passed|failed))/i.test(line);
    const isEmpty = line.trim() === '';
    const isIndented = /^\s{2,}/.test(line); // Stack traces

    if (isFailure || isSummary || isEmpty) {
      inFailure = isFailure;
      kept.push(line);
    } else if (inFailure && isIndented) {
      kept.push(line); // Stack trace continuation
    } else if (inFailure && !isIndented) {
      inFailure = false;
      skippedCount++;
    } else {
      skippedCount++;
    }
  }

  if (skippedCount > 0) {
    return `[... filtered ${skippedCount} lines of passing tests]\n\n` + kept.join('\n');
  }
  return kept.join('\n');
}

// --- Build output filter ---

function filterBuildOutput(lines) {
  const kept = [];
  let skippedCount = 0;

  for (const line of lines) {
    const isImportant = /error|warning|warn|fail|Error|Warning|FAILED|cannot find|not found|undefined|unused/i.test(line);
    const isSummary = /^(Build|Compil|Finish|Success|FAILED|\d+ error|\d+ warning|Done in)/i.test(line.trim());
    const isEmpty = line.trim() === '';
    const isPointer = /^\s*[~^]+\s*$/.test(line); // Error pointer lines like ~~~^^

    if (isImportant || isSummary || isEmpty || isPointer) {
      kept.push(line);
    } else {
      skippedCount++;
    }
  }

  if (skippedCount > 0) {
    return `[... filtered ${skippedCount} lines of build output, showing errors/warnings only]\n\n` + kept.join('\n');
  }
  return kept.join('\n');
}

// --- Utility functions ---

function stripAnsi(str) {
  // Covers: colors, cursor movement, erase, SGR, OSC sequences
  return str.replace(/\x1b\[[0-9;]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b\([A-B]/g, '');
}

function collapseBlankLines(str) {
  return str.replace(/\n{3,}/g, '\n\n');
}

function truncateLines(str, maxWidth) {
  if (!maxWidth || maxWidth <= 0) return str;
  return str.split('\n').map(line =>
    line.length > maxWidth ? line.slice(0, maxWidth) + ' [...]' : line
  ).join('\n');
}

function hardCap(str, maxChars) {
  if (str.length > maxChars) {
    const lines = str.slice(0, maxChars).split('\n');
    // Don't cut mid-line
    lines.pop();
    return lines.join('\n') +
      `\n\n[... output truncated at ${maxChars} chars. Total was ${str.length} chars]\n`;
  }
  return str;
}

function findLastIndex(arr, fn) {
  for (let i = arr.length - 1; i >= 0; i--) {
    if (fn(arr[i])) return i;
  }
  return -1;
}

// --- Tracking ---

function track(cmd, type, rawLen, filtLen) {
  try {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    const savedPct = rawLen > 0 ? Math.round((1 - filtLen / rawLen) * 100) : 0;
    const entry = JSON.stringify({
      ts: new Date().toISOString(),
      cmd: cmd.slice(0, 120),
      type,
      rawChars: rawLen,
      filtChars: filtLen,
      savedPct
    }) + '\n';
    fs.appendFileSync(LOG_FILE, entry);
  } catch (e) { /* ignore tracking errors */ }
}
