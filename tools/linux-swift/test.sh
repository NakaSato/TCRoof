#!/bin/bash
# Runs the Swift tests that work on Linux: TCRoofCore, PVYield and ModuleRules.
# The rest of TCRoofKit doesn't build on Linux (CoreText, UIKit, PDFKit), so this makes a small package
# next to the repo that links those three targets and their tests, plus a `tools` link so HourlyYieldTests
# finds tools/yield-reference four levels above its own file. TCRoofCore's target line (its resources)
# is copied from TCRoofKit/Package.swift.
#   tools/linux-swift/test.sh --parallel               # everything (TCRoofCore takes a few minutes)
#   tools/linux-swift/test.sh --filter HourlyYieldTests
#   tools/linux-swift/test.sh --build-only             # compile only (the session hook warms the cache)
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
root="${TCROOF_LINUX_SWIFT_DIR:-$HOME/.cache/tcroof-linux-swift}"
kit="$root/Kit"

mkdir -p "$kit/Sources" "$kit/Tests"
ln -sfn "$repo/tools" "$root/tools"
for t in PVYield ModuleRules TCRoofCore; do
  ln -sfn "$repo/TCRoofKit/Sources/$t" "$kit/Sources/$t"
  ln -sfn "$repo/TCRoofKit/Tests/${t}Tests" "$kit/Tests/${t}Tests"
done
core="$(grep -E '^[[:space:]]*\.target\(name: "TCRoofCore"' "$repo/TCRoofKit/Package.swift")"
cat > "$kit/Package.swift" <<SWIFT
// swift-tools-version:5.9
// Written by tools/linux-swift/test.sh; the targets mirror TCRoofKit/Package.swift.
import PackageDescription
let package = Package(
    name: "TCRoofLinux",
    defaultLocalization: "th",
    targets: [
$core
        .testTarget(name: "TCRoofCoreTests", dependencies: ["TCRoofCore", "ModuleRules"], resources: [.copy("Fixtures")]),
        .target(name: "PVYield", resources: [.copy("Resources/weather")]),
        .testTarget(name: "PVYieldTests", dependencies: ["PVYield"], resources: [.copy("Fixtures")]),
        .target(name: "ModuleRules", resources: [.process("Resources")]),
        .testTarget(name: "ModuleRulesTests", dependencies: ["ModuleRules"]),
    ]
)
SWIFT

# The tests assume the team's clock (Bangkok): install-day reminders and calendar days read local time.
export TZ="${TZ:-Asia/Bangkok}"

cd "$kit"
if [ "${1:-}" = "--build-only" ]; then
  exec swift build --build-tests
fi
exec swift test "$@"
