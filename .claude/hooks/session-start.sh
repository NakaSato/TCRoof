#!/bin/bash
# Cloud sessions only: installs what the checks that can run on Linux need.
# - tools/firestore-rules-tests: npm packages, the Firebase CLI (its emulator) and Java
# - functions: npm packages for the assistant Cloud Function's `npm test`
# - LibreOffice Calc (headless), to open and re-save exported .xlsx files
# - Swift for Linux, for the PVYield and ModuleRules tests (tools/linux-swift/test.sh);
#   the rest of TCRoofKit and xcodebuild stay on the Mac.
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

# Cloud Function tests
(cd functions && npm install --no-audit --no-fund --loglevel=error)

# LibreOffice for workbook checks; optional, so a failed install doesn't stop the session
if ! command -v soffice >/dev/null 2>&1; then
  { apt-get update -qq && apt-get install -y -qq --no-install-recommends libreoffice-calc-nogui >/dev/null; } \
    || echo "session-start: LibreOffice not installed; workbook checks unavailable" >&2
fi

# Swift for the Linux test package; optional, so a failed download doesn't stop the session
SWIFT_VERSION=6.1.2
SWIFT_DIR="/opt/swift-$SWIFT_VERSION"
if [ ! -x "$SWIFT_DIR/usr/bin/swift" ]; then
  name="swift-$SWIFT_VERSION-RELEASE-ubuntu24.04"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/swift.tar.gz" \
      "https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404/swift-$SWIFT_VERSION-RELEASE/$name.tar.gz" \
    && mkdir -p "$SWIFT_DIR.partial" \
    && tar xzf "$tmp/swift.tar.gz" -C "$SWIFT_DIR.partial" --strip-components=1; then
    rm -rf "$SWIFT_DIR" && mv "$SWIFT_DIR.partial" "$SWIFT_DIR"
  else
    rm -rf "$SWIFT_DIR.partial"
    echo "session-start: Swift not installed; tools/linux-swift/test.sh unavailable" >&2
  fi
  rm -rf "$tmp"
fi
if [ -x "$SWIFT_DIR/usr/bin/swift" ]; then
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$SWIFT_DIR/usr/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
  # Compile once so the first test run in the session is quick
  PATH="$SWIFT_DIR/usr/bin:$PATH" tools/linux-swift/test.sh --build-only >/dev/null \
    || echo "session-start: the Linux Swift package didn't build" >&2
fi
