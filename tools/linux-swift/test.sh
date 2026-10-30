#!/bin/bash
# Runs the supported Linux tests: TCRoofCore, ExcelExport, PVYield, ModuleRules and DriveAuth.
# The rest of TCRoofKit doesn't build on Linux (CoreText, UIKit, PDFKit), so this makes a small package
# next to the repo that links those targets (and CZlib) with their tests, plus `tools` and `Project_Plan_TCRoof`
# links where the tests look for them, four levels above their own files. Every target line
# (dependencies, resources) is copied from TCRoofKit/Package.swift.
#   tools/linux-swift/test.sh --parallel               # everything (about 2 minutes)
#   tools/linux-swift/test.sh --filter HourlyYieldTests
#   tools/linux-swift/test.sh --build-only             # compile only (the session hook warms the cache)
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
root="${TCROOF_LINUX_SWIFT_DIR:-$HOME/.cache/tcroof-linux-swift}"
kit="$root/Kit"
manifest="$repo/TCRoofKit/Package.swift"
targets=(CZlib PVYield ModuleRules TCRoofCore ExcelExport DriveSync)
tests=(PVYieldTests ModuleRulesTests TCRoofCoreTests ExcelExportTests DriveAuthTests)

mkdir -p "$kit/Sources" "$kit/Tests"
ln -sfn "$repo/tools" "$root/tools"
ln -sfn "$repo/Project_Plan_TCRoof" "$root/Project_Plan_TCRoof"
lines=""
for t in "${targets[@]}"; do
  ln -sfn "$repo/TCRoofKit/Sources/$t" "$kit/Sources/$t"
  lines+="$(grep -E "^[[:space:]]*\\.target\\(name: \"$t\"" "$manifest")"$'\n'
done
for t in "${tests[@]}"; do
  ln -sfn "$repo/TCRoofKit/Tests/$t" "$kit/Tests/$t"
  lines+="$(grep -E "^[[:space:]]*\\.testTarget\\(name: \"$t\"" "$manifest")"$'\n'
done
cat > "$kit/Package.swift" <<SWIFT
// swift-tools-version:6.2
// Written by tools/linux-swift/test.sh; the targets are copied from TCRoofKit/Package.swift.
import PackageDescription
let package = Package(
    name: "TCRoofLinux",
    defaultLocalization: "th",
    targets: [
$lines    ],
    swiftLanguageModes: [.v5]
)
SWIFT

# SwiftPM on Linux copies ExcelExport's PlanTemplates link into the bundle as the link itself
# (../../../Project_Plan_TCRoof/…, relative to .build/<triple>/debug/<bundle>), so give it something to land on.
mkdir -p "$kit/.build"
ln -sfn "$repo/Project_Plan_TCRoof" "$kit/.build/Project_Plan_TCRoof"

# The tests assume the team's clock (Bangkok): install-day reminders and calendar days read local time.
export TZ="${TZ:-Asia/Bangkok}"

cd "$kit"
if [ "${1:-}" = "--build-only" ]; then
  exec swift build --build-tests
fi
exec swift test "$@"
