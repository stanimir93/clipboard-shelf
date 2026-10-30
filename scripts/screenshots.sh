#!/bin/bash
# Draws docs/panel-light.png and docs/panel-dark.png for the download page, from a made-up
# history in a throwaway home folder, so nothing you copied ends up in them.
# Usage: scripts/screenshots.sh   (after ./build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=build/Copykeep.app/Contents/MacOS/Copykeep
DEMO=$(mktemp -d)
trap 'rm -rf "$DEMO"' EXIT
mkdir -p "$DEMO/Library/Application Support/Copykeep/blobs"

python3 - "$DEMO/Library/Application Support/Copykeep/history.json" <<'PY'
import datetime, json, sys, uuid
now = datetime.datetime.now(datetime.timezone.utc)
clips = [  # kind, text, app, bundle ID, minutes ago, pinned
    ("text", "Meeting notes: launch on Monday, docs page first, then the release.", "Notes", "com.apple.Notes", 240, True),
    ("text", "Thanks for the quick turnaround — I'll send the signed copy by Friday.", "Mail", "com.apple.mail", 1, False),
    ("link", "https://github.com/stanimir93/copykeep", "Safari", "com.apple.Safari", 4, False),
    ("text", "OPENAI_API_KEY=sk-proj-4f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c", "Visual Studio Code", "com.microsoft.VSCode", 9, False),
    ("text", "git log --oneline --since=yesterday", "Terminal", "com.apple.Terminal", 15, False),
    ("text", "42 Baker Street, London NW1 6XE", "Maps", "com.apple.Maps", 32, False),
    ("text", "Lunch at 1? The new place on the corner.", "Messages", "com.apple.MobileSMS", 70, False),
]
json.dump([{
    "id": str(uuid.uuid4()).upper(), "kind": kind, "text": text, "sourceApp": app, "sourceBundleID": bundle,
    "copiedAt": (now - datetime.timedelta(minutes=ago)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "pinned": pinned, "copyCount": 1, "fingerprint": str(uuid.uuid4()),
} for kind, text, app, bundle, ago, pinned in clips], open(sys.argv[1], "w"))
PY

mkdir -p docs
# CFFIXED_USER_HOME points Application Support at the throwaway folder.
CFFIXED_USER_HOME=$DEMO "$BIN" --snapshot docs/panel-light.png
CFFIXED_USER_HOME=$DEMO "$BIN" --snapshot docs/panel-dark.png dark
