#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing arguments."
    echo "Usage: ./publish_release.sh <marketing_version> <build_number> [release_notes]"
    echo "Example: ./publish_release.sh 3.1 46"
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
RELEASE_NOTES="${3:-}"
TAG="v$VERSION"

# 1. Generate initial draft of RELEASE_NOTES.md & version history
echo "=== Step 1: Generating draft release notes from commit log ==="
python3 scripts/update_version_history.py "$VERSION" "$RELEASE_NOTES"

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

# Re-sync reviewed RELEASE_NOTES.md into VersionHistory.swift & update.json
echo "=== Syncing reviewed release notes across VersionHistory.swift & update.json ==="
python3 scripts/update_version_history.py "$VERSION" "$(cat RELEASE_NOTES.md)"

# 3. Re-build and package the release assets locally
echo "=== Packaging assets locally for $VERSION (Build: $BUILD_NUMBER) ==="
bash release.sh "$VERSION" "$BUILD_NUMBER"

# 4. Commit version updates, update.json & RELEASE_NOTES.md
echo "=== Committing release config & version history changes ==="
git add Sources/VersionHistory.swift update.json RELEASE_NOTES.md
git commit -m "Automated release bump to $TAG" || true

# 5. Tag commit
echo "=== Tagging commit as $TAG ==="
git tag -d "$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "Release $TAG"

# 6. Push commits and tag to GitHub
echo "=== Pushing commits and tag to GitHub ==="
git push origin main
git push origin -f "$TAG"

# 7. Publish release on GitHub Releases via GitHub CLI
if command -v gh &> /dev/null; then
    echo "=== Publishing release on GitHub ==="
    gh release create "$TAG" OptTab.dmg OptTab.zip --title "$TAG" --notes-file RELEASE_NOTES.md 2>/dev/null || gh release edit "$TAG" --notes-file RELEASE_NOTES.md || true
    gh release upload "$TAG" OptTab.dmg OptTab.zip --clobber 2>/dev/null || true
fi

echo ""
echo "=========================================================================="
echo "🎉 Release $TAG (Build $BUILD_NUMBER) published successfully to GitHub!"
echo "=========================================================================="
