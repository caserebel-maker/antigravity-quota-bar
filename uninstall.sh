#!/bin/bash
echo "🛑 Uninstalling AntigravityQuota..."

# 1. Stop the app
pkill AntigravityQuota || true

# 2. Remove LaunchAgent
PLIST_PATH="$HOME/Library/LaunchAgents/com.ebci.antigravity-quota-bar.plist"
if [ -f "$PLIST_PATH" ]; then
    echo "🗑️ Removing LaunchAgent..."
    rm "$PLIST_PATH"
fi

# 3. Clean up installation folder
INSTALL_DIR="$HOME/Library/Application Support/AntigravityQuotaBar"
if [ -d "$INSTALL_DIR" ]; then
    echo "🗑️ Removing binary directory..."
    rm -rf "$INSTALL_DIR"
fi

echo "✅ AntigravityQuota successfully uninstalled!"
