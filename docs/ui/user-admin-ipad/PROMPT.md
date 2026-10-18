# Prompt for Claude Code

```
git fetch origin && git switch -c feat/user-admin-ipad origin/design/user-admin-ipad
```

```
Follow docs/ui/user-admin-ipad/CLAUDE_CODE_TASK.md.

FIRST check that these exist. If any is missing, STOP and report.
- TCRoofKit/Sources/TCRoofCore/UserRoles.swift, with UserRole manager/internal/external and Capability users.manage
- TCRoof/Auth/MembersView.swift (MemberDirectory)
- firestore.rules, with match /members/{email}
- tools/firestore-rules-tests

Build ONLY the developer page จัดการผู้ใช้และสิทธิ์ and what it needs (the task's change list):
1. Maintainer role:
   - UserRole.maintainer, plus capabilities users.suspend / users.permissions / users.admin.
   - user-roles.json and RoleTableTests in step.
   - Rules: isMaintainer(); maintainer is never writable from the app.
2. Suspend (Maintainer only):
   - members/<email>.suspended / suspendedBy / suspendedAt.
   - Rules: isMember() is false while suspended.
   - Sign-in refuses a suspended account; MemberRole signs it out.
3. Developer key:
   - config/devKey with a PBKDF2 hash only, Maintainer-only rules.
   - Lock screen with a 6-digit pad, 5 tries then a 10-minute lock, 15-minute unlock with a timer, ล็อกหน้านี้.
   - The key is asked again before a role edit, an invite, or a matrix/rules edit.
4. Settings › นักพัฒนา row "จัดการผู้ใช้และสิทธิ์ · 🔒 ต้องใช้คีย์", shown only for users.admin.
5. Frame:
   - Header, the three tabs.
   - Pending-changes bar: every change waits there; บันทึกและซิงก์ writes one WriteBatch plus audit entries.
6. ผู้ใช้ tab:
   - Role filter segments, then search, then "+ เพิ่มผู้ใช้"; the list; the detail panel.
   - Detail panel:
     - "🔒 แก้ไขบทบาท" at the head's top right, which becomes เสร็จ
     - role diff box
     - permission groups
     - suspend button
   - Invite sheet (email check, role, team, jobs for external).
7. บทบาทและสิทธิ์ tab:
   - Matrix from the role table; edit after the key, cells cycle.
   - Overrides in config/roleOverrides, applied by Permissions.
   - Cells that firestore.rules enforces are locked ("บังคับใน rules").
   - กฎการใช้งาน and ข้อตกลง.
8. ประวัติการแก้ไข tab from a new append-only auditLog collection.
9. DEBUG flags (task §9), one line in CLAUDE.md, and UserAdminUITests.

Rules:
- Only data with a source. Hide last seen / device / ออกจากระบบทุกเครื่อง / the 30-day idle rule unless you add a
  source (say which), and report them.
- The key is a UI gate; the rules decide. Never store the digits, never hardcode the board's key outside
  -userAdminDemo.
- Every rules change gets rules tests. Don't change MembersView, the sign-in UI or existing capabilities' meaning.
- Theme tokens only, TCButtonStyle, 44 pt hit areas.
- Split big views into computed properties (CLAUDE.md, the Debug SIGSEGV).

Steps:
1. Read the task, then iPadUsers.dc.html as text: renderVals(), GROUPS, RU, U0. Look at states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test, the rules tests (npm test),
   UserAdminUITests and RoleUITests.
4. iPad Pro 13" simulator, run with -screen useradmin -userAdminDemo YES and the new flags.
   Save screenshots 00–12 in docs/ui/user-admin-ipad/screenshots/ and compare them with states/.
5. Commit on feat/user-admin-ipad and push it (no merge).
6. Report:
   - the differences
   - what had no data source and was hidden
   - whether AppCompat.syncVersion was raised
   - the open questions
```
