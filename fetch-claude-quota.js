#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME || '';
const CACHE_FILE = path.join(HOME, 'Library/Application Support/AntigravityQuotaBar/claude-app-usage.json');
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

  const cachedData = tryCachedFile();
  if (cachedData) {
    console.log(cachedData);
    process.exit(0);
  }

  process.exit(1);
}

main();
