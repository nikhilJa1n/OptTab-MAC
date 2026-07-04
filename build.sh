#!/bin/bash
set -e

echo "=== Building Swift Package in Release Mode ==="
swift build -c release

echo "=== Packaging into AdvancedDock.app ==="
APP_NAME="AdvancedDock"
APP_DIR="${APP_NAME}.app"

# Create directories
mkdir -p "${APP_DIR}/Contents/MacOS"

# Copy binary
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikhiljain.AdvancedDock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Sign the app bundle
echo "=== Ad-hoc Signing App Bundle ==="
codesign --force --deep --sign - "${APP_DIR}"

echo "=== App Bundle created successfully at ${APP_DIR} ==="
