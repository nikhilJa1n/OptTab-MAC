#!/bin/bash
set -e

# Production Versioning Defaults
VERSION="1.6"
BUILD_NUMBER="1"

# Read version and build arguments if provided
if [ ! -z "$1" ]; then
    VERSION="$1"
fi
if [ ! -z "$2" ]; then
    BUILD_NUMBER="$2"
fi

echo "=== Building Swift Package in Release Mode ==="
swift build -c release

echo "=== Packaging into OptTab.app ==="
APP_NAME="OptTab"
APP_DIR="${APP_NAME}.app"

# Create directories
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary & resources
cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikhiljain.OptTab</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>OptTab needs to send Apple Events to switch between windows of applications like Google Chrome.</string>
</dict>
</plist>
EOF

# Sign the app bundle
echo "=== Signing App Bundle with OptTabDeveloper Certificate ==="
codesign --force --deep --sign "OptTabDeveloper" "${APP_DIR}"

echo "=== App Bundle created successfully at ${APP_DIR} ==="

# Create DMG Installer
echo "=== Creating DMG Installer ==="
DMG_NAME="OptTab"
DMG_FILE="${DMG_NAME}.dmg"

# Remove old DMG if exists
rm -f "${DMG_FILE}"

# Create a temporary staging directory
STAGING_DIR="dmg_staging"
mkdir -p "${STAGING_DIR}"

# Copy the app bundle
cp -R "${APP_DIR}" "${STAGING_DIR}/"

# Create a symlink to /Applications for easy drag-and-drop installation
ln -s /Applications "${STAGING_DIR}/Applications"

# Create the DMG using hdiutil
hdiutil create -volname "${DMG_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_FILE}"

# Clean up staging directory
rm -rf "${STAGING_DIR}"

echo "=== DMG created successfully at ${DMG_FILE} ==="

# Automatically install and relaunch the app if not packaging a release
if [ "$SKIP_RELAUNCH" != "true" ]; then
    echo "=== Installing and Relaunching ${APP_NAME}.app ==="
    killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_DIR}" "/Applications/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${APP_NAME}.app" 2>/dev/null || true
    sleep 0.5
    open "/Applications/${APP_NAME}.app"
    echo "=== ${APP_NAME}.app successfully installed and launched! ==="
fi
