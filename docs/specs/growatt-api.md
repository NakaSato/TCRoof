# Growatt endpoints

Every Growatt call the code makes or knows of, by the three ways in. The OpenAPI is the one to build on. The web portal is undocumented and needs a signed-in session, so it can change without notice.

## 1. Server OpenAPI v1 (`GrowattAPI` package)

The `GrowattAPI` Swift package at the repo root (`GrowattAPI/`) is the client. It has its own `Package.swift` and depends on nothing but Foundation; `TCRoofKit` depends on it by path and `TCRoofCore` re-exports it (`GrowattAPI+Overview.swift`). Test it with `swift test` in `GrowattAPI/`, also on Linux (`tools/linux-swift/test.sh` runs it after the kit).

- Hosts: `https://openapi.growatt.com/v1/` with the company's token (`GrowattAPI.live`); `https://test.growatt.com/v1/` with the guide's public token (`GrowattAPI.demo`), whose plants are samples without inverters. The live server answers the test token with 10011.
- Every request carries the header `token`. Every answer is `{ data, error_code, error_msg }`; `error_code` may be a number or text.
- 10012 (`error_frequently_access`) is retried 3 times, 6, 12 and 18 s apart. Calls on the same plant closer than about 5 minutes get it.
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
| `alarms` | `device/inverter/alarm` | GET | `device_sn`, `page`, `perpage` | `alarms[]`: `alarm_code`, `alarm_message`, `start_time`, `end_time`, `status` |
| `inverterHistory` | `device/inverter/data` | GET | `device_sn`, `start_date`, `end_date` (≤7 days), `page`, `perpage` (≤1000) | `datas[]`, `next_page_start_id` |
| `latest(deviceSN:)` | `device/inverter/last_new_data` | GET | `device_sn` | latest readings: `pac`, `powerToday`, strings, `faultType`, `warnCode` |
| `latest(deviceSNs:)` | `device/inverter/invs_data` | POST | `pageNum`, `inverters` (≤100) | each inverter's latest readings by SN |
| `info` | `device/inverter/inv_data_info` | GET | `device_sn` | settings and state: `nominalPower`, `fwVersion`, `lost` |
| `storageAlarms` | `device/storage/alarm_data` | POST | `storage_sn`, `date`, `page`, `perpage` | `alarms[]` |
| `storageLatest` | `device/storage/storage_last_data` | POST | `storage_sn` | latest readings |
| `storageHistory` | `device/storage/storage_data` | POST | `storage_sn`, `start_date`, `end_date`, `page`, `perpage` | `datas[]` |
| `endUsers` | `user/c_user_list` | GET | `page`, `perpage` | `c_user[]`, `count` |

Readings with many fields (inverter and storage) come back as `Readings`, every field kept as a `JSONValue`, with the common ones named on `Latest`.

Not confirmed against a live answer:
- `device/inverter/alarm`: the protocol PDF names the parameter `device_id`, the guide's example `device_sn`; the SDK sends `device_sn`. The meaning of an alarm's `status` isn't given.
- Times: the guide's examples write `2015-12-08T11:05:00Z` and `2016-04-28 18:41:40.0`, while live `plant/data` writes `yyyy-MM-dd HH:mm:ss` on the plant's clock.
- `invs_data`: the guide shows `inverters` as an array without saying how a form carries it; it is sent as JSON (`["SN1","SN2"]`).
- `search_type`: the appendix gives `name`, the example `PlantName`.

### Left out on purpose

These change something on Growatt, and nothing in the app should: `user/user_register`, `user/check_user`, `user/modify`, `plant/add`, `plant/modify`, `plant/delete`, `device/datalogger/add`, `device/datalogger/delete`, `device/datalogger/validate`, `inverterSet` and `storageSet` (these two switch equipment on and off and change its settings).

### Cloud Function

`functions/src/growatt.ts` (`GrowattClient`) makes the same GETs from the server poll: `plant/data`, `plant/power`, `device/list`, `plant/energy` (TCRoof/CLAUDE.md, Monitoring's server poll).

### Polling

How the Cloud Function reads the company's plants (`functions/src/monitoring.ts`), so the calls grow slowly with the fleet:

| What | Call | How often | Calls |
|---|---|---|---|
| The fleet's power now | `plant/list`, 100 plants a page | every run (`pollMinutes`, 5) | 1 per 100 plants per account |
| A healthy station's detail | `plant/data`, `plant/power` (the whole day so far), `device/list` | every `detailMinutes` (15), a third of the fleet a run | 3 |
| A station in alarm or offline | the same | every run | 3 |
| History | yesterday's `plant/power`, `plant/energy` by day (5 calls) and month | once a Bangkok day | 7 |

For 43 healthy plants that is about 13,000 calls a day, against 37,000 when every station's detail was read every 5 minutes. The iPads judge the server's reading fresh within two detail reads and a minute; past that they read Growatt themselves.

Still to check on the live server: that `plant/list` gives every plant's `current_power` (the test server's sample plants never report), and whether 10012 limits calls per plant or per token.

## 2. Web portal, guest session (`TCRoofCore/GrowattWebDemo`)

`https://server.growatt.com/`, a cookie session on the portal's example account, for the DEBUG `-growattDemo YES` overview (docs/debug-flags.md).

| Endpoint | Method | Parameters | Answer |
|---|---|---|---|
| `login/toViewExamlePlant` | GET | none | opens the guest session |
| `index/getPlantListTitle` | POST | none | the home dashboard's plants |
| `indexbC/getPlantListTitle` | POST | none | the business dashboard's plants |
| `panel/getPlantData` | POST | `plantId` (query) | one plant's totals |
| `panel/getDevicesByPlantList` | POST | `plantId`, `currPage` | devices, 4 a page |
| `energy/compare/getDevicesDayChart` | POST | `plantId`, `date`, `jsonData` | one day's power, 288 points |

## 3. Web portal, signed-in account (`GrowattPortal` in the package)

Captured from a browser on `server.growatt.com` (10 Nov 2026), signed in to a company account, and ported as `GrowattPortal` in the `GrowattAPI` package. Nothing in the app calls it yet.

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
