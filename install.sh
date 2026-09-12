#!/bin/bash
set -e

cd "$(dirname "$0")"

chmod +x build.sh
./build.sh

echo "🛑 Stopping any existing AntigravityQuota instances..."
pkill -f AntigravityQuota || true

INSTALL_DIR="$HOME/Library/Application Support/AntigravityQuotaBar"
mkdir -p "$INSTALL_DIR"

echo "📦 Installing binary & helper to: $INSTALL_DIR"
cp AntigravityQuota "$INSTALL_DIR/AntigravityQuota"
cp fetch-quota.js "$INSTALL_DIR/fetch-quota.js"
chmod +x "$INSTALL_DIR/fetch-quota.js"

echo "🔑 Signing binary in target folder..."
codesign -f -s - "$INSTALL_DIR/AntigravityQuota"

PLIST_PATH="$HOME/Library/LaunchAgents/com.ebci.antigravity-quota-bar.plist"
if [ -f "$PLIST_PATH" ]; then
    echo "🚀 Reloading LaunchAgent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH" 2>/dev/null || true
else
    echo "🚀 Starting single instance of AntigravityQuota..."
    nohup "$INSTALL_DIR/AntigravityQuota" > /dev/null 2>&1 &
fi

echo "🎉 AntigravityQuota successfully installed and started!"
echo "Check your menu bar (top right) for the ⚡ icon!"
