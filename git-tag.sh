#!/usr/bin/env bash

# Usage: ./git-tag.sh [patch|minor|major]

INCREMENT=${1:-patch}

LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -z "$LATEST_TAG" ]; then
  LATEST_TAG="v0.0.0"
fi

# Remove leading 'v' and split into parts
VERSION=${LATEST_TAG#v}
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

# Increment version
case $INCREMENT in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Invalid increment type. Use patch, minor, or major."
    exit 1
    ;;
esac

NEW_TAG="v$MAJOR.$MINOR.$PATCH"
MESSAGE="Release $NEW_TAG"

git tag -a "$NEW_TAG" -m "$MESSAGE"
git push deploy "$NEW_TAG"

echo "Tag $NEW_TAG created and pushed to deploy."
