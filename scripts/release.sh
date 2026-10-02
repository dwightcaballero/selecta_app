#!/usr/bin/env bash
# ==============================================================================
# Selecta Ops - Automated Release & Version Bump Script
# ==============================================================================
# Usage:
#   ./scripts/release.sh              # Automatically increments build number (+1)
#   ./scripts/release.sh 1.0.1+25     # Sets specific version and build number
# ==============================================================================

set -e

PUBSPEC="pubspec.yaml"
README="README.md"

if [ ! -f "$PUBSPEC" ]; then
  echo "Error: Run this script from the project root containing $PUBSPEC."
  exit 1
fi

CURRENT_VERSION_LINE=$(grep '^version:' "$PUBSPEC")
CURRENT_FULL_VERSION=$(echo "$CURRENT_VERSION_LINE" | sed 's/version: //; s/ //g')

BASE_VERSION=$(echo "$CURRENT_FULL_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_FULL_VERSION" | cut -s -d'+' -f2)

if [ -z "$BUILD_NUMBER" ]; then
  BUILD_NUMBER=1
fi

if [ -n "$1" ]; then
  NEW_VERSION="$1"
else
  NEW_BUILD=$((BUILD_NUMBER + 1))
  NEW_VERSION="${BASE_VERSION}+${NEW_BUILD}"
fi

echo "=========================================="
echo "Selecta Ops Release Workflow"
echo "Current Version: $CURRENT_FULL_VERSION"
echo "New Version:     $NEW_VERSION"
echo "Tag:             v$NEW_VERSION"
echo "=========================================="

# 1. Update pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

# 2. Update README.md if present
if [ -f "$README" ]; then
  sed -i "s/^Current: .*/Current: $NEW_VERSION/" "$README"
fi

echo "[✓] Updated $PUBSPEC and $README"

# 3. Commit changes
git add "$PUBSPEC" "$README"
git commit -m "chore(release): bump version to $NEW_VERSION"

# 4. Create git tag
git tag "v$NEW_VERSION"
echo "[✓] Created git tag v$NEW_VERSION"

# 5. Push to GitHub
echo "Pushing commits and tags to GitHub..."
git push origin main
git push origin "v$NEW_VERSION"

echo "=========================================="
echo "🚀 Release triggered successfully!"
echo "GitHub Actions is now compiling the release APK"
echo "and publishing it to GitHub Releases."
echo ""
echo "Once published, all installed Selecta Ops apps"
echo "will automatically detect the new update (v$NEW_VERSION)"
echo "and prompt salesmen and dealers to update!"
echo "=========================================="
