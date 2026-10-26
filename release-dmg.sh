#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: ./release-dmg.sh VERSION}"
APP_NAME="Sprint Tracker"
APP_BUNDLE="${APP_NAME}.app"
DIST_DIR="dist"
STAGING_DIR="$(mktemp -d)"
DMG_PATH="${DIST_DIR}/SprintTracker-${VERSION}.dmg"
TAG="v${VERSION}"

trap 'rm -rf "$STAGING_DIR"' EXIT

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
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "Tag ${TAG} already exists. Choose a new version." >&2
  exit 1
fi

./build-app.sh
mkdir -p "$DIST_DIR"

# ditto preserves the .app bundle itself. cp -R can copy only its Contents.
ditto "$APP_BUNDLE" "${STAGING_DIR}/${APP_BUNDLE}"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" \
  -ov -format UDZO "$DMG_PATH"

git tag -a "$TAG" -m "${APP_NAME} ${TAG}"
git push origin HEAD
git push origin "$TAG"

gh release create "$TAG" "$DMG_PATH" \
  --verify-tag \
  --title "${APP_NAME} ${TAG}" \
  --generate-notes

echo "Published: ${TAG}"
