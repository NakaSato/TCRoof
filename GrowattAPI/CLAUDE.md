# `GrowattAPI` Swift package

Read with the root CLAUDE.md. Run package commands from this folder. The endpoint reference, with what is confirmed and what isn't, is `docs/specs/growatt-api.md`; keep it in step with every change here.

**What it is:** a local package (its own `Package.swift`, Foundation only, iOS 17 / macOS 14, Swift 5 language mode) that talks to Growatt. One library, `GrowattAPI`, two clients:

- `GrowattAPI` (the struct): Growatt's server OpenAPI v1 with a company token (`GrowattAPI.live(token:)` on `openapi.growatt.com/v1/`; `GrowattAPI.demo` is the guide's public test server and token). Every read call of the 2016 guides, one file per area: `+Plants` (`plant/list`, `details`, `data`, `power`, `energy`, `user_plant_list`), `+Devices` (`device/list`, `datalogger/list`), `+Inverter` (`alarm`, which needs a `date`; `data`, `last_new_data`, `invs_data`, `inv_data_info`), `+Storage`, `+Users`. Readings with many fields come back as `Readings` (`JSONValue` by field); paged calls as `Page<Item>` with Growatt's `count`.
- `GrowattPortal`: the web portal (`server.growatt.com`) on a signed-in browser session's cookies (`useCookies(_:)`; the client sends them itself and keeps those the portal renews). The calls captured from the portal's pages: `plantList`, `faultLog` (day / month / year, `LogPeriod`), `compareDevices`, `dayChart` / `monthChart` (several series in one call). Typed rows in `+Rows` (`PlantRow`, `FaultEvent`, `CompareDevice`); the chart values each device offers in `+Params` (`ChartParam.maxInverter`, `.meter`, `.env`; `confirmed` marks names that answered on the live portal). Signing in from code isn't ported (its request hasn't been captured).

**Who uses it:** `TCRoofKit` depends on it by path (`../GrowattAPI`) and `TCRoofCore` re-exports it (`@_exported import GrowattAPI` in `TCRoofCore/GrowattAPI+Overview.swift`, which also holds the app-side `summary`), so the app and `TCRoofUI` use it without importing it. The Xcode project lists it under Package Dependencies. Monitoring maps its answers (`TCRoofCore/Monitoring/Monitoring+Growatt.swift`); the app is its only caller, from the device.

**Rules:**
- Read only. Growatt's calls that change something (`inverterSet` and `storageSet` switch equipment on and off and change its settings; `plant/add|modify|delete`, `datalogger/add|delete`, the `user/*` writes) stay out unless someone asks for one by name.
- The module and its main type share the name `GrowattAPI`: inside the package and in `@testable` tests that is fine; don't add a type named after another module.
- Keep it Foundation only and building on Linux (`#if canImport(FoundationNetworking)` where URLSession is used); `tools/linux-swift/test.sh` runs its tests after TCRoofKit's.
- Growatt writes numbers as numbers or text and booleans as booleans, numbers or text: read them through `GrowattAPI.number` / `bool` or `JSONValue.number` / `int` / `bool`, never with a plain cast. What Growatt didn't give is nil, never 0.
- Errors are `GrowattAPI.Failure` (its `message` is Thai, shown as is): `.api(code, msg)`, `.tooFrequent` after the retries of 10012, `.http`, `.offline`, `.badResponse`, and `.signedOut` for the portal's login page. A chart value a device doesn't have answers HTTP 500 with a page that says to log in; that is `.http(500)`, not `.signedOut`.
- 10012 (`error_frequently_access`): calls on one plant closer than about 5 minutes. The client retries 3 times, 6, 12 and 18 s apart; don't add calls to a poll without checking the budget (docs/specs/growatt-api.md, "Polling").

**Tests:** `swift test` here (`GrowattAPITests`), all against a stubbed `URLSession` (`GrowattStub` in `GrowattAPITests.swift`: queued replies, the requests and their bodies), on answers copied from the guides, the test server and live portal answers. A request the portal or a browser sent is pinned byte for byte (the form body, `jsonData`). Nothing here calls Growatt; to try a live call, use a throwaway package outside the repo that depends on this one by path, and keep tokens and session cookies out of the repo, tests and logs.

**Secrets:** a company token lives only in the Keychain of each device it was typed on (`MonitoringToken`), never in code or Firebase. Portal cookies (`JSESSIONID`, `assToken`) work as the account's password until the session ends; tests use made-up values.
