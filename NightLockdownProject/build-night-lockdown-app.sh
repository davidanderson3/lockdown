#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
APP_NAME="LockdownReady"
APP_BUNDLE="$ROOT_DIR/${APP_NAME}.app"
SRC_FILE="$PROJECT_DIR/NightLockdownApp/Sources/main.swift"
BIN_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
PLIST_FILE="$APP_BUNDLE/Contents/Info.plist"
ICON_FILE="$PROJECT_DIR/NightLockdownApp/Assets/${APP_NAME}.icns"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "Source file not found: $SRC_FILE"
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$BIN_DIR" "$RESOURCES_DIR"

xcrun swiftc \
  "$SRC_FILE" \
  -o "$BIN_DIR/$APP_NAME" \
  -framework AppKit \
  -framework UserNotifications

chmod +x "$BIN_DIR/$APP_NAME"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/$APP_NAME.icns"
fi

cat > "$PLIST_FILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Lockdown Ready</string>
  <key>CFBundleDisplayName</key>
  <string>Lockdown Ready</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.lockdownready</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>LockdownReady</string>
  <key>CFBundleIconFile</key>
  <string>LockdownReady</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Lockdown Ready needs Apple Events access to quit distracting apps during locked hours.</string>
  <key>NSUserNotificationUsageDescription</key>
  <string>Lockdown Ready shows status notifications when lockdown is enforced.</string>
</dict>
</plist>
PLIST

if [[ "${1:-}" == "--install" ]]; then
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  echo "Installed: /Applications/$APP_NAME.app"
else
  echo "Built: $APP_BUNDLE"
  echo "Tip: run '$0 --install' to copy it to /Applications"
fi
