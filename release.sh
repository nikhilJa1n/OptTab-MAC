#!/bin/bash
set -e

# Make sure we are in the repository root
cd "$(dirname "$0")"

# 1. Read current version from build.sh
VERSION=$(grep -E "<key>CFBundleShortVersionString</key>" -A 1 build.sh | tail -n 1 | sed -e 's/^[[:space:]]*//' -e 's/<string>//' -e 's/<\/string>//')
echo "Detected App Version: $VERSION"

# 2. Get repository info from git remote
REMOTE_URL=$(git config --get remote.origin.url || true)
if [ -z "$REMOTE_URL" ]; then
    echo "Error: Git remote 'origin' is not set. Run 'git remote add origin <URL>' first."
    exit 1
fi

# Extract owner and repo name from URL (supports both HTTPS and SSH formats)
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
    echo "Please enter your GitHub Personal Access Token (PAT) with 'repo' scope:"
    read -r -s GITHUB_TOKEN
    echo ""
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN is required to publish releases."
    exit 1
fi

# 4. Build and Package (Compiles, signs, and generates AdvancedDock.dmg)
echo "=== Compiling and Packaging App ==="
./build.sh

DMG_FILE="AdvancedDock.dmg"
if [ ! -f "$DMG_FILE" ]; then
    echo "Error: DMG file not found. Build failed."
    exit 1
fi

# 5. Check if release already exists on GitHub
echo "=== Checking if release $VERSION exists on GitHub ==="
RELEASE_CHECK_URL="https://api.github.com/repos/$OWNER/$REPO/releases/tags/v$VERSION"
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$RELEASE_CHECK_URL")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "Error: Release v$VERSION already exists on GitHub. Increment your version inside build.sh before running this release script."
    exit 1
fi

# 6. Generate Changelog from Git Commit History
echo "=== Generating Changelog from Git Commit History ==="
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$PREV_TAG" ]; then
    echo "Found previous release tag: $PREV_TAG. Extracting commits from last deployed tag to newest commit..."
    # Check if the previous tag has a parent to safely use inclusive range
    if git rev-parse "${PREV_TAG}^" >/dev/null 2>&1; then
        CHANGELOG=$(git log "${PREV_TAG}^..HEAD" --pretty=format:"* %s" || true)
    else
        CHANGELOG=$(git log "${PREV_TAG}..HEAD" --pretty=format:"* %s" || true)
    fi
else
    echo "No previous release tag found. Extracting full commit history..."
    CHANGELOG=$(git log --pretty=format:"* %s" || true)
fi

# Fallback if changelog is empty
if [ -z "$CHANGELOG" ]; then
    CHANGELOG="* Initial release package of version $VERSION."
fi

echo -e "Changelog Content:\n$CHANGELOG\n"

# Create Release Post Payload with safely escaped JSON body using python
echo "=== Preparing GitHub Release Payload ==="
RELEASE_POST_DATA=$(python3 -c "import json, sys; print(json.dumps({
  'tag_name': 'v' + sys.argv[1],
  'target_commitish': 'main',
  'name': 'v' + sys.argv[1],
  'body': sys.argv[2],
  'draft': False,
  'prerelease': False
}))" "$VERSION" "$CHANGELOG")

RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$RELEASE_POST_DATA" \
     "https://api.github.com/repos/$OWNER/$REPO/releases")

# Parse Release ID and Upload URL from response
RELEASE_ID=$(echo "$RESPONSE" | grep -m 1 "\"id\":" | awk '{print $2}' | tr -d ',')
UPLOAD_URL=$(echo "$RESPONSE" | grep -m 1 "\"upload_url\":" | sed -E 's/.*"upload_url": "([^{]+).*/\1/')

if [ -z "$RELEASE_ID" ] || [ -z "$UPLOAD_URL" ]; then
    echo "Error: Failed to create release. API response:"
    echo "$RESPONSE"
    exit 1
fi

echo "Release created successfully (ID: $RELEASE_ID)."

# 7. Upload AdvancedDock.dmg to the Release
echo "=== Uploading AdvancedDock.dmg ==="
UPLOAD_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @"$DMG_FILE" \
     "$UPLOAD_URL?name=AdvancedDock.dmg")

UPLOAD_STATUS=$(echo "$UPLOAD_RESPONSE" | grep -m 1 "\"state\":" | awk '{print $2}' | tr -d '",')

if [ "$UPLOAD_STATUS" != "uploaded" ]; then
    echo "Warning: Upload response did not confirm success. API response:"
    echo "$UPLOAD_RESPONSE"
else
    echo "AdvancedDock.dmg uploaded successfully!"
fi

# 8. Update update.json with new version details
echo "=== Updating update.json ==="
cat > update.json <<EOF
{
  "version": "$VERSION",
  "downloadUrl": "https://github.com/$OWNER/$REPO/releases/download/v$VERSION/AdvancedDock.dmg",
  "changelog": "Released version $VERSION."
}
EOF

# 9. Commit, tag, and push changes to GitHub
echo "=== Committing and tagging release ==="
git add update.json
git commit -m "Bump update.json to v$VERSION" || true

# Delete local tag if it exists, then create a new annotated tag
git tag -d "v$VERSION" 2>/dev/null || true
git tag -a "v$VERSION" -m "Release v$VERSION"

# Push both the main branch and the tags to origin
echo "=== Pushing commits and tags to GitHub ==="
git push origin main --tags || true

echo "=== Release v$VERSION published successfully! ==="
