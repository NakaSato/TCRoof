# ผู้ช่วยโครงการ (Project Assistant) on Qwen

**Status:** built 2026-10-19: the `assistant` Cloud Function in `functions/` (not deployed yet), the core in
`TCRoofKit/Sources/TCRoofCore/Assistant/` (`AssistantTests`), the `assistant.use` capability, and the app's chat in
`TCRoof/Assistant/` (`AssistantUITests` on the demo stand-in). It calls the function over HTTPS with the account's ID
token (`AssistantClient`), so the app needs no FirebaseFunctions SDK.
**Goal:** a chat assistant that helps the team keep each PWA station's MP plan on schedule: which stations and tasks
are behind, what pace each task needs, and booking progress, actual dates and late causes from the conversation.

---

## 1. Shape

```
App (team / manager / Maintainer; assistant.use)
  ├─ Assistant.Session: the conversation, kept on the device
  ├─ Assistant.Toolbox: runs the model's tool calls on the device's jobs
  │     read: list_stations, get_schedule, get_week_tasks
  │     propose: propose_progress, propose_dates, propose_late_cause → PendingAction (nothing saved)
  └─ Transport → Firebase callable `assistant` (asia-southeast1)
                   ├─ members/<email>: not external, not suspended
                   ├─ assistantUsage/<email>_<Bangkok day>: at most ASSISTANT_DAILY_LIMIT (50) a day
                   ├─ checks every message and tool against functions/src/allowed-tools.json
                   └─ POST {QWEN_BASE_URL}/chat/completions with QWEN_API_KEY (Secret Manager)
```

- **The key never reaches a device.** The function holds it; Firestore rules deny `assistantUsage` to every client.
- **Tools run on the device.** The MP plan logic is Swift (`MasterSchedule`) and the data is the device's SwiftData,
  so the function only relays.
- **The model never does the arithmetic.** `MasterSchedule.recovery` and `ScheduleBrief` work out every percent,
  points per week, pace and projected finish; the system prompt tells the model to quote only tool results.
- **Nothing is saved without a tap.** `propose_*` tools return a `PendingAction`; the app shows it as a card (before →
  after) and on ยืนยัน calls `PendingAction.apply` on the job's current `MasterSchedule.Actual`, then
  `Session.resolve(id, confirmed:)` tells the model.
- **No customer data.** `Assistant.Job` carries the station name, MP number, kWp, the plan, progress and daily reports;
  never the customer's name, phone or address.

## 2. Core (`TCRoofCore/Assistant/`)

| File | What |
|---|---|
| `ScheduleRecovery.swift` | `MasterSchedule.recovery(plan:actual:today:)`: per task with weight, points done and left, weeks left, needed points per week, pace so far, projected finish (the Saturday of the week it ends at that pace), slip days, and a state (`done`, `upcoming`, `onTrack`, `atRisk`, `overdue`) |
| `ScheduleBrief.swift` | One station as JSON for the model: plan vs actual, per part, per task with its recovery numbers and late cause, this and the next two weeks' tasks, the projected station finish, and the last 14 days of daily reports (crew, rain hours, stop reason, progress lines, open problems) |
| `AssistantChat.swift` | The OpenAI-compatible messages, `Request` / `Reply`, the `Transport` protocol, `JSONValue` |
| `AssistantTools.swift` | `Assistant.Job`, `PendingAction`, `Toolbox` (the six tools, their JSON schemas and checks: a job found by id, MP number or name; a task by code; no booking ahead of this week; actual dates not after today; `canEdit` from `mp.progress`) |
| `AssistantSession.swift` | The loop: up to 5 tool rounds per message, a newer proposal for the same task and kind replaces the older, history trimmed to 30 messages and 60,000 characters at a person's message; the Thai system prompt |

## 3. Server (`functions/`)

- `src/guard.ts` (pure, `src/guard.test.ts`): `checkMember`, `checkRequest` (rebuilds the conversation from known fields,
  40 messages and 80,000 characters at most, system only first, tools only from `allowed-tools.json`, the last
  message not the model's), `cleanReply` (drops fields such as reasoning text; a call to an unknown tool becomes words).
- `src/index.ts`: the callable. Counts the request before calling Qwen (a failed call still counts), stores token
  counts only, never the text. `temperature` 0.2, `max_tokens` 1,500, 80 s timeout.
- Parameters: `QWEN_MODEL` (default `qwen3.8-max`, on Model Studio's free quota only: "Free quota only" on in the console, so calls are refused, never billed, once it is used up), `QWEN_BASE_URL` (default `https://maas.qwencloudapi.com/compatible-mode/v1`),
  `ASSISTANT_DAILY_LIMIT` (50); secret `QWEN_API_KEY`.
- `npm test` builds and runs the guard tests; `tools/firestore-rules-tests` checks no client touches `assistantUsage`.

### Deploy (once)

1. The Firebase project `tcroof-1564c` must be on the Blaze plan; set a budget alert.
2. `cd functions && npm install`
3. `firebase functions:secrets:set QWEN_API_KEY`
4. `npm run deploy` (asks for the parameters, or put them in `functions/.env.tcroof-1564c`).

## 4. The app (built)

- `AssistantClient` (`Assistant.Transport`) through `FirebaseFunctions` (add the product to the app target),
  `httpsCallable("assistant")` in `asia-southeast1`; errors in Thai (`resource-exhausted`: the day's limit).
- Jobs → `Assistant.Job`: only jobs with an MP plan, `canEdit = permissions.can(.mpProgress, on: job.access)`.
- `AssistantChatView` from TC components: opened from the install tracking page header (focus on that station),
  แผน MP ทุกสถานี and `MPScheduleScreen`; prompt chips `สถานีไหนช้ากว่าแผน`, `ต้องเร่งงานอะไรสัปดาห์นี้`,
  `ร่างสรุปประชุมประจำสัปดาห์`, `อัปเดตความก้าวหน้าจากรายงานประจำวัน`; proposal cards with ยืนยัน / ยกเลิก, shown
  only with `assistant.use`.
- `ยืนยัน` saves through the same path as บันทึกความก้าวหน้า (so sync, the plan file and the Gantt follow).
- DEBUG `-screen assistant -assistantDemo YES` with a stub transport, and `AssistantUITests`.

## 6. Strategy (`AssistantStrategy.swift`, `AssistantStrategyTests`)

Swift works out every figure; the model compares, explains and recommends. For the station's handover the model
quotes `handoverForecast` / `handoverSlipDays`, the install tracking page's `คาดส่งมอบ` (the period stretched by the
SPI), so the chat and the page agree. The scenarios and the re-plan share one task-by-task forecast
(`Strategy.forecast`), in whole days, in the plan's order of work (a late task pushes the tasks after it). All of them assume a task's pace scales
with its crew and working days, and a task with no progress yet runs at the plan's rate; the results say so.

| Tool | What it gives |
|---|---|
| `what_if` | Each open task's finish at today's pace, and with `crew_change`, `extra_days` or `start_now` tasks; the pace, crew or working days needed for every task to end on time, and the bottleneck task. Crew is the 14-day average of the daily reports. |
| `station_priorities` | Stations by risk (days late × kWp / 100 + points behind), each crew group's (subcontractor, else team) stations and needed crew for four weeks with the overloaded weeks, and spare crew of stations ahead offered to the riskiest of the same group. |
| `look_ahead` | 1–6 weeks: each week's tasks, the predecessors not yet done (`Strategy.predecessors`), inspections and paper deadlines; overdue tasks; 14 days of rain and stops; open problems. |
| `suggest_replan` | A plan from today: a task under way ends when its pace finishes it (never earlier), a task not started moves by as much as its predecessors' ends moved (keeping the plan's overlaps), finished tasks stay. |
| `propose_replan` | A card (`mp.setup` only) with the new dates; `ยืนยัน` turns the plan's dates into fixed ones (as an imported plan's), moves the tasks and fits the install window. Progress is untouched. |

## 7. The key on the device (no Blaze plan)

The project is on the Spark plan, which can't host functions or Secret Manager, so the app can also call Qwen
directly (`AssistantRouter`: the key on this device, else the function).

- A manager enters the key in ตั้งค่า › ผู้ช่วยโครงการ (AI) (`AssistantSettingsPage`), with the model and endpoint
  (https only), and `ทดสอบ` sends one short request. The team sees whether the device has a key and today's use.
- `AssistantKey`: Keychain, `AfterFirstUnlockThisDeviceOnly` (not synced, not in backups); model and endpoint in
  defaults; 50 requests a day per device (`Assistant.OpenAI.dailyLimit`), counted before each call.
- `Assistant.OpenAI` builds the request and checks the reply as `functions/src/guard.ts` does (only the app's tools;
  an unknown tool call becomes words); `AssistantOpenAITests`.
- Trade-off: a key on a device can be extracted by someone with that device and tools, and the limit is per device,
  not per person. Use a key with a spending cap in the Qwen console, and rotate it if a device is lost. Moving to
  the Cloud Function later only needs the Blaze plan and the deploy; a device without a key then uses it.

## 5. Open questions

1. Which model ids the Qwen account offers on that endpoint; try Thai answers on two before picking (`QWEN_MODEL`).
2. Is the Firebase project on Blaze?
3. ~~Should progress confirmed through the assistant be marked in an audit trail?~~ Yes (19/10/2569): each confirmed
   card adds a line to `MasterSchedule.Actual.confirmations` (task, the confirmer's email, time, the card's before and
   after); the progress sheet and the install page's task sheet show the latest as `ผ่านผู้ช่วย · 60% · name · date`.
   Changes typed in by hand are not listed.
4. ~~Is 50 requests per person per day right?~~ Yes, kept at 50 (19/10/2569).
5. App Check is not enforced (the app has no App Check yet); the member check is the gate.
6. ~~Should the original baseline be kept for reports?~~ Yes (19/10/2569): the first confirmed re-plan keeps the plan
   it replaces in `MasterSchedule.Input.baseline` (later re-plans keep that first one; an imported workbook starts
   without one). Planned % stays against the new plan; the MP screen and its PDF add `แผนเดิม x%` and a thin grey bar
   per moved task, and the assistant's brief has `originalInstallEnd` / `originalPlannedPercent`.
