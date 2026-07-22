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

# Get repository details from remote URL
REMOTE_URL=$(git config --get remote.origin.url || true)
OWNER="nikhilJa1n"
REPO="OptTab-MAC"
if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^.]+)(.git)? ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
fi

echo "=== Packaging OptTab for Release (Version: $VERSION, Build: $BUILD_NUMBER) ==="
export SKIP_RELAUNCH="true"
bash build.sh "$VERSION" "$BUILD_NUMBER"

# Check compile outputs
if [ ! -d "OptTab.app" ] || [ ! -f "OptTab.dmg" ]; then
    echo "Error: Build artifacts not generated correctly."
    exit 1
fi

# Create ZIP archive (.zip) as fallback
echo "=== Creating ZIP Archive (OptTab.zip) ==="
rm -f OptTab.zip
zip -r -y -q OptTab.zip OptTab.app

# Update update.json configuration only if explicit release notes are passed
if [ -n "$3" ]; then
    echo "=== Updating update.json ==="
    cat > update.json <<EOF
{
  "version": "$VERSION",
  "downloadUrl": "https://github.com/$OWNER/$REPO/releases/download/v$VERSION/OptTab.dmg",
  "changelog": "$3"
}
EOF
fi

# Summary
echo "=== Release Packages Created Successfully ==="
ls -lh OptTab.dmg OptTab.zip
