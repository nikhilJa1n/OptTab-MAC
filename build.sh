#!/bin/bash
set -e

echo "=== Building Swift Package in Release Mode ==="
swift build -c release

echo "=== Packaging into AdvancedDock.app ==="
APP_NAME="AdvancedDock"
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
    <string>com.nikhiljain.AdvancedDock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
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
echo "=== Signing App Bundle with AdvancedDockDeveloper Certificate ==="
codesign --force --deep --sign "AdvancedDockDeveloper" "${APP_DIR}"

echo "=== App Bundle created successfully at ${APP_DIR} ==="

# Create DMG Installer
echo "=== Creating DMG Installer ==="
DMG_NAME="AdvancedDock"
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
