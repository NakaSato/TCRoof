# Release readiness: Swift 6.2, authentication, and performance

This is the execution record for R01–R13. Apple validation is blocked on a Mac or
existing CI runner supplied for this task; the managed environment exposes Linux
only and no configured remote-host identity. A request for that environment is pending.

## Task status

| Task | Status | Evidence / next action |
| --- | --- | --- |
| R01 Review and commit pending fixes | Complete | `dd1688e4`, clean working tree after commit; 73 Release regression tests passed across the main run and SVG rerun |
| R02 Audit unpublished commits | Complete for source review and portable checks | Audited application range `07020a89..dd1688e4`; 41 additional storage/cache/WBS Release tests passed; release risks below remain open |
| R03 Configure Apple validation | Prepared; blocked on Mac access | `tools/apple/validate.sh` records toolchain, commit, logs, destinations, and result bundles; Linux guard verified |
| R04 Resolve Apple build compatibility | Blocked on R03 | Run Debug and Release SDK builds; Linux type-checks are not substitutes |
| R05 Validate platform authentication | Prepared; blocked on R04 | Execute browser, Keychain, and Firebase scenarios below |
| R06 Verify hashing runtime compatibility | Portable checks complete; Apple checks blocked | Known digests and both pure Swift implementations tested; verify availability on supported Apple runtimes |
| R07 Validate thumbnail and diagram UI | Portable checks complete; device checks blocked | Cancellation/model tests pass; five SVG diagrams parse successfully; run rapid-scroll and edit scenarios |
| R08 Verify workbooks in Excel | Export fixtures pass; manual checks blocked | Open generated exports in Excel and compare formulas, images, and print layout |
| R09 Define performance targets | Initial targets documented | Workloads and thresholds below; baseline on the chosen physical device is still required |
| R10 Profile physical-device Release workloads | Blocked on R03–R09 | Capture Instruments traces using the fixed workloads |
| R11 Resolve measured blockers | Waiting on R10 | Create at most two-day fixes only for observed regressions; no further bottleneck established yet |
| R12 Finalize release evidence | In progress | Linux evidence recorded; Apple results and device measurements are missing |
| R13 Publish and distribute TestFlight | Blocked on R12 | No push, archive upload, or TestFlight distribution performed |

## Source audit

| Commit | Scope | Release implication |
| --- | --- | --- |
| `48bfb935` | Report store-load failures; preserve recovery files | Verify unreadable/corrupt surveys do not become cloud deletions |
| `0618d0f5` | Pace snapshot batches; skip redundant survey work | Verify initial sync stays responsive and completes all collections |
| `c485088c` | Isolate storage writes; cache fingerprints; bound collection processing | Verify autosave, deletion, reload, and sign-out during pending work on the actual app |
| `d2cf50db` | Report invalid directories consistently | Portable load-failure tests pass |
| `ca29b5e6` | Add WBS dependencies and working-day lag | Persisted format and sync compatibility change; see rollout condition below |
| `b3119808` | Reduce ZIP buffers; serialize/cancel obsolete diagram builds | Verify Excel interoperability and rapid diagram edits |
| `5fa0e427` | Require Swift 6.2; inline/span hashing; token and thumbnail isolation | Requires Xcode 26+; older runtime fallback and real authentication must be verified |
| `dd1688e4` | Handle browser startup failure, cancellation, and duplicate callbacks | Nine additional portable browser tests pass; actual AuthenticationServices validation remains open |

The 41 additional Release tests cover `JobStoreLoadTests`,
`JobStoreConcurrencyTests`, `RecordFingerprintCacheTests`, `WBSDependencyTests`,
and `WBSDependencyExcelTests`. They passed with zero failures. They do not exercise
SwiftData or Firestore callbacks on Apple platforms.

### Rollout and rollback conditions

- The WBS commit raises `AppCompat.syncVersion` to **7** because earlier builds can
  drop dependency links when rewriting WBS rows. Confirm the intended rollout of
  the server's `config/app.minSyncVersion` before users edit dependencies. No
  server configuration was inspected or changed by this work.
- `origin/main` at `07020a89` is a source baseline, not an automatically safe data
  rollback after dependency links exist. `ca29b5e6` is a WBS-aware rollback candidate
  for the later performance changes, but it still needs a validated installable
  archive. No verified rollback binary is available in this environment.
- Authentication review must include `GoogleSession.firebaseUser`: its Firebase
  SDK sign-in is a separate awaited operation after OAuth token acquisition. The
  portable OAuth generation tests alone do not establish Firebase SDK behavior
  when sign-out/account switching overlaps that operation. Record the actual
  SDK account state before closing R05.
- Freeze the candidate commit only after Apple checks pass. Preserve local survey
  data and the WBS-aware sync requirement during rollback; do not revert persisted
  data or lower compatibility settings as part of a Git rollback.

## Apple runner

On a Mac with Xcode 26+ selected, run:

```bash
bash tools/apple/validate.sh --output /tmp/tcroof-apple-candidate
```

Inspect `destinations.log` or `simulators.json`, then run on each selected runtime
using a fresh output directory:

```bash
bash tools/apple/validate.sh --simulator SIMULATOR_UDID --ui-tests --package-tests --output /tmp/tcroof-apple-runtime-check
```

Use an app-supported older runtime (iOS 18) and an iOS 26 runtime. The package's
older iOS 17 / macOS 14 availability promises additionally need a compatible
package test host; do not raise deployment targets merely to make tests pass.
Record model, OS, Xcode version, commit, signing configuration, and every failed
or skipped check. Simulator builds disable signing; device installation and
TestFlight use the team's existing signing workflow separately.

The runner is syntax-checked, its help and Linux rejection paths are verified,
and its Xcode execution path is **not yet tested**.

## Fixed workloads and initial engineering targets

Use the same physical device, release configuration, fixtures, and network
conditions for baseline/candidate comparisons. Record one cold run and three warm
runs per workload; retain raw traces as well as medians. These initial targets
must be evaluated against the first device baseline; they are not measured results.

| Workload | Procedure | Target and correctness condition |
| --- | --- | --- |
| Photo grids | Use the same 100-photo job; visit feed, picker, and review; scroll down/up five times and replace a photo during decode | No stale image; no hang over 250 ms; investigate p95 frame time above 16.7 ms on a 60 Hz device; memory must plateau across repeated loops |
| Diagram editing | Use the same multi-transformer fixture with continuation rows; make 20 rapid edits and close/reopen | Only latest output is published; at most one build runs; input acknowledgment within 100 ms; no retained obsolete results after leaving |
| Workbook export | Export the same small and photo-heavy job three times; record sheet/photo counts and output size | Open in Excel without repair; formulas, images, and print setup preserved; investigate median time or peak memory regressions above 5% versus baseline |
| Authentication | Start ten concurrent Drive requests; cancel one caller; switch/sign out while refresh or Firebase sign-in is delayed | One shared OAuth refresh; no old-account credential publication; new account remains intact; browser startup failure and cancellation finish without a callback |
| Sync and storage | Use a fixed large local dataset; start sync while scrolling, editing, deleting, and signing out | No lost/recreated edits or cross-session results; no cloud deletion inferred from a load failure; no UI hang over 250 ms |
| Hash/ZIP microbenchmarks | Run `tools/performance/benchmark.py --samples 3` on the same host | Digests/CRC checks must pass; record median time, peak RSS, and selected implementation; do not equate host RSS with iOS memory limits |

For memory, investigate sustained growth or a reproducible median regression above
5%; any memory termination or retained work across navigation is a release blocker.
Absolute memory and export-time budgets require the actual device baseline and
fixture sizes. No claim of meeting device targets is made here.

## Integration evidence to collect

For R05, record cancellation before browser startup, `start()` failure, duplicate
or late callback, cancelling sign-in, sign-out during refresh, and account A → B
switching while a Firebase credential sign-in is pending. Check Keychain entries,
the displayed account, Firebase's current account, and actual Drive requests.
Use test accounts and do not put token values or personal data in artifacts.

For R08, open both small and photo-heavy exports in Excel. Compare sheet names,
formulas, calculated values, photos, Unicode labels, and print previews. Save the
Excel version and the source fixture identifier with the result.

For R10, collect Time Profiler, Allocations, and retained-object evidence using
Release builds. Turn each confirmed blocker into a separate, bounded fix with
before/after traces and affected regression tests. Stop further speculative type
or concurrency rewrites until those measurements identify a need.

For R13, record the published commit, archive/build identifier, TestFlight build,
and installation/sign-in/photo/diagram/export smoke results only after R12 is
complete. Publication has not been attempted.
