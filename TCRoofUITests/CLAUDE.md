# UI tests

The catalogue of tests (what each taps, its launch arguments) is `docs/ui-tests.md`; the DEBUG launch arguments are `docs/debug-flags.md`. Add a new test to the catalogue.

Run on a simulator of the size the test needs (each test says iPad or iPhone), with your own derived data path; add `-only-testing:TCRoofUITests/<Class>` for one class:

```
xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -derivedDataPath <scratch>/DerivedData
```
UI tests that change answers start from `-surveyFreshJob YES`, since the demo job keeps its answers between runs.
The first launch in a simulator is slow, so the waits are long (about 90 s). Use `.matching(...).firstMatch` for buttons that share a name, and wait for non-existence with `XCTNSPredicateExpectation` (`waitForExistence` returns at once while the old element is still there).
