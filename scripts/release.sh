#!/bin/bash
# Publishes the version in VERSION as a GitHub release: builds a universal app (Apple silicon and
# Intel), zips it as Copykeep.zip and uploads it under the tag v<VERSION>. The download
# page (docs/index.html) links to the latest release's Copykeep.zip, so it follows along.
# Usage: scripts/release.sh   (bump VERSION first; needs gh signed in)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
TAG="v$VERSION"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "$TAG is already released. Bump VERSION first." >&2
  exit 1
fi

./build.sh --universal
ZIP=build/Copykeep.zip
rm -f "$ZIP"
ditto -c -k --keepParent build/Copykeep.app "$ZIP"

gh release create "$TAG" "$ZIP" --title "Copykeep $VERSION" --target main --notes "Download **Copykeep.zip**, unzip it and move Copykeep to Applications. Needs macOS 14 or later, on Apple silicon or Intel.

The app isn't notarized by Apple, so the first time you open it macOS says it can't check it. Open **System Settings › Privacy & Security** and click **Open Anyway** next to Copykeep. Or install from Terminal, which skips the check:

\`\`\`sh
curl -sL https://github.com/stanimir93/copykeep/releases/latest/download/Copykeep.zip -o /tmp/cs.zip && ditto -xk /tmp/cs.zip /Applications && open /Applications/Copykeep.app
\`\`\`"
