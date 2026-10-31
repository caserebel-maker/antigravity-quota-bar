#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const https = require('https');

function getSessionKey() {
  const home = process.env.HOME || '';
  const envPaths = [
    path.join(home, '.env'),
    path.join(home, 'Library/Application Support/AntigravityQuotaBar/.env'),
    path.join(__dirname, '.env')
  ];

  for (const p of envPaths) {
    if (fs.existsSync(p)) {
      try {
        const content = fs.readFileSync(p, 'utf8');
        for (const line of content.split('\n')) {
          const trimmed = line.trim();
          if (trimmed.startsWith('CLAUDE_SESSION_KEY=')) {
            const val = trimmed.substring('CLAUDE_SESSION_KEY='.length).trim();
            if (val) return val.replace(/^["']|["']$/g, '');
          }
        }
      } catch (_) {}
    }
  }
  return null;
}

function request(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error('Invalid JSON response'));
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  const sessionKey = getSessionKey();
  if (!sessionKey) {
    process.exit(1);
  }

  const cookie = sessionKey.startsWith('sessionKey=') ? sessionKey : `sessionKey=${sessionKey}`;
  const headers = {
    'Cookie': cookie,
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json'
  };

  try {
    let orgId = 'c1aad3f0-f1a4-419b-ac9b-3c18f4eb9bf3';
    try {
      const orgs = await request('https://claude.ai/api/organizations', headers);
      if (Array.isArray(orgs) && orgs.length > 0) {
        orgId = orgs[0].uuid || orgId;
      }
    } catch (_) {}

    const usage = await request(`https://claude.ai/api/organizations/${orgId}/usage`, headers);
    console.log(JSON.stringify(usage));
  } catch (err) {
    process.stderr.write(`Error: ${err.message}\n`);
    process.exit(1);
  }
}

main();
