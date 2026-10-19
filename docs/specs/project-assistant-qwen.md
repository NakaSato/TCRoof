# ผู้ช่วยโครงการ (Project Assistant) on Qwen

**Status:** phases 1–2 built 2026-10-19 (the `assistant` Cloud Function in `functions/`, not deployed yet; the core in
`TCRoofKit/Sources/TCRoofCore/Assistant/`, tested by `AssistantTests`; the `assistant.use` capability). Phase 3 (the
app's client and chat screen) is next.
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
- Parameters: `QWEN_MODEL` (default `qwen-plus`), `QWEN_BASE_URL` (default `https://maas.qwencloudapi.com/compatible-mode/v1`),
  `ASSISTANT_DAILY_LIMIT` (50); secret `QWEN_API_KEY`.
- `npm test` builds and runs the guard tests; `tools/firestore-rules-tests` checks no client touches `assistantUsage`.

### Deploy (once)

1. The Firebase project `tcroof-1564c` must be on the Blaze plan; set a budget alert.
2. `cd functions && npm install`
3. `firebase functions:secrets:set QWEN_API_KEY`
4. `npm run deploy` (asks for the parameters, or put them in `functions/.env.tcroof-1564c`).

## 4. Phase 3: the app (next)

- `AssistantClient` (`Assistant.Transport`) through `FirebaseFunctions` (add the product to the app target),
  `httpsCallable("assistant")` in `asia-southeast1`; errors in Thai (`resource-exhausted`: the day's limit).
- Jobs → `Assistant.Job`: only jobs with an MP plan, `canEdit = permissions.can(.mpProgress, on: job.access)`.
- `AssistantChatView` from TC components: opened from the install tracking page header (focus on that station),
  แผน MP ทุกสถานี and `MPScheduleScreen`; prompt chips `สถานีไหนช้ากว่าแผน`, `ต้องเร่งงานอะไรสัปดาห์นี้`,
  `ร่างสรุปประชุมประจำสัปดาห์`, `อัปเดตความก้าวหน้าจากรายงานประจำวัน`; proposal cards with ยืนยัน / ยกเลิก, shown
  only with `assistant.use`.
- `ยืนยัน` saves through the same path as บันทึกความก้าวหน้า (so sync, the plan file and the Gantt follow).
- DEBUG `-screen assistant -assistantDemo YES` with a stub transport, and `AssistantUITests`.

## 5. Open questions

1. Which model ids the Qwen account offers on that endpoint; try Thai answers on two before picking (`QWEN_MODEL`).
2. Is the Firebase project on Blaze?
3. Should progress confirmed through the assistant be marked (who confirmed, `ผ่านผู้ช่วย`) in an audit trail?
   `MasterSchedule.Actual` has no author field today.
4. Is 50 requests per person per day right?
5. App Check is not enforced (the app has no App Check yet); the member check is the gate.
