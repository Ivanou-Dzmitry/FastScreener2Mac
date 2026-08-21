#!/bin/bash
# Packages the SPM release build of FastScreenerMac into a real
# double-clickable .app bundle — the Mac equivalent of the Windows
# build's .exe. The resource bundle goes in the standard Contents/
# Resources location (AppResourceBundle.swift looks for it there);
# anything placed beside Contents/ instead makes codesign refuse the
# whole app with "unsealed contents present in the bundle root".
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1.0"
APP_NAME="FastScreener2 for Mac"
APP="$APP_NAME.app"

swift build -c release --product FastScreenerMac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FastScreenerMac "$APP/Contents/MacOS/"
cp Resources-App/Info.plist "$APP/Contents/Info.plist"
cp Resources-App/AppIcon.icns "$APP/Contents/Resources/"
cp -R .build/release/FastScreenerMac_FastScreenerMac.bundle "$APP/Contents/Resources/"

codesign --force --deep -s - "$APP"

ZIP="FastScreener2-for-Mac-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Built $APP and $ZIP"
