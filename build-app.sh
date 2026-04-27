#!/bin/bash
# Build a proper .app bundle from SPM executable
set -e

APP_NAME="Meeting Caller Mac"
BUNDLE_ID="com.silas.MeetingCallerMac"
EXECUTABLE="MeetingCallerMac"

echo "Building..."
swift build -c release 2>&1 | tail -3

APP_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "Creating app bundle at: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"

# Copy executable
cp ".build/release/$EXECUTABLE" "$MACOS/$EXECUTABLE"

# Create Info.plist with all required keys
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Meeting Caller Mac needs local network access to communicate with the ESP32 Meeting Master device.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_meeting-master._tcp</string>
    </array>
    <key>NSCameraUsageDescription</key>
    <string>Meeting Caller Mac monitors camera state to automatically control meetings.</string>
</dict>
</plist>
PLIST

echo "Done! App bundle created at: $APP_DIR"
echo "Opening app..."
open "$APP_DIR"
