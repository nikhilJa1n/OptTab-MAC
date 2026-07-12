#!/bin/bash
set -e

# Make sure we are in the repository root
cd "$(dirname "$0")"

# 1. Read current version from build.sh
VERSION=$(grep -E "<key>CFBundleShortVersionString</key>" -A 1 build.sh | tail -n 1 | sed -e 's/^[[:space:]]*//' -e 's/<string>//' -e 's/<\/string>//')
echo "Detected App Version: $VERSION"

# 2. Get repository info from git remote
REMOTE_URL=$(git config --get remote.origin.url || true)
if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^.]+)(.git)? ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
else
    echo "Error: Could not parse owner/repo from remote URL: $REMOTE_URL"
    exit 1
fi
echo "Repository Target: $OWNER/$REPO"

# 3. Prompt for GitHub Personal Access Token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Please enter your GitHub Personal Access Token (PAT):"
    read -r -s GITHUB_TOKEN
    echo ""
fi
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN is required."
    exit 1
fi

# Helper functions for API operations
github_api() {
    local method="$1"
    local path="$2"
    shift 2
    curl -s -X "$method" \
         -H "Authorization: token $GITHUB_TOKEN" \
         -H "Content-Type: application/json" \
         "$@" \
         "https://api.github.com/repos/$OWNER/$REPO$path"
}

get_json_val() {
    python3 -c "import json, sys; d=sys.stdin.read().strip(); print(json.loads(d).get('$1', '') if d else '')"
}

# 4. Build and Package
echo "=== Compiling and Packaging App ==="
./build.sh
DMG_FILE="AdvancedDock.dmg"
if [ ! -f "$DMG_FILE" ]; then
    echo "Error: DMG file not found."
    exit 1
fi

# 5. Update update.json
echo "=== Updating update.json ==="
cat > update.json <<EOF
{
  "version": "$VERSION",
  "downloadUrl": "https://github.com/$OWNER/$REPO/releases/download/v$VERSION/AdvancedDock.dmg",
  "changelog": "Released version $VERSION."
}
EOF

# 6. Commit, tag, and push locally
echo "=== Committing and tagging release locally ==="
git add update.json
git commit -m "Bump update.json to v$VERSION" || true
git tag -d "v$VERSION" 2>/dev/null || true
git tag -a "v$VERSION" -m "Release v$VERSION"

echo "=== Pushing commits and tag to GitHub ==="
git push origin main || true
git push origin -f "v$VERSION" || true

# 7. Check if release already exists on GitHub
echo "=== Managing GitHub Release ==="
RELEASE_INFO=$(github_api GET "/releases/tags/v$VERSION")
RELEASE_ID=$(echo "$RELEASE_INFO" | get_json_val id)

if [ -n "$RELEASE_ID" ]; then
    echo "Release v$VERSION already exists (ID: $RELEASE_ID). Reusing release..."
    UPLOAD_URL=$(echo "$RELEASE_INFO" | get_json_val upload_url | sed -E 's/([^{]+).*/\1/')
    
    # Check and delete existing asset if present
    ASSETS_JSON=$(github_api GET "/releases/$RELEASE_ID/assets")
    ASSET_ID=$(echo "$ASSETS_JSON" | python3 -c "import json, sys; d=sys.stdin.read().strip(); assets=json.loads(d) if d else []; print(next((a['id'] for a in assets if a['name'] == 'AdvancedDock.dmg'), ''))")
    if [ -n "$ASSET_ID" ]; then
        echo "Deleting old AdvancedDock.dmg asset (ID: $ASSET_ID)..."
        github_api DELETE "/releases/assets/$ASSET_ID" > /dev/null
    fi
else
    echo "Creating new release on GitHub..."
    PREV_TAG=$(git tag --merged HEAD | grep -E "^v" | grep -v "^v$VERSION$" | sort -V | tail -n 1 || true)
    CHANGELOG=$(git log "${PREV_TAG}..HEAD" --pretty=format:"* %s" 2>/dev/null || echo "* Initial release of version $VERSION.")
    [ -z "$CHANGELOG" ] && CHANGELOG="* Initial release of version $VERSION."
    
    RELEASE_POST_DATA=$(python3 -c "import json, sys; print(json.dumps({
      'tag_name': 'v' + sys.argv[1],
      'target_commitish': 'main',
      'name': 'v' + sys.argv[1],
      'body': sys.argv[2],
      'draft': False,
      'prerelease': False
    }))" "$VERSION" "$CHANGELOG")
    
    RESPONSE=$(github_api POST "/releases" -d "$RELEASE_POST_DATA")
    RELEASE_ID=$(echo "$RESPONSE" | get_json_val id)
    UPLOAD_URL=$(echo "$RESPONSE" | get_json_val upload_url | sed -E 's/([^{]+).*/\1/')
    
    if [ -z "$RELEASE_ID" ]; then
        echo "Error: Failed to create release. Response: $RESPONSE"
        exit 1
    fi
fi

# 8. Upload AdvancedDock.dmg to the Release
echo "=== Uploading AdvancedDock.dmg ==="
UPLOAD_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @"$DMG_FILE" \
     "$UPLOAD_URL?name=AdvancedDock.dmg")

UPLOAD_STATUS=$(echo "$UPLOAD_RESPONSE" | get_json_val state)
if [ "$UPLOAD_STATUS" != "uploaded" ]; then
    echo "Warning: Upload response did not confirm success: $UPLOAD_RESPONSE"
else
    echo "AdvancedDock.dmg uploaded successfully!"
fi

echo "=== Release v$VERSION published successfully! ==="
