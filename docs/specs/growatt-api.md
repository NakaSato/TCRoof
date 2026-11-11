# Growatt endpoints

Every Growatt call the code makes or knows of, by the three ways in. The OpenAPI is the one to build on. The web portal is undocumented and needs a signed-in session, so it can change without notice.

## 1. Server OpenAPI v1 (`GrowattAPI` package)

The `GrowattAPI` Swift package at the repo root (`GrowattAPI/`) is the client. It has its own `Package.swift` and depends on nothing but Foundation; `TCRoofKit` depends on it by path and `TCRoofCore` re-exports it (`GrowattAPI+Overview.swift`). Test it with `swift test` in `GrowattAPI/`, also on Linux (`tools/linux-swift/test.sh` runs it after the kit).

- Hosts: `https://openapi.growatt.com/v1/` with the company's token (`GrowattAPI.live`); `https://test.growatt.com/v1/` with the guide's public token (`GrowattAPI.demo`), whose plants are samples without inverters. The live server answers the test token with 10011.
- Every request carries the header `token`. Every answer is `{ data, error_code, error_msg }`; `error_code` may be a number or text.
- 10012 (`error_frequently_access`): calls on the same plant closer than about 5 minutes get it. Without a gate the client retries 3 times, 6, 12 and 18 s apart. The app never retries: every client it makes (`MonitoringStore.api`) goes through `GrowattGate.shared`, which refuses the same call (path with its query or form: the same plant, day, page) again within 4:30 before it's sent (`Failure.tooFrequent`), spaces any two calls on a token 1.5 s apart, and on a 10012 holds that endpoint (its path, any query, so another page or the list without paging too) on the token for 5:15, sending nothing until then. The waits are kept in the device's defaults (`growatt.gate`, hashed keys, never the token), so a relaunch doesn't call into one. ตั้งค่า Monitoring shows an account's wait (`MonitoringStore.retryAt`: `รอ Growatt ถึง 23:58`, the test button off until then). A call that never reached Growatt's API (no network, cancelled, an HTTP error) gives its slot back, so trying again goes at once. Monitoring's poll paces itself at 4:45 a call per plant (`MonitoringFeed.callGap`), so the gate never refuses it.
- The plant list is kept on the device per account (`MonitoringStore.plantLists`, `monitoring.plants`): the pairing pane reads it, and `ทดสอบ` and adding an account read Growatt again. When `plant/list` has none, the pairing pane offers `ดู Plant ของผู้ใช้ปลายทาง`: one `user/c_user_list`, then one `plant/user_plant_list` per end user tapped, never all at once. A row's id and name are read as `plant_id` / `plantId` / `id` and `name` / `plant_name` / `plantName`; rows none of which reads throw `badResponse` rather than reading as no plants. A live account answered `plant/list?page=1&perpage=100` with `count` 1 and `plants: []` (unconfirmed why), so `plants`, `plantPage`, `allPlants` and `userPlants` ask 20 a page by default (`plantListPage`, the guide's default), and a first page with no rows but a `count` above 0 is asked once more with no paging. When `ทดสอบ` finds no plants, the account card shows the answer's outline (`GrowattAPI.outline`: keys, types, list lengths, `count`, `error_code`; no values).
- Sources: "Growatt Server Open API protocol standards" and "Growatt Server API Guide" (2016), copies at `soulraven.github.io/growatt-monitor/assets/`.

### Ported (read only)

| Swift | Endpoint | Method | Parameters | Answer |
|---|---|---|---|---|
| `plants`, `plantPage`, `allPlants` | `plant/list` | GET | `page`, `perpage` (≤100), `search_type=name`, `search_keyword` | `plants[]`, `count` |
| `userPlants` | `plant/user_plant_list` | POST | `user_name`, `page`, `perpage` | `plants[]`, `count` |
| `details` | `plant/details` | GET | `plant_id` | name, user, place, `peak_power`, `timezone`, arrays, inverters |
| `data` | `plant/data` | GET | `plant_id` | energy today / month / year / total, `current_power`, `last_update_time`, `timezone` |
| `power` | `plant/power` | GET | `plant_id`, `date` | `powers[]` every 5 min, W |
| `energy` | `plant/energy` | GET | `plant_id`, `start_date`, `end_date`, `time_unit` | `energys[]`; a range too long gets 10004 |
| `dataloggers` | `device/datalogger/list` | GET | `plant_id`, `page`, `perpage` | `dataloggers[]` |
| `devices`, `devicePage` | `device/list` | GET | `plant_id`, `page`, `perpage` | `devices[]`: `device_sn`, `type`, `status`, `lost`, `device_id` |
| `alarms` | `device/inverter/alarm` | GET | `device_sn`, `date` (not in either guide, but required), `page`, `perpage` | `alarms[]`: `alarm_code`, `alarm_message`, `start_time`, `end_time`, `status` |
| `inverterHistory` | `device/inverter/data` | GET | `device_sn`, `start_date`, `end_date` (≤7 days), `page`, `perpage` (≤1000) | `datas[]`, `next_page_start_id` |
| `latest(deviceSN:)` | `device/inverter/last_new_data` | GET | `device_sn` | latest readings: `pac`, `powerToday`, strings, `faultType`, `warnCode` |
| `latest(deviceSNs:)` | `device/inverter/invs_data` | POST | `pageNum`, `inverters` (≤100) | each inverter's latest readings by SN; `Latest.stringCurrents` (`currentString1…`) and `mpptCurrents` (`ipv1…`) |
| `info` | `device/inverter/inv_data_info` | GET | `device_sn` | settings and state: `nominalPower`, `fwVersion`, `lost` |
| `storageAlarms` | `device/storage/alarm_data` | POST | `storage_sn`, `date`, `page`, `perpage` | `alarms[]` |
| `storageLatest` | `device/storage/storage_last_data` | POST | `storage_sn` | latest readings |
| `storageHistory` | `device/storage/storage_data` | POST | `storage_sn`, `start_date`, `end_date`, `page`, `perpage` | `datas[]` |
| `endUsers` | `user/c_user_list` | GET | `page`, `perpage` | `c_user[]`, `count` |

Readings with many fields (inverter and storage) come back as `Readings`, every field kept as a `JSONValue`, with the common ones named on `Latest`.

Not confirmed against a live answer:
- `device/inverter/alarm`: needs a `date` (`yyyy-MM-dd`) that neither guide names: without it the test server answers 10003 `error_dateError`; with it and `device_sn` it looks the inverter up (10005 for a serial it doesn't know), while `device_id` gets 10002 (10 Nov 2026). The meaning of an alarm's `status` isn't given.
- Times: the guide's examples write `2015-12-08T11:05:00Z` and `2016-04-28 18:41:40.0`, while live `plant/data` writes `yyyy-MM-dd HH:mm:ss` on the plant's clock.
- `invs_data`: the guide shows `inverters` as an array without saying how a form carries it; it is sent as JSON (`["SN1","SN2"]`). Monitoring reads the string currents from it (CHA-106) by the names the portal's chart answered for a MAX (`currentString1…32`, else `ipv1…` per MPPT, two strings to an MPPT, `GrowattMap.mppts`), not yet seen in this answer: the device calls it for the station page shown (CHA-107) and treats a failure as no news (the last currents stay, nothing shows in the header). Record a live answer for the tests when a token and a MAX plant are at hand.
- `search_type`: the appendix gives `name`, the example `PlantName`.

### Left out on purpose

These change something on Growatt, and nothing in the app should: `user/user_register`, `user/check_user`, `user/modify`, `plant/add`, `plant/modify`, `plant/delete`, `device/datalogger/add`, `device/datalogger/delete`, `device/datalogger/validate`, `inverterSet` and `storageSet` (these two switch equipment on and off and change its settings).

### Polling

Only the device reads Growatt (`MonitoringFeed`, for `MonitoringStore`): there is no server poll, and none of Growatt's answers go through Firebase. The device reads only while its Monitor tab is shown (`MonitoringPoller`, in `PadTabs` and `PhoneTabs`): on any other tab it calls nothing, so the dock's badge and the iPad's alerts keep their last reading. Each paired station whose token is on the device, one call after another, and only what a screen shows (CHA-107):

| What | Call | When | Calls |
|---|---|---|---|
| Summary | `plant/data`, `plant/power` (the whole day so far), `device/list` | every `pollMinutes` (5 at the most often); coming back to the tab before then reads nothing | 3 |
| Yesterday | yesterday's `plant/power` (`เทียบเมื่อวานเวลาเดียวกัน`) | the iPad overview's chart on `วันนี้`, or a station page on it; once a day, on a poll after one that read today's power (that poll's today's curve is the last poll's) | 1 |
| Days | `plant/energy` by day, 30 days | a chart on `7 วัน` or `30 วัน`; once a day, a week a poll | 5 |
| Months | `plant/energy` by month, 12 months | a chart on `12 เดือน`, or a station page (its month card); once a day | 1 |
| String currents | `invs_data` | the station page shown, with each summary | 1 |

The overview's chart range reads its history for every station; a station page reads its own only. A new pairing, server or token reads the summary at once, except on a plant read less than 5 minutes before.

No call is made twice on a plant within 5 minutes (`MonitoringFeed.callGap`, `lastCall`): Growatt answers 10012 to the same call again sooner, and the SDK's retries (36 s at most) don't outlast that. The history is one call a poll per station, without retries; a 10012 there waits for the next poll and isn't shown in the header. The `บำรุงรักษา` overview reuses these readings and calls nothing.

Each device with the token polls on its own, so two iPads open on Monitoring make twice the calls on the same account.

Still to check on the live server: whether 10012 limits calls per plant or per token.

## 2. Web portal, guest session (`TCRoofCore/GrowattWebDemo`)

`https://server.growatt.com/`, a cookie session on the portal's example account, for the DEBUG `-growattDemo YES` overview (docs/debug-flags.md). The calls go through the package's `GrowattPortal` (`openGuest()` for the guest login, `post` for the rest, `dayChart` for the power), which keeps the session's cookies; the guest login answers 200 with them (no redirect) and expires a few at once (`selPage`, `Max-Age=0`), which aren't kept.

| Endpoint | Method | Parameters | Answer |
|---|---|---|---|
| `login/toViewExamlePlant` | GET | none | opens the guest session |
| `index/getPlantListTitle` | POST | none | the home dashboard's plants |
| `indexbC/getPlantListTitle` | POST | none | the business dashboard's plants |
| `panel/getPlantData` | POST | `plantId` (form; the query works too, checked 11 Nov 2026) | one plant's totals |
| `panel/getDevicesByPlantList` | POST | `plantId`, `currPage` | devices, 4 a page |
| `energy/compare/getDevicesDayChart` | POST | `plantId`, `date`, `jsonData` | one day's power, 288 points |

## 3. Web portal, signed-in account (`GrowattPortal` in the package)

Captured from a browser on `server.growatt.com` (10 Nov 2026), signed in to a company account, and ported as `GrowattPortal` in the `GrowattAPI` package. Nothing in the app calls its signed-in calls yet; the guest demo above uses its transport.

- It needs a browser session: give the `Cookie` header's text (`JSESSIONID`, `assToken`, …) to `useCookies(_:)`. The client sends the cookies itself and keeps those the portal renews (`SERVERID`). The cookies work like the account's password until the session ends, so keep them out of the repo, tickets and logs.
- Signing in with a username and password isn't ported: its request hasn't been captured.
- An expired session gets the login page, which throws `GrowattAPI.Failure.signedOut`. A `result` other than 1 throws `api(result, msg)`.
- Lists come back as `GrowattPortal.Page`: rows from `obj.datas` (or `obj` as a list), `currPage`, `pages`, `count`. Each row is kept whole as `JSONValue`, since no real answer has been read yet.

| Swift | Endpoint | Method | Body | What it is |
|---|---|---|---|---|
| `plantList`, `allPlants` | `selectPlant/getPlantList` | POST | `currPage`, `plantType=-1`, `orderType=2`, `plantName` | the account's plants, paged (`plantSize` cookie: 43 plants) |
| `faultLog` | `log/getNewPlantFaultLog` | POST | `deviceSn`, `date`, `plantId` (-1 all), `toPageNum`, `type`, `deviceFlag=0` | the fault log of a period: `type` 1 a day (`date` `2026-11-09`), 2 a month (`2026-11`), 3 a year (`2026`) (`LogPeriod`); `deviceFlag`'s meaning isn't known |
| `compareDevices` | `energy/compare/getNewPlantDevices` | POST | `plantId` | the plant's devices that Energy › Compare offers for its charts |
| `dayChart` | `energy/compare/getDevicesDayChart` | POST | `plantId`, `date` (`yyyy-MM-dd`), `jsonData` | a day of each series, 288 values 5 min apart (`pac`, W) |
| `monthChart` | `energy/compare/getDevicesMonthChart` | POST | `plantId`, `date` (`yyyy-MM`), `jsonData` | a month of each series, a value a day (`energy`, kWh) |
| (not ported) | `log/getFaultUnreadLogPage`, `log/getFaultLogPage` | (pages) | none | the Log pages, named in the `selPageTwo` cookie |

`jsonData` names the chart's series: `[{"type":"max","sn":"GKLLEXC006","params":"energy"}]` (an inverter by its portal type and serial number, or `"type":"plant"` with the plant id). `params` seen so far: `pac` (power, W) and `vString1` (string 1 voltage, V; presumably `vString2`… for the others, as in the OpenAPI's `last_new_data`) on the day chart, `energy` (kWh) on the month chart, and a meter's `positiveActiveTodayEnergy` (energy from the grid today, kWh) and `power_factor` on the day chart (`ChartParam.meter`). An environment sensor is `"type":"env"`, named the same way (`DYDCE9302Z_6`, address 6; `ChartSeries.env(datalogger:address:)`), with `env_temp` (air, °C), `panel_temp` (module, °C) and `radiant` (irradiance, W/m² presumably) `sensorSingnalGen` (Growatt's spelling; meaning and unit unknown) and `wind_angle` (wind direction, degrees presumably) seen (`ChartParam.env`). A meter is `"type":"meter"` with `sn` its data logger and its bus address (`DYDCE9302Z_36`; `ChartSeries.meter(datalogger:address:)`); the `memoryDeviceSn` cookie names the same meter `multipleBackflow%DYDCE9302Z_36@71`, the plant's zero-export meter. Its other values and their labels haven't been captured. The page's full list for a MAX / MID-X / MOD-X / MAC-X inverter is `GrowattPortal.ChartParam.maxInverter` (102 values: PAC, MPPT POWER, the phases' power and voltage, 10 MPPTs' power, voltage and current, 32 strings' voltage and current), looked up by label with `ChartParam.max(label:)`. Only `pac` and `vString1` have been seen in a request; the other names follow the OpenAPI's (`ppv`, `pacr`, `ppv1`, `vpv1`, `vacr`, `ipv1`, `currentString1`) and need checking. The answer is `{ result: 1, obj: [ { datas: { <params>: [values] } } ] }`, one entry per series (`GrowattWebDemo` reads the day chart's this way on the guest account). The page's year chart wasn't captured.

For inverter faults the OpenAPI's `device/inverter/alarm` covers the same need with the company token.

### Read live (10 Nov 2026)

Each portal call was made once with a signed-in session of the company account; the answers settled these:

- **Plant list:** the page's fields (`currPage`, `pages` 3, `pageSize` 20, `count` 43) and `datas` are at the top level, with no `result` / `obj`. A row: `id`, `plantName`, `currentPac` (power now), `eToday`, `onlineNum`, `plantType`, `accountName` (`GrowattPortal.plants(in:)`).
- **Fault log:** `{ result: 1, obj: { pages, currPage, count, datas } }`. A row: `eventId` (`Error 125`, `Warning 203(0)`), `eventName` (`PV Isolation Low`), `eventType` (0 error, 1 warning), `deviceSn`, `deviceModelName`, `deviceType`, `alias`, `plantId`, `plantName`, `time`, `recoveryTime` (null while raised), `solution`, `readFlag` (`GrowattPortal.faults(in:)`). `plantId=-1` gives every plant's events in one call, 10 a page.
- **Compare devices:** `obj` is a list of groups `{ deviceTypeName, devices: { <sn>: [[sn, alias, status, logger, logger, ?]] } }` (`max`, `meter`, `env`; status -1 lost) (`compareDevices`).
- **Charts:** one call takes several series (an inverter's `pac`, the meter's `positiveActiveTodayEnergy` and the sensor's `radiant` together). Each answer entry names its series (`sn`, `type`, `params`, `selfDeviceType`). A day has 288 values, a month one a day; times and days not reached yet are 0, not null. `radiant` peaked at 982.7 (W/m²), the inverter's `pac` at 96,790 (W).
- **Chart names that answered on a MAX:** `pac`, `ppv`, `ppv1`, `vpv1`, `ipv1`, `pacr`, `pacs`, `pact`, `vacs`, `vact` (about 240 V), `vacrs` (R to S, about 416 V), `vString1`, `vString2`, `vString32`, `currentString1`, `currentString32`. `vacr`, `vac1` and `vacR` answer HTTP 500, so which name the page's R-PHASE VOLTAGE sends isn't known.
- **A name the device doesn't have** answers HTTP 500 with an HTML page that says to log in, though the session is fine (`.http(500)` in `GrowattPortal`).
- **Timing:** a chart the portal hasn't served lately took 68 s; the rest under a second (`GrowattPortal.timeout` is 90 s).
