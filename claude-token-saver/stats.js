#!/usr/bin/env node
'use strict';

// Token savings statistics viewer
// Usage: node stats.js [--today | --week | --all | --reset]

const fs = require('fs');
const path = require('path');
const os = require('os');

const LOG_FILE = path.join(os.homedir(), '.claude-token-saver', 'log.jsonl');
const args = process.argv.slice(2);

if (args.includes('--reset')) {
  try { fs.unlinkSync(LOG_FILE); } catch (e) {}
  console.log('Tracking log cleared.');
  process.exit(0);
}

if (!fs.existsSync(LOG_FILE)) {
  console.log('No tracking data yet. Start using Claude Code with the token saver hook active.');
  process.exit(0);
}

// Parse log entries
const entries = fs.readFileSync(LOG_FILE, 'utf8')
  .split('\n')
  .filter(Boolean)
  .map(line => { try { return JSON.parse(line); } catch (e) { return null; } })
  .filter(Boolean);

if (entries.length === 0) {
  console.log('No tracking data yet.');
  process.exit(0);
}

// Filter by time period
const now = Date.now();
const DAY = 24 * 60 * 60 * 1000;
let filtered = entries;
let periodLabel = 'All time';

if (args.includes('--today')) {
  const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
  filtered = entries.filter(e => new Date(e.ts).getTime() >= startOfDay.getTime());
  periodLabel = 'Today';
} else if (args.includes('--week')) {
  filtered = entries.filter(e => now - new Date(e.ts).getTime() < 7 * DAY);
  periodLabel = 'Last 7 days';
} else if (!args.includes('--all')) {
  // Default: last 7 days
  filtered = entries.filter(e => now - new Date(e.ts).getTime() < 7 * DAY);
  periodLabel = 'Last 7 days';
}

if (filtered.length === 0) {
  console.log(`No data for period: ${periodLabel}`);
  process.exit(0);
}

// Calculate statistics
const totalRaw = filtered.reduce((s, e) => s + (e.rawChars || 0), 0);
const totalFilt = filtered.reduce((s, e) => s + (e.filtChars || 0), 0);
const totalSaved = totalRaw - totalFilt;
const avgPct = totalRaw > 0 ? Math.round((1 - totalFilt / totalRaw) * 100) : 0;

// By type
const byType = {};
for (const e of filtered) {
  if (!byType[e.type]) byType[e.type] = { count: 0, rawChars: 0, filtChars: 0 };
  byType[e.type].count++;
  byType[e.type].rawChars += e.rawChars || 0;
  byType[e.type].filtChars += e.filtChars || 0;
}

// Estimate tokens (rough: 1 token ≈ 4 chars for English, 3 for code)
const estTokensSaved = Math.round(totalSaved / 3.5);

// Print report
console.log('');
console.log('=== Claude Token Saver — Statistics ===');
console.log(`Period: ${periodLabel}`);
console.log('');
console.log(`  Commands filtered:    ${filtered.length}`);
console.log(`  Total chars saved:    ${formatNum(totalSaved)} (${avgPct}% reduction)`);
console.log(`  Est. tokens saved:    ~${formatNum(estTokensSaved)}`);
console.log(`  Raw output total:     ${formatNum(totalRaw)} chars`);
console.log(`  Filtered output:      ${formatNum(totalFilt)} chars`);
console.log('');
console.log('  By command type:');

const sortedTypes = Object.entries(byType).sort((a, b) => (b[1].rawChars - b[1].filtChars) - (a[1].rawChars - a[1].filtChars));
for (const [type, data] of sortedTypes) {
  const saved = data.rawChars - data.filtChars;
  const pct = data.rawChars > 0 ? Math.round((1 - data.filtChars / data.rawChars) * 100) : 0;
  console.log(`    ${padRight(type, 14)} ${padLeft(String(data.count), 4)} cmds  ${padLeft(formatNum(saved), 10)} chars saved  (avg ${pct}%)`);
}

// Last 10 commands
console.log('');
console.log('  Last 10 filtered commands:');
const last10 = filtered.slice(-10);
for (const e of last10) {
  const saved = (e.rawChars || 0) - (e.filtChars || 0);
  const pct = e.savedPct || 0;
  const cmdShort = (e.cmd || '').slice(0, 50);
  console.log(`    ${cmdShort.padEnd(52)} ${padLeft(formatNum(e.rawChars || 0), 8)} → ${padLeft(formatNum(e.filtChars || 0), 8)}  (${pct}% saved)`);
}
console.log('');

function formatNum(n) {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function padRight(str, len) {
  return str.length >= len ? str : str + ' '.repeat(len - str.length);
}

function padLeft(str, len) {
  return str.length >= len ? str : ' '.repeat(len - str.length) + str;
}
