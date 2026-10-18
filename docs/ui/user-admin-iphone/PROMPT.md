# Prompt for Claude Code

```
git fetch origin && git switch -c feat/user-admin-iphone origin/design/user-admin-iphone
```

```
Follow docs/ui/user-admin-iphone/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoof/Auth/UserAdmin/UserAdminView.swift and UserAdminUsers.swift (the iPad page from PR #61)
- TCRoofKit/Sources/TCRoofCore/UserRoles.swift, with Capability daily.fill and iec.fill_submit
- TCRoofKit/Sources/TCRoofCore/RoutineReport.swift, with WeeklyRequest
- TCRoof/Views/Job/RoutineReports/WeeklyRequestScreen.swift
- firestore.rules, with match /jobs/{doc} (external may change only iecReport / iecState)

Build ONLY these two things (the task's change list):
A. Contractor duties (iPad and iPhone):
   1. New capability weekly.request:
      - manager allow, internal conditional "อนุมัติ / ส่งกลับ", external conditional
        "ต้องส่งทุกสัปดาห์ · งานตัวเอง"
      - put it after daily.fill
      - keep user-roles.json, UserRoles.swift and RoleTableTests the same
   2. New external notes on daily.fill and iec.fill_submit (access unchanged).
   3. Contractors fill and send next week's request:
      - WeeklyRequest.sentAt / sentBy (decodeIfPresent)
      - team approves or sends back; sent = read only for the contractor
      - rules: external may change weeklyRequests on their own job, with rules tests
      - team devices drop a contractor's change to a sent or approved week
   4. Duty card "หน้าที่ต้องส่ง · ผู้รับเหมา" in an external member's detail:
      - three rows
      - each pill reads ต้องส่ง or ปิดอยู่, from the effective external cell
   5. The decisions line.
B. iPhone (compact) layout of UserAdminView, per PhoneUsers.dc.html. iPad stays as it is.
   - lock
   - header with lock button
   - segmented tabs
   - list with role chips
   - pushed detail
   - invite and key sheets
   - one-role-at-a-time matrix
   - rules and decisions
   - log
   - two-line pending bar

Rules:
- Only data with a source: keep last seen, device, ออกจากระบบทุกเครื่อง and the 30-day rule hidden, as on iPad.
- The key is a UI gate; firestore.rules decides.
- Every rules change gets rules tests. Don't change existing capabilities' meaning for manager or internal.
- Theme tokens only, TCButtonStyle, 44 pt hit areas.
- Split big views into computed properties (the Debug SIGSEGV in CLAUDE.md).

Steps:
1. Read the task, then the two boards as text (renderVals(), GROUPS, the part after "// ── iPhone:").
   Look at states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run:
   - swift test
   - the rules tests (npm test)
   - UserAdminUITests (with the new iPhone test)
   - RoleUITests
4. Screenshots:
   - iPhone 16 simulator, -screen useradmin -userAdminDemo YES and the flags: save 00–09 in
     docs/ui/user-admin-iphone/screenshots/ and compare them with states/.
   - iPad: 10–11, and check nothing else changed.
5. Commit on feat/user-admin-iphone and push it (no merge).
6. Report:
   - the differences
   - what had no data source and was hidden
   - whether AppCompat.syncVersion was raised
   - the open questions
```
