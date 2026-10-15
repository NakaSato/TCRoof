# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

TCRoof is an iPad-first SwiftUI app (iOS 17, bundle `com.tcroof.internal`) for a solar installer: jobs, install plans, device scans, install logs, and the **solar site survey** module, which produces the company's PDF report and Excel workbook. UI text is Thai.

## Build and test

- **Package logic and tests (fast, macOS):** run from `TCRoofKit/`
  - `swift build`
  - `swift test`
  - `swift test --filter InverterStationTests` (one class) or `swift test --filter InverterStationTests/testOutdoorRoom` (one test)
- **`TCRoofUI` and the app:** these are wrapped in `#if canImport(UIKit)`, so `swift build` on macOS does **not** compile them. Verify UI changes with xcodebuild:
  ```
  xcodebuild -project TCRoof.xcodeproj -scheme TCRoof -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DerivedData build
  ```
  Always pass your own `-derivedDataPath`. The user keeps Xcode open, and a CLI build in the shared DerivedData locks Xcode's `build.db`. Reuse the same path between builds: a clean build takes over 10 minutes, so run it in the background.
- **Lint:** there is no SwiftLint or swift-format config and no CI; the checks are `swift test` and the xcodebuild build.
- **Toolchain:** if `swift build` fails on `actool`, or `xcodebuild` says the active developer directory "is a command line tools instance", prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Secrets:** `Config.xcconfig` includes the git-ignored `Secrets.xcconfig` (copy `Secrets.example.xcconfig`) for `GISTDA_API_KEY`. The app builds without it.

### UI tests (iPhone taps)

`TCRoofUITests/PhoneSurveyUITests.swift` taps through the iPhone survey pages (A1 save button and `คัดลอก`, A2 picture to full screen, A3 breaker sheet, single line toggle) in the demo job, using the launch arguments below. Run on an iPhone simulator with your own derived data path:
```
xcodebuild test -project TCRoof.xcodeproj -scheme TCRoofUITests -destination 'id=<udid>' -derivedDataPath <scratch>/DerivedData
```
`TCRoofUITests/ReviewLockUITests.swift` runs on an iPad simulator (same command, `-only-testing:TCRoofUITests/ReviewLockUITests`): a missing photo filled from the stubbed camera, then sign → lock → open REV 01 → edit → sign → the change list. `TCRoofUITests/HomeNavbarUITests.swift` (iPad, `-only-testing:TCRoofUITests/HomeNavbarUITests`) checks the home bar and dock: the bell toggles its panel, the dock's `ตั้งค่า` closes it and opens settings, a dock button opens its tab and a screen pushed there covers the dock, the `โครงการ` tab opens the PWA home with its filter and bell, `อ่านทั้งหมด` clears the count, and search opens the survey list focused. The read state stays on the simulator.
`TCRoofUITests/PhoneSurveyHomeUITests.swift` (iPhone, `-only-testing:TCRoofUITests/PhoneSurveyHomeUITests`) taps the survey home: the dock opens the survey form and the add-customer sheet, the next appointment, a list row and `ประวัติการสำรวจ` open their screens, and a day and a status chip become selected.
`TCRoofUITests/PhonePWAPlanUITests.swift` (iPhone, `-only-testing:TCRoofUITests/PhonePWAPlanUITests`) taps the PWA `แผนงาน` page: the view switch, an install row and an overdue handover open the station, a Gantt row opens แผนงาน MP, the two filters narrow their lists, and the calendar's month view, a tapped day and the list's position select a day. Its set-up launches `-screen mpall`, which gives the first four jobs an MP plan for good.
`TCRoofUITests/PhonePWAHomeUITests.swift` (iPhone, `-only-testing:TCRoofUITests/PhonePWAHomeUITests`) taps the PWA home under the main dock: `แผนงาน` pushes the plan over the dock and comes back, the bell opens the notifications, the filter's `ประเภทงาน` picks the view and `ล้าง` resets it, a maintenance row of `-surveyHomeDemo maintenance` opens a station, and the settings sheet has `ตั้งค่าโครงการ PWA`.
`TCRoofUITests/LiveNotificationBannerUITests.swift` (iPhone, `-only-testing:TCRoofUITests/LiveNotificationBannerUITests`) launches with `-notifDemo live`, which posts one example of each live notification case 8 s apart, allows notifications when iOS asks, and waits for each banner by its title. With `-noNotificationPrompt YES` on a fresh install nothing is posted, since permission was never asked.
`TCRoofUITests/StationDocsDraftUITests.swift` (iPad, `-only-testing:TCRoofUITests/StationDocsDraftUITests`) fills ร่างหนังสือแจ้งดับไฟ and keeps it: the paper gets a file and reads `ร่างแล้ว`. The answers and the file stay on the first installing job.
`TCRoofUITests/InstallTrackingUITests.swift` (iPad, `-only-testing:TCRoofUITests/InstallTrackingUITests`) taps the install tracking page's overview end with `-installDemo YES`: the KPI cell `ต้องดำเนินการ` opens its sheet and a row pushes its screen, a document tile lists its items and a line opens its daily report, the site panel's tabs switch, the `รายงานประจำวัน` tab's `ต้องทำ` filter and row button work, and `PDF รวม` opens the share sheet on a station seeded with `-installSeed YES` (that station keeps the reports), `รายละเอียดงาน` opens the job's screen and back returns, `ทดสอบ IEC 62446` opens the IEC test with `-iecDemo YES` and a Vmp typed in its after table is kept, a string opened from its before table takes IR +E from the pad and a stub photo, and a late task's cause chip is kept after a relaunch and clears when tapped again (on the first installing station's task 2).
`TCRoofUITests/InstallPerformanceUITests.swift` (iPad, `-only-testing:TCRoofUITests/InstallPerformanceUITests`) measures time, CPU and memory of switching the install page's tabs, opening the IEC string table and typing on its pad (5 runs each, Debug build). Its CPU figures include XCTest's own accessibility snapshots, which run inside the app; to see the app's own cost, attach Time Profiler to the app's process (`xcrun xctrace record --template 'Time Profiler' --device <udid> --attach <pid>`).
`TCRoofUITests/IECFlowUITests.swift` (iPad, `-only-testing:TCRoofUITests/IECFlowUITests`) runs the IEC 62446 test from nothing to the Excel through the screens (set-up, row fill and checks, every string on the pad before and after, performance, conditions, export), on the first installing station after `-iecClear YES`. The values are test inputs; read the exported file in the app's `tmp/` to check them. Its second test adds a third inverter to the sample (`-iecDemo reset`) and exports it (6 sheets).
`TCRoofUITests/IECStagesUITests.swift` (iPad, `-only-testing:TCRoofUITests/IECStagesUITests`) checks that the IEC test keeps its results: steps confirmed in `ขั้นตอนการทดสอบ` and the test closed by `เสร็จ` survive a relaunch, a closed test's string table is read only until `แก้ไข`, a reading left on the pad is saved when the app goes to the background and is closed there, and `เสร็จ` on a real test (`-iecDemo full` with `-iecStationLine`, which drops the sample label) books the MP plan's `3.1 Pre-Commissioning Test` at 100% (for good) before reopening the test. It starts from `-iecDemo full`.
`TCRoofUITests/ERCFlowUITests.swift` (iPad, `-only-testing:TCRoofUITests/ERCFlowUITests`) opens ลำดับ กกพ. after a failed design round and records the request again: the turn passes to the utility. Its second test opens the พค.2 papers from an open request and finds the flow's line on the job's card.
`TCRoofUITests/PadA1UITests.swift` (iPad, `-only-testing:TCRoofUITests/PadA1UITests`) resizes A1's report frame by a corner and resets it, in the landscape layout of `-surveyWideA1 YES`.
`TCRoofUITests/PhoneHomeFeedUITests.swift` (iPhone, `-only-testing:TCRoofUITests/PhoneHomeFeedUITests`) taps the demo feed of `-homeFeed demo`: a filter segment narrows the posts, `รับทราบ` and `แก้แล้ว` toggle, a post's text opens its record, the `เอกสาร` tab opens the document library, and the modules that left the dock are behind the settings sheet's `เครื่องมือวัด` row.
UI tests that change answers start from `-surveyFreshJob YES`, since the demo job keeps its answers between runs.
The first launch in a simulator is slow, so the waits are long (about 90 s). Use `.matching(...).firstMatch` for buttons that share a name, and wait for non-existence with `XCTNSPredicateExpectation` (`waitForExistence` returns at once while the old element is still there).

### Simulator checks (DEBUG launch arguments)

There is no Simulator.app here, so the simulator can't be rotated; landscape checks rely on these flags. Screenshot with `xcrun simctl io <udid> screenshot`.

```
xcrun simctl launch <udid> com.tcroof.internal -screen pwa -surveyDemo YES -surveyDemoSection YES -surveyWideA1 YES -surveyPage <page>
```

- `-screen <name>` skips sign-in and opens one app screen as the root of its own stack, with no way back to the home (`TCRoofApp.swift` `DebugScreen`; `pwa` is the survey module, under the main dock). On iOS 27 a screen pushed over the home at launch stays blank, so don't push it.
- `-surveyDemo YES` opens a demo job; add `-surveyDemoSection YES` to open its first section.
- `-surveyWideA1 YES` forces the two-column (landscape) wide pages and hides the sidebar.
- `-surveyStacked YES` forces the one-column (portrait) layout of the wide pages in a landscape simulator.
- `-surveyPage site|electrical|sld|inverter|panels|flood|water|backfeed|fts|roof|tank|final` opens that page (`JobEditor.openDebugPage`). No template has a tank, so `tank` first adds an empty D1 to a job without one.
- `-surveyB4 lv|lvdone|hv|hvdone` (with `-surveyPage backfeed`) writes that state of `docs/ui/survey-b4/states` into the opened B4, with generated placeholder photos.
- `-surveyB4Render YES` (with `-surveyPage backfeed`) writes B4 offscreen at free widths 1366 / 1180 to `Documents/backfeed-<w>x<h>.png`, and its one-column iPhone layout to `Documents/backfeed-phone.png`.
- `-surveyC1 span|spany|posts|pv|keepout|landscape|ridgev|frame-n|frame-w|frame-c|frame-r|bays12|picker|shape|material|wood` (with `-surveyPage roof`) writes the design's example roof into the opened job and opens that state of `docs/ui/survey-c1/states`.
- `-surveyRoofRender YES` (with `-surveyPage roof`) writes C1 offscreen at several free widths and heights to `Documents/roof-<w>x<h>.png`, for layout checks without rotating. ImageRenderer can't draw menus, text fields or scroll views; they show as placeholders or blank.
- `-surveyD1 default|size|t64|t30|t20|above|buried|custom|compass|span|empty|tab2|obst|obstbottom|obstshade|obstrow|obstfull|obstadded|obstdelete|layout|layoutbottom|layoutedit|layoutask|layoutfull|layoutmax|layoutdrawing` (with `-surveyPage tank`) writes the design's example tank into the opened job and opens that state of `docs/ui/survey-d1-size/states` (`tab2` opens sub-step 2). The `obst…` states seed the standard points as `docs/ui/survey-d1-obstacles-iphone` (8 of 15 checked, V9 moved and selected) and open sub-step 2: scrolled to its end, its shading view, the row question, the plan full screen, a hatch added on site, or the delete question. The `layout…` states check every point and open sub-step 3 (`docs/ui/survey-d1-layout-iphone`) with the automatic layout: scrolled to its end, แก้แผง with a panel off and a table removed, the question before จัดแผงใหม่, the plan full screen, หาผังแผงมากสุด, or the B1-C3 sheet.
- `-surveyTankRender YES` (with `-surveyPage tank`) writes D1 offscreen at free widths 1366 / 1180 / 1100 to `Documents/tank-<w>x<h>.png`, and its iPhone sub-step 1 (step line and cards, no scroll view) to `Documents/tank-phone.png`.
- `-surveyA1Render YES` (any page) writes A1 with the board's example answers offscreen at free widths 1366 / 1180 to `Documents/a1-<w>x<h>.png`, and its bottom bar at 1366 to `Documents/a1-bar.png` (with `-surveySave` for the save states).
- `-surveyFinalRender YES` (with `-surveyPage final`) writes E1 offscreen at free widths 1366 / 1180 to `Documents/final-<w>x<h>.png`.
- `-surveyE1 two|installable|notrec|alladded|empty|pad|pad2|cleared|complete` (with `-surveyPage final`) writes that state of `docs/ui/survey-e1/states` into the opened job, or opens a signature pad.
- `-surveyPage photos|revisions` opens ตรวจรูปทั้งหมด or REV และรายการแก้ไข (`docs/specs/review-lock-revisions-swift.md`). `-surveyReview sign|locked|rev01|broken` writes that review-lock state into the opened job: both signatures (the lock sheet opens), REV issued and locked, REV 00 issued then REV 01 opened with three changes, or locked then edited behind the lock (the integrity banner). They change the demo job for good; `rev01` and `broken` only run on a job with no REV yet.
- `-surveyFreshJob YES` (with `-surveyDemo YES`) opens a new job (docNo `UITEST`, with a station address), deleting the previous one; `-surveyTestJob YES` reopens that job as it was left. `-surveyCameraStub YES` makes ตรวจรูปทั้งหมด put a generated photo into a slot instead of opening the camera.
- `-surveyScrollEnd YES` opens a card page scrolled to its end (A1 and A2 on iPhone: the lower bands; with `-screen surveyForm`, the iPad survey form's photos and notes).
- `-surveySave saving|saved|clean` (any step) opens the save button in that state: spinner, green flash, green outline. iPhone `บันทึก`: `docs/ui/survey-a1-iphone/states/04`–`06`; iPad card pages' `บันทึกร่างตอนนี้`: `docs/ui/survey-a1-ipad/states/03`–`05`. `-surveyA1Internet yes|no` (iPhone A1) picks the `อินเทอร์เน็ต` answer.
- `-surveyExport YES` opens the export sheet.
- `-surveyHomeTab projects|plan|maintenance` (iPhone and iPad, with `-screen pwa` or `-screen home -homeTab pwa`) picks the PWA home's nav segment (`docs/ui/pwa-solar-survey-iphone-v3`, on iPad `docs/ui/pwa-solar-survey-ipad-v3`): the project list, the `แผนงาน` page (`PWAPlanPhoneView`: pushed on iPhone; on iPad shown under the home's own header and nav in two columns, `docs/ui/pwa-plan-ipad`, through `PWAOverviewHost.planBody`) or the `บำรุงรักษา` overview. This and the other `-surveyHome…` flags of this item work on both sizes. `-surveyHomeType all|install|maintenance` picks the filter's `ประเภทงาน`: the project list, the install overview or the maintenance overview. `-surveyHomeSearch YES` opens the header's search; `-surveyHomeFilter YES` opens the `กรองและเรียง` popover and `-surveyHomeFilter draft` sets status `ร่าง` and sort `ความคืบหน้า`. `-surveyHomeDemo install|maintenance` seeds the example stations of `docs/ui/pwa-solar-survey-iphone-v2` (12 being installed, or 6 handed over), dated from today; `-surveyHomeDemo cards` shows the second and third project cards as install-phase cards, one late and one on plan (nothing is saved). `-pwaMaintenanceFilter issue|pmSoon|all` (with `-surveyHomeTab maintenance`) picks the row filter of the `บำรุงรักษา` overview (`docs/ui/pwa-maintenance-iphone`). `-screen pwa` is the main dock with its PWA tab selected: `กปภ.` on iPhone (`PhoneTabs`), `โครงการ` on iPad (`PadTabs`), root `PWARoot` on both. `ตั้งค่าโครงการ PWA` is a row of the settings sheet opened from that tab, and `StationDocsScreen` is reached from a station's job.
- `-pwaPlanView schedule|mp|due` (iPhone, with `-screen pwa -surveyHomeTab plan`) picks the view of the `แผนงาน` page (`PWAPlanPhoneView`, `docs/ui/pwa-plan-iphone`). `-pwaPlanDemo YES` shows the board's example instead of the jobs (nothing is saved), dated from today, with the calendar's bars from the board's `monthTypesByDay`; add `-pwaPlanToday 2026-10-12` to fix "today" on the board's Monday. `-pwaPlanCalendar week|month` picks the calendar's view, `-pwaPlanDay 2026-10-15` selects a day and scrolls the day list to it, `-pwaPlanFilter open|ins-A|empty` opens `กรองตารางงาน`, or sets `ติดตั้ง` + contractor A, or a filter with no match; `-pwaPlanDueFilter open|doc` opens the `กำหนดส่ง` filter menu or picks `ยื่นเอกสาร`; `-pwaPlanSearch YES` opens the header's search. On iPad (`-surveyHomeTab plan`, best with `-screen home -homeTab pwa -homeBoard YES` for the landscape layout) the same flags work except `-pwaPlanView`, `-pwaPlanFilter` and `-pwaPlanDueFilter` (the iPad page shows all three views and no filters), and `-pwaPlanScrollEnd YES` opens the right column at its end.
- `-surveyNewJob empty|filled|details|date|time|kwp|team|install|province|search|invalid|saved` (with `-screen survey` or `-screen home -homeTab homework`) opens the iPhone add-customer sheet (`NewJobPhoneView`) in that state of `docs/ui/tcroof-new-job-iphone/states`; `saved` also saves the example customer, so it adds a job.
- `-surveySLDPanel YES` (with `-surveyPage sld`, iPhone) opens the `ข้อมูลฝั่ง PV` sheet.
- `-screen homework -homeworkSheet weight|pack|entry|archive` opens น้ำหนักบนหลังคา, ชุดไฟล์ PPIM, ข้อมูลกรอก PPIM or แฟ้มเอกสาร over งานบ้าน.
- `-surveySLDDXF YES` (with `-surveyPage sld`) writes the single line diagram's DXF to `Documents/sld.dxf`.
- `-surveySiteDXF YES` (with `-surveyPage site`) writes the A2 site plan's DXF to `Documents/site.dxf`.
- `-surveyTankDXF YES` (with `-surveyPage tank`) writes D1's DXF to `Documents/tank.dxf`, 2.5 s after opening so `-surveyD1` has seeded the tank.
- `-surveyCardImport YES` opens นำเข้ารูปจากการ์ด / USB with three generated photos (a drone shot 92 m up and two ground shots), skipping the file picker.
- `-surveyPlatePhoto YES` (with `-surveyPage electrical`) clears TX 1's nameplate fields and gives it a rendered nameplate photo, so A3 offers `พบในรูปป้าย` from the photo text reader.
- `-surveySettings YES` (with `-screen pwa`) opens the survey settings; its `เครื่องนี้` section lists the hardware the device has (`DeviceCaps`).
- `-screen home -homeDemo YES` opens the home with sample appointments; `-homeBoard YES` lays the iPad tabs out at 1366 × 1024. On iPad, `-homeTab home|survey|pwa|docs|tools|scan` opens with that tab of the dock selected (`PadTabs`, one stack per tab, `docs/ui/tcroof-home-ipad-v2`; the items are `หน้าแรก · โครงการ · งานบ้าน · เอกสาร · เครื่องมือ · สแกน | ตั้งค่า`, `docs/ui/pwa-solar-survey-ipad-v3`: `pwa` is `โครงการ`, `survey` is `งานบ้าน`, `docs` the residential document library, and the plan calendar and the install records are rows at the top of `เครื่องมือ`). On iPhone, `-homeTab home|homework|pwa|docs` opens with that tab of the floating dock selected (`งานบ้าน` is the survey list, `กปภ.` the PWA survey module, and `เอกสาร` the residential document library, `HomeLibraryView`; the tools register and the plan calendar, scan and install rows are under the settings sheet's `เครื่องมือวัด` row for now); `-homeNotifications YES` / `-homeSettings YES` open those screens.
- `-homeFeed demo` (iPhone home, and the iPad home's right column of `docs/ui/tcroof-home-ipad-v2`) seeds the project feed with the five posts of `docs/ui/tcroof-home-iphone-v3` and drawn example photos; without it the feed is built from the jobs' records (`FeedBuilder`). `-homeFeedFilter all|pwa|home|mine` picks a filter (a segment on iPhone, a chip on iPad), `-homeNoAppointments YES` leaves today without a survey appointment (on iPhone the card becomes `แผนงานถัดไป`: the next install days, IEC tests and PWA document deadlines ahead, or nothing when none are; add `-homeHeroPlan demo` for the board's three example items, dated from tomorrow), and `-homeFeedIssue fixed` opens the demo issue post already fixed and the summary acknowledged (state `05`). The demo's `รับทราบ` and `แก้แล้ว` are not kept.
- `-homeTimeline demo` (iPad home, with `-homeDemo YES`) puts the five PWA plan rows of `docs/ui/tcroof-home-ipad-v3` §1 into `วันนี้` in place of the plan's own (nothing is saved): two MP install tasks at 08:00 and 08:30, an inspection at the first survey appointment, a document deadline, and a test at the second. `-homeTimelineEnd YES` opens the card scrolled to its end.
- `-toolsDemo YES` gives the tools register (`ToolsView`, on iPhone under the settings sheet's `เครื่องมือวัด` row) three sample tools, one overdue and one due within 30 days, so the row shows its badge of 2; they are not saved. The real register is `Documents/Tools/instruments.json`, on the device only.
- `-screen home -homeTab homework` opens the iPhone survey home (`PhoneSurveyList`); `-screen survey` opens it on its own. Add `-surveyDay <0-6>` (the selected day of the week strip, 0 is today), `-surveyStatus interested|confirmed|installing|completed` (the status chip), `-surveySearch <text>`, `-surveySearchFocus YES` (seed `ค้นหาล่าสุด` with `-surveyList.recentSearches "a\nb"`) or `-surveyListDraft YES` (today's first job gets a half-done draft) for the states of `docs/ui/tcroof-survey-home-iphone`. Run `-homeDemo YES` on the home tab first to put two appointments on today.
- `-screen planlist` opens the plan list (`PlanListView`); `-screen surveyhistory`, `scanhistory` and `loghistory` the survey, scan and install-log histories.
- `-screen plan` opens the plan calendar (on iPhone it has no tab: it is the first row of `เครื่องมือวัด`, in the settings sheet); on iPhone that is `docs/ui/tcroof-plan-calendar-iphone`. Add `-planToday 2026-09-30` to fix "today" and `-planDemo YES` to move the sample jobs back to their offsets from it, with the board's survey times. Then `-planDay <yyyy-MM-dd>` selects a day (and shows its month), `-planView week` opens the week view, `-planTeam TCR01` filters a team and `-planTeamMenu YES` opens the team menu.
- `-screen job -jobKind home|pwa` opens the first job's detail as a งานบ้าน or งาน PWA job (`JobKind`): a PWA job shows the MP plan, รายงานประจำ, เอกสารสถานี กปภ. and the NO.224 card, a home job shows งานบ้าน ครบวงจร. It changes that job's kind for good.
- `-screen job -mpDemo plan|setup|new` opens the first job's detail with a sample MP plan around today (`MPScheduleCard`), also opening ตั้งค่าแผน (`setup`), or opens it on the job with its plan cleared (`new`).
- `-screen mp` opens that job's แผนงาน MP full screen (`MPScheduleScreen`), seeding the same plan when it has none; add `-mpDemo progress` to open บันทึกความก้าวหน้า, or `-mpDemo pdf` to write the weekly-meeting page to `Documents/mp.pdf`.
- `-screen routine|daily|dailies|request|weekly|monthly` seeds the first installing job with station settings, an MP plan and two weeks of signed daily reports (one day missing, today empty), then opens the รายงานประจำ card, today's daily report (`-routineDay yyyy-MM-dd` for another day; `-routineDemo sign|ack` opens its sheets, `-routineDemo pdf` writes the latest daily report to `Documents/daily.pdf` and this month's R4 to `monthly.pdf`; `-routineKeyPlan YES` stands a drawn picture in for the A2 site picture), the daily report list, next week's request, last week's R3 or this month's R4 (`docs/specs/routine-reports-swift.md`).
- `-screen stationdocs` opens เอกสารสถานี กปภ. (`StationDocsScreen`) for the first installing job: the station's papers by submission and the พค.2 check list (`TCRoofCore/StationDocs`). Add `-stationDocsDraft outage` to open ร่างหนังสือแจ้งดับไฟ (`OutageLetterSheet`, the first paper the app drafts: `StationDocs+Drafts`), or `-stationDocsDraft pdf` to write that letter with example answers to `Documents/outage.pdf`. `-stationDocsERC wait|failed|ready|parallel|done` sets the station to 200 kVA and over, writes that state of the ERC exemption flow (`TCRoofCore/ERCFlow`, `docs/specs/erc-exemption-flow-swift.md`) dated back from today and opens the `ลำดับ กกพ.` tab; it changes the job for good.
- `-screen mpall` opens แผน MP ทุกสถานี (`MPOverviewView`, also from the Plan tab's header), seeding plans on the first four jobs that have none, which also sets them to งาน PWA. Only a job set to งาน PWA is in the PWA module (`Job.kind`); `Job.keepKinds` set the older jobs with PWA data to it once per device.
- `-installOpen YES` (iPad, with `-screen home -homeTab pwa`, add `-homeBoard YES` for landscape) pushes the first installing PWA station's install tracking page (`InstallTrackingPage`, `docs/ui/install-tracking-ipad`), seeding one with an MP plan and daily reports when none is installing (that job changes for good). `-installTab overview|daily` picks its tab, `-installView gantt|curve` the progress card's view, `-installStage n` opens the nth task's sheet, `-installSheet actions|<tile id>` opens `ต้องดำเนินการ` or a `เอกสารโครงการ` tile's list (`daily`, `weekly`, `permits`, `commissioning`, `punch`, `grid`, `devices`, `handover`), `-installSite info|risk|labour` picks the site panel's tab, `-installScrollEnd YES` opens the overview at its end, `-iecOpen YES` pushes the `ทดสอบ IEC 62446` tab (`IECTestScreen`, `docs/ui/iec62446-test`): add `-iecDemo YES` to give a station with no test the แพรกหนามแดง sample, labelled `(ตัวอย่าง)` in the sheet and the export's name (for good; `-iecDemo reset` replaces the station's test with it, `-iecDemo full` with the sample filled in completely, drawn photos in every slot, so every step is done and none confirmed), `-iecClear YES` to start the station with no test (for good), `-iecStationLine <text>` to write the sheet's station line (the overview flags a line that doesn't name the job, and export asks first), `-iecSetup YES` for the set-up sheet, `-iecInverter n -iecPhase before|after` for a string table (`-iecPage performance|conditions|photos` for that inverter's ผลการผลิต or the station's conditions or photos), `-iecSlot n` to select its slot and `-iecEntry YES` to open it in กรอกทีละสตริง; `-iecCameraStub YES` puts a drawn meter photo in a photo slot instead of opening the camera (IEC photos are `PhotoAsset`s on `Job.iecPhotos`); `-installDetail YES` pushes the header's `รายละเอียดงาน` (the job's `JobDetailView`, the install page's way to the customer, schedule, scans, install logs, ICL, R4, survey link and documents), `-installSeed YES` gives the opened station the `-screen daily` reports when it has none (for good), and `-installDemo YES` shows the board's example values (nothing is saved).
- `-noNotificationPrompt YES` skips the notification permission prompt, for screenshots on a fresh install. A prompt already on screen survives a reinstall; reboot the simulator to clear it.
- `-screen components` opens `ComponentGallery` (also in Settings › นักพัฒนา in DEBUG builds); add `-gallerySection 1…9` to show one board section of `docs/ui/components`.
- `-surveyA2 layers|fullscreen|trafo|zero` opens A2's layers menu, full screen with the first placed building model selected, or the transformer / กันย้อน symbol's editor.
- `-surveyAutofill fill|conflict` (with `-surveyPage site` or `electrical`) writes `docs/ui/a2-a3-autofill`'s A2 symbols and a placeholder site picture: `fill` links them into A3 / B4, `conflict` gives A3 a 500 kVA transformer first. Add `-surveyA2Panel YES` on A3 to open the `ดึงจากภาพ A2` panel.
- Survey job data is stored at `<app data container>/Documents/SolarSurvey/Jobs/<id>/job.json`, with photos in `photos/`. It can be edited while the app is stopped to seed test data; back it up first.

## Architecture

**App target (`TCRoof/`)** handles Google sign-in (`Auth/`), SwiftData models, Firestore sync (`Sync/CloudSync.swift`) and the non-survey screens. Firestore access is limited by `firestore.rules` (Firebase project `tcroof-1564c`): only accounts with a `members/<email>` document, and only the collections the app syncs, so a newly synced collection needs a rule. It hosts the survey module via `Views/Survey/` (`SolarSurveyEntry`, `PWASurveyLink`).

**`TCRoofKit` Swift package** holds all survey work, layered as follows:
- `TCRoofUI`: all the package's UI. Its root files and `Gallery/` are the design system shared by the app and the survey module (`docs/ui/components`), and `Survey/` is the survey editor (below). `Theme` tokens (light and dark), `Space` / `Radius` / `TypeScale`, `Font.sarabun`, and `TC*` components by board section, plus the DEBUG `ComponentGallery`. The design system files import nothing from the other modules; keep it so. New screens build from these components; colours come from `Theme`, never hex literals in views. No `Color.white` either: cards and fields use `Theme.surface`, text on `Theme.primary` uses `Theme.onPrimary`, and plans and diagrams sit on `Theme.paper` (white in both modes, since their ink is dark). Buttons use `TCButtonStyle`, not `.bordered` / `.borderedProminent`: a page's `.foregroundStyle` overrides the system style's white label. The app is light only: it forces light mode for signed-in users (`TCRoofApp.swift`). `Theme` keeps its dark values, but dark mode is not shown.
- `TCRoofCore`: pure values and rules, no UI.
  - `PWAOverview.swift`: `InstallStationSummary` / `InstallOverview` and `MaintenanceStationSummary` / `MaintenanceOverview`, the iPhone survey home's `งานติดตั้ง` and `บำรุงรักษา` overviews (behind / ahead of the MP plan, kWp-weighted averages). The app fills them through `PWAOverviewHost` (`\.pwaOverview`), since MP plans and daily reports are app models.
  - `PWAPlan.swift`: the iPhone PWA `แผนงาน` page (`docs/ui/pwa-plan-iphone`): the day agenda, the kWp-weighted S-curve, the Gantt bars and the deadlines of two weeks, from `PWAPlan.Station`s the app makes from its jobs (`Job.planStation`).
  - `Models.swift`: `Job`, `SurveyModule`, `Values` / `FieldValue`, `Transformer` / `Board` / `Breaker`.
  - `Schema.swift`: every page and section as `ModuleSpec` / `GroupSpec` / `FieldSpec` with field ids.
  - `Progress.swift`: completion, section numbering (`sectionsByCategory`: B1, B1.2 …), `steps`.
  - `IECReport.swift`: a station's IEC 62446 test before and after the grid connection (`docs/specs/iec62446-excel-export-swift.md` §2): per inverter 20 string slots in Excel order, the checks, 7-day energy and test conditions, with derived kWp, Yf, PR, efficiency, the IR summary, the Voc check and progress. Stored as `Job.iecReportJSON`; `IECReport(form:)` reads the form JSON of `docs/forms/iec62446-pwa`. `IECReport+Stages` has the 7 steps of the wizard (done and missing per step, derived), their confirmations (kept with a digest of the step's values, so a later edit unconfirms), the exports, the closing result (`เสร็จ` locks the test; `Job.updateIEC` refuses edits until `แก้ไข`) and the photos' Drive names (`IEC 62446/รูปถ่าย`, uploaded with the job's documents).
  - `ProjectFeed.swift`: `FeedPost` and `FeedBuilder`, the iPhone home's project feed made from daily reports, ICL check lists and punch lists (`docs/ui/tcroof-home-iphone-v3`).
  - `SystemNotifications.swift` and `LiveNotifications.swift`: every local notification as a `NotificationPlan` (survey, sync, Drive, routine reports, calibration, install days, the MP plan, the feed's events) and the `DeepLink` a tap opens. The app's `NotificationScheduler` posts them each minute and `AppNotification` lists the same ids in the bell. They are local: a record from another device is announced once sync has brought it in, while the app runs.
  - Feature calculators: `SingleLine` (SLD), `InverterStation` (B2), `BuildingPanels` (B1), `Flood`, `SiteShapes`, `EquipmentCatalog` (bundled JSON).
  - `Sketch` / `DrawOp` vector drawing, shared by the screen and the PDF.
  - DXF R12 export: `SketchDXF` writes any `Sketch`; `RoofDXF` (C1), `SingleLineDXF` (SLD, A3 paper scale) and `TankDXF` (D1, real scale) call it. `RoofDXF` output is pinned by golden files in `Tests/TCRoofCoreTests/Fixtures`.
- `PDFReport`: `ReportLayout` turns a `Job` into pages of `DrawOp`s (`ReportLayout+*.swift` per area); `PDFRenderer` draws them. The SLD page is A3.
- `ExcelExport`: fills `Resources/template.xlsx` by cell address (`ExcelExporter`, `template_meta.json`). Section slots are fixed (`ExcelExporter.slots`); extra sections get a copied sheet. `IECExcel` fills the PWA's own IEC 62446 workbook (`Resources/iec62446_template.xlsx`, byte-identical to `docs/specs/iec62446/1FORMI1.xlsx`) in place, cell by cell, so everything else stays as the customer's file; `IECExcelTests` checks the sample gives back the original.
- `DriveSync`: Google Drive upload of report files and photos.
- `TCRoofUI/Survey`: the editor, in folders by area (`Editor`, `Home`, `Model`, `Export`, `Photos`, `Hardware`, `Review`, `Pages/<page>`). It was the `SurveyUI` module until it was merged into `TCRoofUI`; older task briefs in `docs/ui` still name `Sources/SurveyUI/<file>.swift`.
  - `SurveyModel` (job storage, photos) and `JobEditorView` (sidebar, page routing, `cardBar` bottom bar).
  - The generic schema form `groupPage` is used on iPhone and wherever a wide page doesn't apply.
  - `SurveyHomeView` is the PWA project home, one page (`homePage`) for both sizes: 16 pt margins and one column on iPhone, 63 pt margins and three columns on iPad.
  - Designed "wide" pages: `InfoPageWide` (A1), `SitePageWide` (A2), `ElectricalPageWide` (A3), `FloodPageWide` (A4), `PanelsPageWide` (B1), `InverterPageWide` (B2), `WaterPageWide` (B3), `FtsPageWide` (B5), `RoofPageWide` (C1), `TankPageWide` (D1), `FinalPageWide` (E1), `SingleLinePage`.

**Data rules every change must keep:**
- Answers live in `Values` keyed by schema field id. Existing ids, labels and Excel cells must not change.
- New fields are optional and usually hidden from the form page (`when: { _ in false }`), so section completion counts as before.
- Old job JSON must still decode: hand-written `init(from:)` with `decodeIfPresent` defaults. Wide pages write legacy fields back so Excel, PDF and `Progress` keep working (B2 writes `sizeLWH` and `inverterCount`; B1 writes `breakerAT`).
- Pages share data across sections. For example, B1's `a3Breaker` link writes A3 `Breaker.target`, the SLD reads B1 loads and B2 sizes, and B2 writes B4 `level`. Before editing, find every reader of a field: the SLD, `Progress`, the PDF, Excel and `Flood` often read the same field.

## Design specs (`docs/ui/survey-*`)

Each wide page has a `CLAUDE_CODE_TASK.md` (what to build, constraints, check list) and a `SPEC.md` (data, rules, UI, tests, open questions), plus `preview*.png` at 1366 × 1024 and an `icons/` folder.
- When asked to "follow" one, compare the result with the previews in the simulator.
- Report the spec's open questions at the end.
- Values in previews are examples; never hardcode them.

`docs/specs/` holds feature specs (auto drawing, cable route, roof PV layout, tank mounting, site logistics, calendar and travel, hardware assist, presentation mode, review lock, standard designs, IEC 62446 Excel export and more), with images in `img/` and HTML prototypes in `prototype/`. Some are built by now (review lock, routine reports, the ERC exemption flow, the master schedule, hardware assist), so check the code before treating a spec as pending.

UI conventions from the specs:
- Hit areas are at least 44 pt.
- Plans and PDF drawings are vector (`Sketch`), never bitmaps of icons.
- Icon catalogs go in `TCRoofKit/Sources/TCRoofUI/Resources/<X>Icons.xcassets` and load through `A2Icon(name:fallback:)`. Asset names are global across catalogs, so avoid duplicates (B1's clashing `ui-*` icons are prefixed `b1-`).
- Very long SwiftUI expressions fail to type-check or crash at runtime in Debug (`View.modifier` SIGSEGV). Split cards into separate computed properties.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

The server runs the `code-review-graph` binary from `.mcp.json`; install it with `uv tool install code-review-graph`. If it fails to connect, use grep and Read instead.

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".
  Uncommitted new files are often missing; fall back to grep.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->
