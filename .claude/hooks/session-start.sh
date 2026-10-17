#!/bin/bash
# Cloud sessions only: installs what the checks that can run on Linux need.
# - tools/firestore-rules-tests: npm packages, the Firebase CLI (its emulator) and Java
# - LibreOffice Calc (headless), to open and re-save exported .xlsx files
# Swift can't be installed here (download.swift.org is blocked), so `swift test` and xcodebuild stay on the Mac.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

# Firestore rules tests
(cd tools/firestore-rules-tests && npm install --no-audit --no-fund --loglevel=error)
command -v firebase >/dev/null 2>&1 || npm install -g firebase-tools --no-audit --no-fund --loglevel=error
command -v java >/dev/null 2>&1 || {
  apt-get update -qq && apt-get install -y -qq --no-install-recommends default-jre-headless >/dev/null
}

# LibreOffice for workbook checks; optional, so a failed install doesn't stop the session
if ! command -v soffice >/dev/null 2>&1; then
  { apt-get update -qq && apt-get install -y -qq --no-install-recommends libreoffice-calc-nogui >/dev/null; } \
    || echo "session-start: LibreOffice not installed; workbook checks unavailable" >&2
fi
