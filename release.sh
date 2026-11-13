#!/bin/zsh
# Usage: ./release.sh 1.2.0 "What changed"
# Bumps VERSION, builds, commits, tags and publishes a GitHub release.
# Installed copies pick it up within 6 hours (or on next launch).
set -euo pipefail
cd "$(dirname "$0")"

NEW=${1:?usage: ./release.sh <version> "<notes>"}
NOTES=${2:-"CornerSwitch $NEW"}

echo "$NEW" > VERSION
./build.sh
git add -A
git commit -m "Release $NEW"
git tag "v$NEW"
git push origin HEAD --tags
gh release create "v$NEW" build/CornerSwitch.zip build/CornerSwitch.dmg --title "CornerSwitch $NEW" --notes "$NOTES"
