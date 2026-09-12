# AntigravityQuotaBar ⚡

Lightweight macOS menu bar application to monitor Antigravity AI quotas and rate limits in real time.

## Features
- **Weekly & 5-Hour Limits**: Displays both weekly limit and 5-hour rolling pool for Gemini & Claude/GPT models.
- **Menu Bar Status**: Live remaining percentage directly in macOS status bar (`⚡ 74% (5h) · 87% (Wk)`).
- **Filtered & Clean**: Shows individual active models (Gemini 3.7/3.8, Claude Sonnet/Opus 4.6).
- **Codex Quotas**: Integrates local Codex session rate limits (5h & Weekly) if active.
- **Zero Dependencies**: Queries local Antigravity Language Server directly via Connect RPC.

## Quick Install (at home or office)

```bash
git clone https://github.com/caserebel-maker/antigravity-quota-bar.git
cd antigravity-quota-bar
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```
