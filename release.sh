#!/bin/bash
# Publish a new MyType build: commit, push, package the DMG, upload it to the GitHub release, verify it.
#
#   ./release.sh "what changed"          re-publish the current version (replaces the DMG on its release)
#   ./release.sh "what changed" 1.1      publish a new version (creates release v1.1)
#
# The current version is remembered in .version.
set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-}"; NEW="${2:-}"
[ -n "$MSG" ] || { echo "usage: ./release.sh \"what changed\" [new-version]"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in to GitHub. Run: gh auth login"; exit 1; }

VERSION="${NEW:-$(cat .version 2>/dev/null || echo 1.0)}"
TAG="v$VERSION"

echo "==> Commit and push"
git add -A
if git diff --cached --quiet; then echo "nothing new to commit"; else
  git commit -q -m "$MSG

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
fi
git push -q origin HEAD

echo "==> Build MyType.dmg ($VERSION)"
VERSION="$VERSION" ./package.sh
echo "$VERSION" > .version

echo "==> Publish release $TAG"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" build/MyType.dmg --clobber
else
  gh release create "$TAG" build/MyType.dmg --title "MyType $VERSION" --notes "$MSG"
fi

echo "==> Verify the download matches"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
gh release download "$TAG" -p MyType.dmg -D "$TMP"
if [ "$(shasum -a 256 < build/MyType.dmg)" = "$(shasum -a 256 < "$TMP/MyType.dmg")" ]; then
  echo "Done. $TAG is live and the download is identical to your build."
  gh release view "$TAG" --json url --jq .url
else
  echo "WARNING: the downloaded DMG does not match your local build."; exit 1
fi
