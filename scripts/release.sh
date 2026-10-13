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
RELEASE_NOTES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --force|-f)
      IS_FORCE=true
      shift
      ;;
    -m|--notes|--message)
      RELEASE_NOTES="$2"
      shift 2
      ;;
    *)
      if [ -z "$SPECIFIC_VERSION" ]; then
        SPECIFIC_VERSION="$1"
      fi
      shift
      ;;
  esac
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

# Auto-generate release notes from git commits since the last release tag if not provided
if [ -z "$RELEASE_NOTES" ]; then
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [ -n "$LAST_TAG" ]; then
    AUTO_NOTES=$(git log "${LAST_TAG}..HEAD" --no-merges --invert-grep --grep="^chore(release)" --pretty=format:"• %s" 2>/dev/null || echo "")
  else
    AUTO_NOTES=$(git log -n 5 --no-merges --invert-grep --grep="^chore(release)" --pretty=format:"• %s" 2>/dev/null || echo "")
  fi

  if [ -z "$AUTO_NOTES" ]; then
    AUTO_NOTES="• Performance improvements and bug fixes"
  fi

  if [ -t 0 ]; then
    echo "=========================================="
    echo "📋 Auto-detected release notes from commits:"
    echo "------------------------------------------"
    echo "$AUTO_NOTES"
    echo "------------------------------------------"
    read -r -p "Use these release notes? [Press ENTER for yes, or type custom notes]: " USER_INPUT
    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "y" ] || [ "$USER_INPUT" = "Y" ]; then
      RELEASE_NOTES="$AUTO_NOTES"
    else
      RELEASE_NOTES="$USER_INPUT"
    fi
  else
    RELEASE_NOTES="$AUTO_NOTES"
  fi
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
echo "Release Notes:"
echo "$RELEASE_NOTES"
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
git commit -m "$COMMIT_MSG" -m "$RELEASE_NOTES"

# 4. Create annotated git tag containing the release notes
TAG_MSG="$RELEASE_NOTES"
if [ "$IS_FORCE" = true ]; then
  TAG_MSG="[force-update]
$TAG_MSG"
fi

git tag -a "v$NEW_VERSION" -m "$TAG_MSG"
echo "[✓] Created annotated git tag v$NEW_VERSION with release notes"

# 5. Push to GitHub
echo "Pushing commits and tags to GitHub..."
git push origin main
git push origin "v$NEW_VERSION"

echo "=========================================="
echo "🚀 Release triggered successfully!"
echo "GitHub Actions is now compiling the release APK,"
echo "publishing to GitHub Releases, and uploading to"
echo "Firebase Storage for ultra-fast downloads!"
echo ""
echo "Once finished, installed Selecta Ops apps will"
echo "automatically download the update in the background"
echo "and prompt users: [INSTALL NOW] with 0 wait time!"
echo "=========================================="
