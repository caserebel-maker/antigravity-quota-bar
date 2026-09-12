#!/usr/bin/env node
const { execSync } = require('child_process');
const https = require('https');
const http = require('http');

async function main() {
  try {
    const psOut = execSync('ps aux', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
    const lines = psOut.split('\n');
    let pid = null;
    let csrfToken = null;

    for (const line of lines) {
      if (line.includes('language_server') && line.includes('--csrf_token')) {
        const parts = line.trim().split(/\s+/);
        pid = parseInt(parts[1], 10);
        const match = line.match(/--csrf_token\s+([^\s]+)/);
        if (match) {
          csrfToken = match[1];
        }
        break;
      }
    }

    if (!pid || !csrfToken) {
      throw new Error('Antigravity language server process not found');
    }

    const lsofOut = execSync(`lsof -nP -iTCP -sTCP:LISTEN -a -p ${pid}`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
    const ports = [];
    for (const line of lsofOut.split('\n')) {
      const match = line.match(/:(\d+)\s+\(LISTEN\)/);
      if (match) {
        const port = parseInt(match[1], 10);
        if (!ports.includes(port)) {
          ports.push(port);
        }
      }
    }

    if (ports.length === 0) {
      throw new Error('No listening ports found for Antigravity');
    }

    let workingBaseUrl = null;
    for (const port of ports) {
      const isHttps = await probePort(port, csrfToken, true);
      if (isHttps) {
        workingBaseUrl = `https://127.0.0.1:${port}`;
        break;
      }
      const isHttp = await probePort(port, csrfToken, false);
      if (isHttp) {
        workingBaseUrl = `http://127.0.0.1:${port}`;
        break;
      }
    }

    if (!workingBaseUrl) {
      throw new Error('Could not find active Connect RPC port');
    }

    const [userStatus, quotaSummary] = await Promise.all([
      rpcRequest(workingBaseUrl, '/exa.language_server_pb.LanguageServerService/GetUserStatus', csrfToken),
      rpcRequest(workingBaseUrl, '/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary', csrfToken)
    ]);

    const result = {
      timestamp: new Date().toISOString(),
      method: 'local',
      email: userStatus?.userStatus?.email || userStatus?.email || 'User',
      models: []
    };

    // Extract weekly & 5h summary pools
    const groups = quotaSummary?.response?.groups || quotaSummary?.groups;
    if (Array.isArray(groups)) {
      for (const group of groups) {
        const groupName = group.displayName || '';
        for (const bucket of group.buckets || []) {
          const resetTime = bucket.resetTime;
          let timeUntilResetMs = undefined;
          if (resetTime) {
            const diff = new Date(resetTime).getTime() - Date.now();
            timeUntilResetMs = diff > 0 ? diff : undefined;
          }
          const isWeekly = bucket.window === 'weekly' || (bucket.displayName && bucket.displayName.toLowerCase().includes('weekly'));
          const windowLabel = isWeekly ? 'Weekly' : '5h';
          let label = '';
          if (groupName.toLowerCase().includes('gemini')) {
            label = `Gemini ${windowLabel}`;
          } else if (groupName.toLowerCase().includes('claude') || groupName.toLowerCase().includes('gpt')) {
            label = `Claude/GPT ${windowLabel}`;
          } else {
            label = `${groupName} ${windowLabel}`;
          }

          result.models.push({
            label,
            modelId: bucket.bucketId || label,
            remainingPercentage: typeof bucket.remainingFraction === "number" ? bucket.remainingFraction : undefined,
            isExhausted: bucket.remainingFraction === 0,
            resetTime,
            timeUntilResetMs
          });
        }
      }
    }

    // Extract individual client models
    const clientConfigs = userStatus?.userStatus?.cascadeModelConfigData?.clientModelConfigs ||
                          userStatus?.cascadeModelConfigData?.clientModelConfigs;
    if (Array.isArray(clientConfigs)) {
      for (const m of clientConfigs) {
        const quotaInfo = m.quotaInfo;
        const remainingFraction = typeof quotaInfo?.remainingFraction === 'number' ? quotaInfo.remainingFraction : undefined;
        const resetTime = typeof quotaInfo?.resetTime === 'string' ? quotaInfo.resetTime : undefined;
        let timeUntilResetMs = undefined;
        if (resetTime) {
          const diff = new Date(resetTime).getTime() - Date.now();
          timeUntilResetMs = diff > 0 ? diff : undefined;
        }

        result.models.push({
          label: m.label || m.modelOrAlias?.model || 'unknown',
          modelId: m.modelOrAlias?.model || 'unknown',
          remainingPercentage: remainingFraction,
          isExhausted: remainingFraction === 0,
          resetTime,
          timeUntilResetMs
        });
      }
    }

    console.log(JSON.stringify(result, null, 2));
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

function probePort(port, csrfToken, isHttps) {
  return new Promise((resolve) => {
    const protocol = isHttps ? https : http;
    const req = protocol.request({
      hostname: '127.0.0.1',
      port,
      path: '/exa.language_server_pb.LanguageServerService/GetUnleashData',
      method: 'POST',
      timeout: 1000,
      rejectUnauthorized: false,
      headers: {
        'Content-Type': 'application/json',
        'Connect-Protocol-Version': '1',
        ...(csrfToken ? { 'X-Codeium-Csrf-Token': csrfToken } : {})
      }
    }, (res) => {
      resolve(res.statusCode === 200 || res.statusCode === 401);
      res.resume();
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.write(JSON.stringify({ wrapper_data: {} }));
    req.end();
  });
}

function rpcRequest(baseUrl, path, csrfToken) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const protocol = url.protocol === 'https:' ? https : http;
    const req = protocol.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      timeout: 5000,
      rejectUnauthorized: false,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connect-Protocol-Version': '1',
        'X-Codeium-Csrf-Token': csrfToken
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch {
            resolve(null);
          }
        } else {
          resolve(null);
        }
      });
    });
    req.on('error', err => reject(err));
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Timeout'));
    });
    req.write(JSON.stringify({ metadata: { ideName: 'antigravity', extensionName: 'antigravity', locale: 'en' } }));
    req.end();
  });
}

main();
