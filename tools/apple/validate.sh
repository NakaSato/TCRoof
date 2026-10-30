#!/bin/bash
# Apple SDK validation; intentionally refuses to substitute Linux checks for an Xcode build.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: tools/apple/validate.sh [--output DIR] [--simulator UDID] [--ui-tests] [--package-tests]

Builds Debug and Release against the iOS Simulator SDK using Xcode 26+.
--simulator UDID   Select an installed simulator; defaults to generic/platform=iOS Simulator.
--ui-tests         Run the existing UI suite on the selected simulator (requires --simulator).
--package-tests    Run the focused package tests on the Mac after app builds.
--output DIR      Write logs, result bundles, and isolated DerivedData here; DIR must be new.

This does not sign, upload, or publish a build. Real Google/Keychain flows and physical-device
profiling remain separate checks documented in docs/specs/release-readiness.md.
HELP
}

output=""
simulator=""
ui_tests=false
package_tests=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --output|--simulator)
            [ "$#" -ge 2 ] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
            if [ "$1" = --output ]; then output="$2"; else simulator="$2"; fi
            shift 2 ;;
        --ui-tests) ui_tests=true; shift ;;
        --package-tests) package_tests=true; shift ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    printf 'Requires macOS with Xcode 26+. No Apple checks were executed.\n' >&2
    exit 2
fi
for command in xcodebuild xcrun swift git; do
    command -v "$command" >/dev/null || { printf 'Missing command: %s\n' "$command" >&2; exit 2; }
done
if $ui_tests && [ -z "$simulator" ]; then
    printf '%s\n' '--ui-tests requires --simulator UDID.' >&2
    exit 2
fi
xcode_version="$(xcodebuild -version)"
xcode_major="$(printf '%s\n' "$xcode_version" | awk '/^Xcode / { split($2, version, "."); print version[1] }')"
case "$xcode_major" in
    ''|*[!0-9]*) printf 'Unable to determine the selected Xcode version.\n' >&2; exit 2 ;;
esac
[ "$xcode_major" -ge 26 ] || { printf 'Select Xcode 26 or later using DEVELOPER_DIR or xcode-select.\n' >&2; exit 2; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "$output" ]; then
    output="$(mktemp -d "${TMPDIR:-/tmp}/tcroof-apple-validation.XXXXXX")"
else
    if [ -e "$output" ]; then printf 'Output directory already exists: %s\n' "$output" >&2; exit 2; fi
    mkdir -p "$output"
fi
output="$(cd "$output" && pwd)"
printf '%s\n' "$xcode_version" > "$output/xcode-version.txt"
xcrun swift --version > "$output/swift-version.txt"
git -C "$repo" rev-parse HEAD > "$output/commit.txt"
git -C "$repo" status --porcelain > "$output/working-tree.txt"
printf 'Apple validation output: %s\n' "$output"

run_step() {
    local name="$1"
    shift
    if "$@" > "$output/$name.log" 2>&1; then
        printf 'PASS\t%s\n' "$name" | tee -a "$output/results.tsv"
    else
        printf 'FAIL\t%s\n' "$name" | tee -a "$output/results.tsv" >&2
        printf 'Inspect %s/%s.log for the error.\n' "$output" "$name" >&2
        exit 1
    fi
}

cd "$repo"
run_step destinations xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -showdestinations
xcrun simctl list devices available --json > "$output/simulators.json"
destination='generic/platform=iOS Simulator'
if [ -n "$simulator" ]; then destination="platform=iOS Simulator,id=$simulator"; fi
for configuration in Debug Release; do
    run_step "build-$configuration" xcodebuild -quiet -project TCRoof.xcodeproj -scheme TCRoof \
        -configuration "$configuration" -destination "$destination" \
        -derivedDataPath "$output/DerivedData" -resultBundlePath "$output/$configuration.xcresult" \
        CODE_SIGNING_ALLOWED=NO build
done
if $package_tests; then
    run_step package-tests xcrun swift test --package-path TCRoofKit \
        --scratch-path "$output/PackageBuild" -c release \
        --filter 'OAuthBrowserAuthorizationTests|OAuthTokenSessionTests|BackgroundWorkTests|ReviewTests|ZipArchiveTests|SingleLineTests'
else
    printf 'NOT_RUN\tpackage-tests\n' >> "$output/results.tsv"
fi
if $ui_tests; then
    run_step ui-tests xcodebuild -quiet -project TCRoof.xcodeproj -scheme TCRoofUITests \
        -configuration Debug -destination "$destination" -derivedDataPath "$output/DerivedData" \
        -resultBundlePath "$output/UITests.xcresult" CODE_SIGNING_ALLOWED=NO test
else
    printf 'NOT_RUN\tui-tests\n' >> "$output/results.tsv"
fi
printf 'Build checks complete. Device, authentication, Excel, and profiling checks still require recorded evidence.\n'
