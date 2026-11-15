#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME || '';
const CACHE_FILE = path.join(HOME, 'Library/Application Support/AntigravityQuotaBar/claude-app-usage.json');
const CLAUDE_APP_HISTORY = path.join(HOME, 'Library/Application Support/Claude/plan-usage-history.json');
const SESSION_KEY_FILE = path.join(HOME, 'Library/Application Support/AntigravityQuotaBar/claude-session-key.txt');
const ALT_KEY_FILE = path.join(HOME, '.claude-session-key');
let ORG_ID = 'c1aad3f0-f1a4-419b-ac9b-3c18f4eb9bf3';

function getStoredSessionKey() {
  if (process.env.CLAUDE_SESSION_KEY && process.env.CLAUDE_SESSION_KEY.trim().length > 10) {
    return process.env.CLAUDE_SESSION_KEY.trim();
  }
  for (const file of [SESSION_KEY_FILE, ALT_KEY_FILE]) {
    if (fs.existsSync(file)) {
      try {
        const val = fs.readFileSync(file, 'utf8').trim();
        if (val.length > 10) return val;
      } catch (_) {}
    }
  }
  return null;
}

function resolveOrgId(key) {
  try {
    const cmd = `curl -s -m 5 "https://claude.ai/api/organizations" \
      -H "Cookie: sessionKey=${key}" \
      -H "Accept: application/json" \
      -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"`;
    const out = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'], timeout: 6000 }).trim();
    const orgs = JSON.parse(out);
    if (Array.isArray(orgs) && orgs.length > 0) {
      return orgs[0].uuid || orgs[0].id || ORG_ID;
    }
  } catch (_) {}
  return ORG_ID;
}

function tryDirectApiFetch(sessionKey) {
  if (!sessionKey) return null;
  let key = sessionKey.trim();
  if (key.startsWith('sessionKey=')) {
    key = key.substring('sessionKey='.length);
  }

  try {
    const org = resolveOrgId(key);
    const cmd = `curl -s -m 7 "https://claude.ai/api/organizations/${org}/usage" \
      -H "Cookie: sessionKey=${key}" \
      -H "Accept: application/json" \
      -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" \
      -H "Origin: https://claude.ai" \
      -H "Referer: https://claude.ai/"`;
    
    const out = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'], timeout: 8000 }).trim();
    if (out && out.startsWith('{') && out.includes('limits')) {
      try {
        fs.writeFileSync(CACHE_FILE, out, 'utf8');
      } catch (_) {}
      return out;
    }
  } catch (_) {}
  return null;
}

function tryBrowserFetch() {
  const browsers = ['Brave Browser', 'Google Chrome', 'Microsoft Edge', 'Safari'];
  
  for (const browser of browsers) {
    let script = '';
    if (browser === 'Safari') {
      script = `tell application "Safari"
  repeat with w in windows
    repeat with t in tabs of w
      if URL of t contains "claude.ai" then
        return (do JavaScript "(()=>{try{var x=new XMLHttpRequest();x.open(\\"GET\\",\\"/api/organizations/${ORG_ID}/usage\\",false);x.send(null);return x.responseText;}catch(e){return \\"\\";}})()" in t)
      end if
    end repeat
  end repeat
end tell`;
    } else {
      script = `tell application "${browser}"
  repeat with w in windows
    repeat with t in tabs of w
      if URL of t contains "claude.ai" then
        return (execute t javascript "(()=>{try{var x=new XMLHttpRequest();x.open(\\"GET\\",\\"/api/organizations/${ORG_ID}/usage\\",false);x.send(null);return x.responseText;}catch(e){return \\"\\";}})()")
      end if
    end repeat
  end repeat
end tell`;
    }

    try {
      const out = execSync('osascript', {
        input: script,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'ignore'],
        timeout: 5000
      }).trim();

      if (out && out.startsWith('{') && out.includes('limits')) {
        try {
          fs.writeFileSync(CACHE_FILE, out, 'utf8');
        } catch (_) {}
        return out;
      }
    } catch (_) {}
  }

  return null;
}

function tryClaudeAppHistory() {
  if (!fs.existsSync(CLAUDE_APP_HISTORY)) return null;
  try {
    const raw = fs.readFileSync(CLAUDE_APP_HISTORY, 'utf8');
    const data = JSON.parse(raw);
    if (!data.samples || data.samples.length === 0) return null;

    const latest = data.samples.reduce((prev, curr) => (curr.t > prev.t ? curr : prev), data.samples[0]);
    if (!latest || !latest.u) return null;

    const fh = typeof latest.u.fh === 'number' ? latest.u.fh : 0;
    const sd = typeof latest.u.sd === 'number' ? latest.u.sd : 0;
    const sampleTime = latest.t || Date.now();

    // 5-hour session reset calculation: 5h after limit start
    const fiveHourReset = new Date(Math.max(Date.now(), sampleTime + 5 * 3600 * 1000)).toISOString();

    // Weekly reset: next Sunday at 21:00 UTC
    const now = new Date();
    const dayOfWeek = now.getUTCDay(); // 0 is Sunday
    const daysUntilSunday = (7 - dayOfWeek) % 7;
    const nextSunday = new Date(now);
    nextSunday.setUTCDate(now.getUTCDate() + daysUntilSunday);
    nextSunday.setUTCHours(21, 0, 0, 0);
    if (nextSunday.getTime() <= now.getTime()) {
      nextSunday.setUTCDate(nextSunday.getUTCDate() + 7);
    }
    const weeklyReset = nextSunday.toISOString();

    return JSON.stringify({
      limits: [
        {
          kind: "session",
          group: "session",
          percent: fh,
          resets_at: fiveHourReset,
          is_active: fh >= 100
        },
        {
          kind: "weekly_all",
          group: "weekly",
          percent: sd,
          resets_at: weeklyReset,
          is_active: true
        }
      ]
    });
  } catch (_) {
    return null;
  }
}

function tryCachedFile() {
  if (fs.existsSync(CACHE_FILE)) {
    try {
      const content = fs.readFileSync(CACHE_FILE, 'utf8').trim();
      if (content.startsWith('{') && content.includes('limits')) {
        return content;
      }
    } catch (_) {}
  }
  return null;
}

function main() {
  // 1. Direct API Fetch using stored sessionKey (Highest accuracy, independent of browser/app)
  const sessionKey = getStoredSessionKey();
  if (sessionKey) {
    const directData = tryDirectApiFetch(sessionKey);
    if (directData) {
      console.log(directData);
      process.exit(0);
    }
  }

  // 2. Browser Tab Fetch via AppleScript
  const liveData = tryBrowserFetch();
  if (liveData) {
    console.log(liveData);
    process.exit(0);
  }

  // 3. Local Claude Desktop App usage history
  const appHistory = tryClaudeAppHistory();
  if (appHistory) {
    console.log(appHistory);
    process.exit(0);
  }

  // 4. Cached usage file fallback
  const cachedData = tryCachedFile();
  if (cachedData) {
    console.log(cachedData);
    process.exit(0);
  }

  process.exit(1);
}

main();
