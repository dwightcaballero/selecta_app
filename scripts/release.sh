#!/usr/bin/env bash
# ==============================================================================
# Selecta Ops - Automated Release & Version Bump Script
# ==============================================================================
# Usage:
#   ./scripts/release.sh              # Automatically increments build number (+1)
#   ./scripts/release.sh --force      # Mandatory / force update (+1 build)
#   ./scripts/release.sh 1.0.1+25     # Sets specific version and build number
#   ./scripts/release.sh 1.0.1+25 --force # Sets version and marks as mandatory
# ==============================================================================

set -e

PUBSPEC="pubspec.yaml"
README="README.md"

if [ ! -f "$PUBSPEC" ]; then
  echo "Error: Run this script from the project root containing $PUBSPEC."
  exit 1
fi

IS_FORCE=false
SPECIFIC_VERSION=""

for arg in "$@"; do
  if [ "$arg" == "--force" ] || [ "$arg" == "-f" ]; then
    IS_FORCE=true
  elif [ -z "$SPECIFIC_VERSION" ]; then
    SPECIFIC_VERSION="$arg"
  fi
done

CURRENT_VERSION_LINE=$(grep '^version:' "$PUBSPEC")
CURRENT_FULL_VERSION=$(echo "$CURRENT_VERSION_LINE" | sed 's/version: //; s/ //g')

BASE_VERSION=$(echo "$CURRENT_FULL_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_FULL_VERSION" | cut -s -d'+' -f2)

if [ -z "$BUILD_NUMBER" ]; then
  BUILD_NUMBER=1
fi

if [ -n "$SPECIFIC_VERSION" ]; then
  NEW_VERSION="$SPECIFIC_VERSION"
else
  NEW_BUILD=$((BUILD_NUMBER + 1))
  NEW_VERSION="${BASE_VERSION}+${NEW_BUILD}"
fi

echo "=========================================="
echo "Selecta Ops Release Workflow"
echo "Current Version: $CURRENT_FULL_VERSION"
echo "New Version:     $NEW_VERSION"
echo "Tag:             v$NEW_VERSION"
if [ "$IS_FORCE" = true ]; then
  echo "Update Type:     MANDATORY / FORCE UPDATE ⚠️"
else
  echo "Update Type:     Standard (Optional)"
fi
echo "=========================================="

# 1. Update pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

# 2. Update README.md if present
if [ -f "$README" ]; then
  sed -i "s/^Current: .*/Current: $NEW_VERSION/" "$README"
fi

echo "[✓] Updated $PUBSPEC and $README"

# 3. Commit changes
COMMIT_MSG="chore(release): bump version to $NEW_VERSION"
if [ "$IS_FORCE" = true ]; then
  COMMIT_MSG="$COMMIT_MSG [force-update]"
fi

git add "$PUBSPEC" "$README"
git commit -m "$COMMIT_MSG"

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
