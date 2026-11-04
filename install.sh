#!/bin/bash
set -e

cd "$(dirname "$0")"

chmod +x build.sh
./build.sh

echo "🛑 Stopping any existing AntigravityQuota instances..."
pkill -f AntigravityQuota || true

INSTALL_DIR="$HOME/Library/Application Support/AntigravityQuotaBar"
APP_DIR="$INSTALL_DIR/Antigravity Quota.app"
mkdir -p "$APP_DIR/Contents/MacOS"

echo "📦 Installing .app bundle & helpers to: $INSTALL_DIR"
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ebci.antigravity-quota-bar</string>
    <key>CFBundleName</key>
    <string>Antigravity Quota</string>
    <key>CFBundleDisplayName</key>
    <string>Antigravity Quota</string>
    <key>CFBundleExecutable</key>
    <string>AntigravityQuota</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

cp AntigravityQuota "$APP_DIR/Contents/MacOS/AntigravityQuota"
cp AntigravityQuota "$INSTALL_DIR/AntigravityQuota"
cp fetch-quota.js "$INSTALL_DIR/fetch-quota.js"
chmod +x "$INSTALL_DIR/fetch-quota.js"
if [ -f fetch-claude-quota.js ]; then
    cp fetch-claude-quota.js "$INSTALL_DIR/fetch-claude-quota.js"
    chmod +x "$INSTALL_DIR/fetch-claude-quota.js"
fi
if [ -f sync-cloud.sh ]; then
    cp sync-cloud.sh "$INSTALL_DIR/sync-cloud.sh"
    chmod +x "$INSTALL_DIR/sync-cloud.sh"
fi

echo "🔑 Signing binary & app bundle..."
codesign -f -s - "$APP_DIR"
codesign -f -s - "$INSTALL_DIR/AntigravityQuota"

PLIST_PATH="$HOME/Library/LaunchAgents/com.ebci.antigravity-quota-bar.plist"
cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ebci.antigravity-quota-bar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DIR/Contents/MacOS/AntigravityQuota</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

echo "🚀 Reloading LaunchAgent..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH" 2>/dev/null || true

echo "🎉 AntigravityQuota successfully installed as Antigravity Quota.app and started!"
echo "Check your menu bar (top right) for the 🧠 icon!"
