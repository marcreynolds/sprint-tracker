#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: ./release-dmg.sh VERSION [--force]}"
FORCE="${2:-}"
APP_NAME="Sprint Tracker"
APP_BUNDLE="${APP_NAME}.app"
DIST_DIR="dist"
STAGING_DIR="$(mktemp -d)"
DMG_PATH="${DIST_DIR}/SprintTracker-${VERSION}.dmg"
TAG="v${VERSION}"

trap 'rm -rf "$STAGING_DIR"' EXIT

if [[ -n "$FORCE" && "$FORCE" != "--force" ]]; then
  echo "Unknown option: $FORCE" >&2
  exit 1
fi

command -v gh >/dev/null || {
  echo "The GitHub CLI (gh) is required." >&2
  exit 1
}
gh auth status >/dev/null

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash changes before creating a release." >&2
  exit 1
fi

git remote get-url origin >/dev/null
git fetch origin --tags
TAG_EXISTS=false
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  TAG_EXISTS=true
fi
if [[ "$TAG_EXISTS" == true && "$FORCE" != "--force" ]]; then
  echo "Tag ${TAG} already exists. Choose a new version or use --force." >&2
  exit 1
fi

./build-app.sh
mkdir -p "$DIST_DIR"

# ditto preserves the .app bundle itself. cp -R can copy only its Contents.
ditto "$APP_BUNDLE" "${STAGING_DIR}/${APP_BUNDLE}"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" \
  -ov -format UDZO "$DMG_PATH"

git push origin HEAD

if [[ "$FORCE" == "--force" ]]; then
  git tag -fa "$TAG" -m "${APP_NAME} ${TAG}"
  git push origin "refs/tags/${TAG}" --force
else
  git tag -a "$TAG" -m "${APP_NAME} ${TAG}"
  git push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release edit "$TAG" --title "${APP_NAME} ${TAG}"
  gh release upload "$TAG" "$DMG_PATH" --clobber
else
  gh release create "$TAG" "$DMG_PATH" \
    --verify-tag \
    --title "${APP_NAME} ${TAG}" \
    --generate-notes
fi

echo "Published: ${TAG}"
