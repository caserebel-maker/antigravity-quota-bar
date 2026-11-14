#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME || '';
const CACHE_FILE = path.join(HOME, 'Library/Application Support/AntigravityQuotaBar/claude-app-usage.json');
const CLAUDE_APP_HISTORY = path.join(HOME, 'Library/Application Support/Claude/plan-usage-history.json');
const ORG_ID = 'c1aad3f0-f1a4-419b-ac9b-3c18f4eb9bf3';

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
    const dayOfWeek = now.getUTCDay();
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
  const liveData = tryBrowserFetch();
  if (liveData) {
    console.log(liveData);
    process.exit(0);
  }

  const appHistory = tryClaudeAppHistory();
  if (appHistory) {
    console.log(appHistory);
    process.exit(0);
  }

  const cachedData = tryCachedFile();
  if (cachedData) {
    console.log(cachedData);
    process.exit(0);
  }

  process.exit(1);
}

main();
