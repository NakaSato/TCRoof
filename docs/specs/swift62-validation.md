# Swift 6.2 and concurrency validation

The package requires Swift 6.2 / Xcode 26, retains Swift 5 language mode, and keeps
its iOS 17 / macOS 14 deployment targets. The app's deployment target remains iOS 18.

## Review follow-up

- Code exchange rejects missing/empty replacement refresh tokens before clearing
  previous credentials; empty access tokens are rejected during response decoding.
- `accessToken(validFor:)` enforces the full requested lifetime after refresh and
  rejects invalid durations. A token that is too short for background work can
  still be used for an eligible shorter foreground request without signing out.
- ZIP decoding verifies expanded size and CRC, with configurable `ReadLimits`.
  Defaults are 64 MiB per entry and 256 MiB total expanded content, including
  directory and duplicate entries. Limits are checked before buffer allocation;
  input and metadata overhead are separate. All 132 repository archives (2,789
  entries) passed the new limits, size checks, and CRC validation. The largest
  entry was 8.73 MiB; the largest expanded archive was 74.92 MiB.
- `TCRoofCore/SingleLineRender.swift` owns observable asynchronous diagram state.
  The diagram page and B4/B5 previews show a loading state for the first result,
  retain the previous result during edits, and cancel on disappearance. Reading
  `result` never performs model building or layout on the main actor.

## Browser authorization fix

`OAuthBrowserAuthorization` owns one browser request and resumes its continuation
once. A failed `start()` returns an error immediately. Cancelling its caller closes
the browser and completes the request even if the platform never sends a callback.
Duplicate and late callbacks are ignored. `GoogleAuth` keeps the session-generation
checks that prevent an old browser result from updating a different account.

Nine portable tests cover failed startup, synchronous and duplicate callbacks,
callbacks on another executor, caller cancellation, explicit cancellation, late
callbacks, cancellation before startup, and request reuse.

## Validation scope

The current environment is Linux with the official Swift 6.2 Docker toolchain.
Linux tests exercise the production token/session and background-work code, both
pure Swift hashing paths, ZIP round trips, workbook export fixtures, and diagram
models. A GoogleAuth type-check with platform stubs checks its wiring only; it is
not an Apple SDK build or a real Keychain/browser integration test.

| Check | Required environment | Status |
| --- | --- | --- |
| Browser/token lifecycle and background cancellation tests | Swift 6.2, Linux or macOS | Passed in Debug and Release |
| Hash vectors, padding boundaries, and sliced input | Swift 6.2, Linux or macOS | Passed in Release |
| ZIP/export and diagram model regression tests | Swift 6.2, Linux or macOS | Passed in Release |
| Debug and Release application builds | Xcode 26+ | Pending: unavailable on Linux |
| Runtime guards and older-runtime fallback | Supported older iOS runtime and iOS 26 | Pending |
| Real Google browser and Keychain flows | iOS device or simulator | Pending |
| Rapid-scroll/photo-replacement thumbnail checks | iOS device or simulator | Pending |
| Workbook reopening and layout verification | Excel and the iOS app | Pending |
| Instruments measurements and TestFlight smoke checks | Physical iOS device and Xcode | Pending |

## Repeatable checks

Run the focused Linux checks from the repository root using Swift 6.2:

```bash
tools/linux-swift/test.sh --filter 'OAuthBrowserAuthorizationTests|OAuthTokenSessionTests|BackgroundWorkTests'
tools/linux-swift/test.sh -c release --filter 'OAuthBrowserAuthorizationTests|OAuthTokenSessionTests|BackgroundWorkTests|ReviewTests|ZipArchiveTests|SingleLineRenderTests|SingleLineTests|^ExcelExportTests.ExcelExportTests/|WBSDependencyExcelTests'
SLD_SVG=/tmp/tcroof-sld-validation tools/linux-swift/test.sh -c release --filter 'SingleLineTests/testWriteSVG'
```

The Release run selected 73 tests: 72 passed and the opt-in SVG export was skipped
because `SLD_SVG` was unset. The final command was then run with the directory set;
the remaining test passed and produced five non-empty, well-formed SVG diagrams.
All 73 selected tests therefore passed across the two runs.

After the review follow-up, the expanded Release selection (including renderer
state, token lifetime, malformed ZIP cases, and WBS export fixtures) passed **93
tests with zero failures or skips**, with `SLD_SVG` configured for that run. The
four changed UIKit source files also passed syntax parsing; this is not an Apple
SDK type-check or UI integration test.

On the Mac, inspect available destinations and build both app configurations with
isolated build output:

```bash
xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -showdestinations
xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tcroof-validation-debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tcroof-validation-release CODE_SIGNING_ALLOWED=NO build
```

Exercise sign-in cancellation and failed browser startup, sign-out while refresh
is pending, and switching accounts before an old request finishes. Verify that
credentials are never restored by old callbacks and only one refresh is sent for
concurrent callers. Verify that a cancelled sign-in preserves the previous stored
account and allows a subsequent attempt.

Exercise all three thumbnail grids with rapid scrolling, photo replacement, and
navigation away while decoding. No cancelled request may publish an old image.
Verify that rapid diagram edits build the latest result without concurrent builds.

## Performance and release gate

Use Release builds and fixed workloads for Instruments Time Profiler, Allocations,
and retained-object checks. Record device/OS/toolchain, workload size, elapsed time,
peak memory, and frame responsiveness before changing another hot path. Compare
the same workload after each optimization; Linux microbenchmarks do not establish
on-device improvements.

The Apple-platform checks above are still required before distributing a test
build. These Linux results do not establish that the unpublished commit range is ready
for release.

### Repeatable microbenchmarks

Run with Swift 6.2, Clang, zlib headers, and Python 3 installed:

```bash
python3 tools/performance/benchmark.py --samples 3 > /tmp/tcroof-performance.json
```

The tool compiles the current production SHA and ZIP sources with `-O`. Each run
uses a fresh observer process so compiler memory is excluded from peak RSS. It
checks hashes against Python's `hashlib` and checks ZIP CRCs and compression modes
with Python's independent ZIP reader. On older macOS versions, the reported
`implementation` identifies when the selected SHA path is the legacy fallback.

On this Linux session with Swift 6.2.4, three 16 MB hashing runs had median peak RSS
of 49.0 MiB for the legacy path and 34.4 MiB for the inline/span path. Median elapsed
times were 0.117 s and 0.077 s respectively. The synthetic ZIP round trip used
147.8 MiB peak RSS and 0.438 s median time. ZIP timing includes integrity checks and
writing the resulting archive. These are workload-specific observations, not
cross-platform performance budgets or evidence of iOS frame responsiveness.
