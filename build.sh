#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🔨 Building AntigravityQuota..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

swiftc -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 main.swift -o AntigravityQuota

echo "🔑 Ad-hoc signing binary..."
codesign -f -s - AntigravityQuota

echo "✅ Compilation successful! Binary generated at $(pwd)/AntigravityQuota"
