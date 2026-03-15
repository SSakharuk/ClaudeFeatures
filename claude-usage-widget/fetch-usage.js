/**
 * fetch-usage.js
 * Makes a minimal Haiku API call (1 token) to read rate-limit response headers.
 * Outputs a JSON object to stdout. Called by widget.ps1 on each refresh.
 */
'use strict';
const fs    = require('fs');
const https = require('https');

// Read OAuth credentials (file may be UTF-16 LE with BOM)
let raw = fs.readFileSync(process.env.USERPROFILE + '\\.claude\\.credentials.json');
if (raw[0] === 0xFF && raw[1] === 0xFE) raw = raw.slice(2).toString('utf16le');
else raw = raw.toString('utf8').replace(/^\uFEFF/, '');

const creds = JSON.parse(raw);
const token = creds.claudeAiOauth.accessToken;
const subType = creds.claudeAiOauth.subscriptionType || 'unknown';

const body = JSON.stringify({
    model:      'claude-haiku-4-5-20251001',
    max_tokens: 1,
    messages:   [{ role: 'user', content: '.' }]
});

const req = https.request({
    hostname: 'api.anthropic.com',
    path:     '/v1/messages',
    method:   'POST',
    headers: {
        'Authorization':     `Bearer ${token}`,
        'Content-Type':      'application/json',
        'anthropic-version': '2023-06-01',
        'anthropic-beta':    'oauth-2025-04-20',
        'Content-Length':    Buffer.byteLength(body)
    }
}, (res) => {
    const h = res.headers;

    const out = {
        subscription: subType,
        session5h: {
            utilization: parseFloat(h['anthropic-ratelimit-unified-5h-utilization'] || '0'),
            resetAt:     parseInt(h['anthropic-ratelimit-unified-5h-reset']         || '0', 10),
            status:      h['anthropic-ratelimit-unified-5h-status'] || 'unknown'
        },
        weekly7d: {
            utilization: parseFloat(h['anthropic-ratelimit-unified-7d-utilization'] || '0'),
            resetAt:     parseInt(h['anthropic-ratelimit-unified-7d-reset']          || '0', 10),
            status:      h['anthropic-ratelimit-unified-7d-status'] || 'unknown'
        },
        overageStatus: h['anthropic-ratelimit-unified-overage-status'] || 'unknown'
    };

    res.on('data', () => {}); // drain
    res.on('end',  () => process.stdout.write(JSON.stringify(out)));
});

req.on('error', (e) => { process.stderr.write(e.message); process.exit(1); });
req.write(body);
req.end();
