#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c debug

APP="FastScreenerMacSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/FastScreenerMacSpike "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"

echo "Built $APP"
