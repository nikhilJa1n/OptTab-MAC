#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing arguments."
    echo "Usage: ./publish_alpha.sh <marketing_version> <build_number> [release_notes]"
    echo "Example: ./publish_alpha.sh 3.5-alpha.1 62"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
RELEASE_NOTES="${3:-}"
TAG="v$VERSION"

echo "=========================================================================="
echo "🧪 OPTTAB ALPHA RELEASE PIPELINE: $TAG (Build $BUILD_NUMBER)"
echo "=========================================================================="

# 1. Generate initial draft of RELEASE_NOTES.md & alpha version history
echo "=== Step 1: Generating draft alpha release notes from commit log ==="
python3 scripts/update_version_history.py "$VERSION" "$RELEASE_NOTES" --alpha

# 2. Interactive Review Step: Open RELEASE_NOTES.md for user review
echo ""
echo "=========================================================================="
echo "📝 REVIEW STEP: Opening RELEASE_NOTES.md for your review..."
echo "Please review and edit RELEASE_NOTES.md to your exact liking."
echo "Save your edits in your editor, then return here."
echo "=========================================================================="
echo ""

open RELEASE_NOTES.md 2>/dev/null || true

read -p "Press [ENTER] after reviewing & saving RELEASE_NOTES.md to continue... "

# Re-sync reviewed RELEASE_NOTES.md into VersionHistory.swift & update-alpha.json
echo "=== Syncing reviewed release notes into VersionHistory.swift & update-alpha.json ==="
python3 scripts/update_version_history.py "$VERSION" "$(cat RELEASE_NOTES.md)" --alpha

# 3. Re-build and package the release assets locally
echo "=== Packaging assets locally for $VERSION (Build: $BUILD_NUMBER) ==="
bash release.sh "$VERSION" "$BUILD_NUMBER"

# 4. Commit version updates, update-alpha.json & RELEASE_NOTES.md
echo "=== Committing alpha release config & version history changes ==="
git add Sources/VersionHistory.swift update-alpha.json RELEASE_NOTES.md
git commit -m "Automated alpha release bump to $TAG" || true

# 5. Tag commit
echo "=== Tagging commit as $TAG ==="
git tag -d "$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "Alpha Release $TAG"

# 6. Push commits and tag to GitHub
echo "=== Pushing commits and tag to GitHub ==="
git push origin main

# Safely update tag on GitHub without aborting if it already exists
git push origin -f "refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null || \
(git push origin --delete "$TAG" 2>/dev/null && git push origin "$TAG" 2>/dev/null) || \
echo "Notice: Tag $TAG already exists on remote, proceeding to release asset upload..."

# 7. Publish release on GitHub Releases via GitHub CLI as a PRE-RELEASE
if command -v gh &> /dev/null; then
    echo "=== Publishing Pre-Release on GitHub ==="
    gh release create "$TAG" OptTab.dmg OptTab.zip --title "$TAG (Alpha Preview)" --notes-file RELEASE_NOTES.md --prerelease 2>/dev/null || \
    gh release edit "$TAG" --title "$TAG (Alpha Preview)" --notes-file RELEASE_NOTES.md --prerelease || true
    gh release upload "$TAG" OptTab.dmg OptTab.zip --clobber 2>/dev/null || true
fi

echo ""
echo "=========================================================================="
echo "🎉 Alpha Pre-Release $TAG (Build $BUILD_NUMBER) published successfully to GitHub!"
echo "Users on the Alpha channel will receive this update."
echo "=========================================================================="
