# Claude Code task: iPad `จัดการผู้ใช้และสิทธิ์` (developer page, behind a key), board 18 ต.ค. 2569

> **How to use:** open Claude Code in the `TCRoof` repo and paste `PROMPT.md`, or type
> `Follow docs/ui/user-admin-ipad/CLAUDE_CODE_TASK.md`

- **Board:** `iPad · จัดการผู้ใช้และสิทธิ์ (นักพัฒนา · ต้องใช้คีย์)` (`iPadUsers.dc.html`, 1366 × 1024 pt, landscape). Its entry row is on `iPadSettings.dc.html`.
- Thai strings in `backticks` are literal UI labels.
- **Everything in the previews is example data:** names, emails, devices, times, jobs, counts. The example key `246810` is only the board's. Never hardcode any of it.

## What exists

- **Roles:**
  - `TCRoofCore/UserRoles.swift` (`UserRole` manager / internal / external, `Capability`, the role table, `Permissions`)
  - `docs/reference/roles/user-roles.json`
  - `RoleTableTests` keeps the two the same
- **Members:** `TCRoof/Auth/MembersView.swift` (`MemberDirectory`, Settings › `สมาชิกทีม`): a manager (`users.manage`) invites an email with a role, changes a role, removes someone.
  - `TCRoof/Auth/TeamDirectory.swift` (`directory/<email>`: names).
  - `MemberRole` reads `members/<email>.role`; `GoogleSession.signIn` refuses accounts without a member document.
- **Rules:** `firestore.rules` (`members/{email}`: a manager creates, updates `role`, deletes; never their own document). Tests: `tools/firestore-rules-tests`.
- **Settings:** the settings sheet (`TCRoof/Views/Home/PhoneSettings.swift`, used on both sizes) has a `นักพัฒนา` section.

**Decided with the owner (keep):**
- There is a 4th role, **Maintainer**, who can do everything; the board's example is the app's developer.
- **Only a Maintainer may suspend or reactivate an account.** A manager still invites and sets roles, but cannot suspend.
- A Maintainer can't be made or changed from the app (Firebase console only), and nobody suspends a Maintainer or themselves.

## Scope

- **In scope:**
  - the new page, iPad regular width (on iPhone, push the same view; no iPhone layout work)
  - its Settings entry
  - the Maintainer role
  - suspend
  - the developer key
  - role and permission overrides
  - the audit log
  - the rules and their tests
- **Do not touch:**
  - `MembersView` (managers keep `สมาชิกทีม` as it is)
  - sign-in UI
  - existing capabilities' meaning
  - job data
  - any screen outside Settings
- **Data rule:** show only what has a source.
  - Elements with no source (see "No source") are hidden and listed in the report.
  - `-userAdminDemo YES` may show the board's example, for screenshots only, and writes nothing.

**Before editing:**
- Use code-review-graph (per `CLAUDE.md`), else grep.
- Read `UserRoles.swift`, `user-roles.json`, `RoleTableTests`, `MembersView.swift`, `MemberRole.swift`, `GoogleSession.swift`, `TeamDirectory.swift`, `firestore.rules`, `tools/firestore-rules-tests/rules.test.js` and `AppCompat`.

## Files in this folder

| File | Shows |
|---|---|
| `states/00-settings-entry.png` | Settings sheet: `นักพัฒนา` › `จัดการผู้ใช้และสิทธิ์` with `🔒 ต้องใช้คีย์` |
| `states/01-lock.png` | Lock screen: 6-digit key pad |
| `states/02-lock-wrong-key.png` | Wrong key: shake, `คีย์ไม่ถูกต้อง · เหลือ n ครั้ง` |
| `states/03-users.png` | `ผู้ใช้` tab: role filter, search, `+ เพิ่มผู้ใช้`, list, detail panel (= `preview.png`) |
| `states/04-role-key-confirm.png` | `🔒 แก้ไขบทบาท` asks for the key again |
| `states/05-role-edit.png` | Role edit mode: 3-segment role, diff box (`ได้เพิ่ม n · เสีย n`), `เสร็จ`, pending bar |
| `states/06-invite.png` | `เพิ่มผู้ใช้ด้วยอีเมล` sheet: email check, name, role, team, jobs (external), note |
| `states/07-invite-added-pending.png` | The invited row (`รอเข้าระบบ`) and the pending bar |
| `states/08-suspended-pending.png` | `ปิดบัญชี · Maintainer` pressed: status `ระงับ`, button `เปิดใช้งานอีกครั้ง`, pending bar |
| `states/09-maintainer.png` | The Maintainer's own row: purple card, no role edit, `ปิดบัญชีไม่ได้` |
| `states/10-roles.png` | `บทบาทและสิทธิ์`: matrix (3 roles × 35 capabilities) and `กฎการใช้งาน` |
| `states/11-roles-edit.png` | Matrix edit mode after the key: a changed cell outlined, `แสดงเฉพาะที่แก้ (n)`, pending bar |
| `states/12-log.png` | `ประวัติการแก้ไข`: audit list with kind tags |
| `iPadUsers.dc.html`, `iPadSettings.dc.html`, `grf.css` | Design source. Read them as text: `renderVals()` holds every size, colour and rule (`GROUPS` = the matrix, `RU` = the rules list, `U0` = example users) |
| `screenshots/` | Empty: put your simulator screenshots here |

## Change list

### 1. Maintainer role (`TCRoofCore`, JSON, rules)

- **Role:** add `UserRole.maintainer = "maintainer"` (`Maintainer`, `ทำได้ทุกอย่าง`).
  - It is allowed every capability except those `disabled` for all roles (BOQ).
  - Decode: an unknown or absent role stays `internal`, as today.
- **New capabilities:**
  - `users.suspend`: Maintainer only.
  - `users.permissions`: edit the matrix and rules, Maintainer only.
  - `users.admin`: open this page, Maintainer only.
- **Sync:** add the role and capabilities to `user-roles.json`, and keep `RoleTableTests` passing (update it to 4 roles).
- **`firestore.rules`:**
  - `isMaintainer()`; `isManager()` is also true for a Maintainer.
  - **Role values:** only `manager | internal | external` can be written by a manager. `maintainer` is never writable from the app, and a Maintainer's document can't be updated or deleted by anyone but the console.
  - **Tests:** add rules tests for each of these.
- **Version gate:** if older builds would misread the new role, raise `AppCompat.syncVersion` and say so in the report. Do not set `config/app.minSyncVersion`.

### 2. Suspend (Maintainer only)

- **Fields on `members/<email>`:** `suspended: true`, `suspendedBy`, `suspendedAt`. Reactivate removes them.
- **Rules:**
  - Only a Maintainer writes those keys.
  - `isMember()` is false while `suspended == true`.
  - Nobody suspends themselves or a Maintainer.
  - Add tests.
- **App:**
  - `GoogleSession.signIn` refuses a suspended account with `บัญชีนี้ถูกระงับ · ติดต่อผู้ดูแลระบบ`.
  - `MemberRole` treats suspension like removal (sign out at the next sync).
- **Page:**
  - The detail panel's red `ปิดบัญชี · Maintainer` / `เปิดใช้งานอีกครั้ง · Maintainer`.
  - For a Maintainer row: grey `ปิดบัญชีไม่ได้`.
  - On your own row: the toast `ปิดบัญชีของตัวเองไม่ได้`.

### 3. Developer key

- **Storage:** `config/devKey` holds `{ hash, salt, iterations, expiresAt, setBy, setAt }`.
  - The hash is PBKDF2-SHA256 of the 6 digits (CryptoKit / CommonCrypto). Never store the digits.
  - Rules: only a Maintainer reads or writes `config/devKey` (today `config/*` is read-only for members). Add tests.
- **Lock screen** (`states/01`, `02`):
  - Full-page navy gradient, lock icon, `จัดการผู้ใช้และสิทธิ์`, `เฉพาะนักพัฒนา · ใส่คีย์นักพัฒนา 6 หลักเพื่อเปิดหน้านี้`.
  - 6 dots and a 3 × 4 pad (84 pt keys; `ล้าง`, `0`, `⌫`).
  - **Wrong key:** shake and `คีย์ไม่ถูกต้อง · เหลือ n ครั้ง`.
  - **After 5 wrong keys:** `ล็อก 10 นาที · ติดต่อผู้ดูแลระบบ`, with the pad disabled (counter kept on the device).
  - **Footer:** `คีย์ออกให้โดยผู้ดูแลระบบ · เปลี่ยนทุก 30 วัน · ปลดล็อกได้ครั้งละ 15 นาที`.
- **Unlock:**
  - Lasts 15 minutes. The header's pill shows `ปลดล็อกเหลือ mm:ss นาที`.
  - `ล็อกหน้านี้` locks at once, as does leaving the page or the app going to the background.
  - Locking also ends both edit modes.
- **Re-confirm** (`states/04`): a smaller key sheet `ยืนยันคีย์เพื่อ…` before:
  - editing a role
  - adding a user
  - editing the matrix or rules
- **Expired or missing key:** when the key is expired, show `คีย์หมดอายุ · ตั้งคีย์ใหม่ใน Firebase console`. When no key exists, show the same kind of message. See open question 2.
- **The key is a UI gate on top of the role; the rules decide.** The page only exists for `users.admin`.

### 4. Entry (`states/00`)

- In the settings sheet's `นักพัฒนา` section, add a row `จัดการผู้ใช้และสิทธิ์` with the trailing `🔒 ต้องใช้คีย์` and a chevron.
- The row is shown only when `permissions.can(.usersAdmin)`.
- It pushes the page; on iPad, full screen as on the board, with the dock hidden.

### 5. Frame (`states/03`)

- **Header:** blue, with `‹` back, title `จัดการผู้ใช้และสิทธิ์`, subtitle `โหมดนักพัฒนา · n บทบาท · members/<email>.role`, the unlock pill, and `ล็อกหน้านี้`.
- **Tabs:** `ผู้ใช้ n` · `บทบาทและสิทธิ์ n` · `ประวัติการแก้ไข n` (560 pt), plus the sync line `ซิงก์ล่าสุด …` at the right.
- **Pending bar** (`states/05`, `07`, `08`, `11`): a dark capsule above the bottom.
  - Text: `แก้ไข n รายการ · ยังไม่บันทึก` / `บันทึกแล้วจะซิงก์ members/<email>.role ให้ทุกเครื่อง`.
  - Buttons: `ยกเลิกทั้งหมด` and the yellow `บันทึกและซิงก์`.
  - **Every change on the page waits in this bar.** Save writes them all in one Firestore `WriteBatch`, plus one audit entry each (§9).
  - Leaving with unsaved changes asks first.

### 6. `ผู้ใช้` tab (`states/03`, `05`–`09`)

- **List (left):**
  - **Toolbar:** role filter segments `ทั้งหมด n · Maintainer n · ผู้จัดการ n · ทีมภายใน n · ภายนอก n` on the left, then a search field (name, email, team), then `+ เพิ่มผู้ใช้`.
  - **Rows:**
    - avatar (initials, colour by index) with a status dot
    - name with `(คุณ)` on your own row, email
    - role pill and team or contractor (with `· n งาน` / `ไม่มีงาน` for external, from `Job.externals`)
    - status
  - **Selected row:** tint plus a 3 pt left bar.
- **Detail (440 pt, right):**
  - **Head:** avatar 52, name, email, status line. At its top right, `🔒 แก้ไขบทบาท`, which becomes `เสร็จ` in edit mode. There is no edit button on a Maintainer.
  - **`บทบาท`:**
    - Read-only: a pill and `<English> · แก้ได้หลังยืนยันคีย์`.
    - Edit mode: the 3-segment control `ผู้จัดการ / ทีมภายใน / ภายนอก` (`states/05`) plus a yellow diff box. The box reads `<from> → <to> · ได้เพิ่ม n · เสีย n`, shows up to 4 `+` / `−` chips, and has `ยกเลิกการเปลี่ยนบทบาท`.
    - You can't change your own role (toast).
  - **Maintainer:** the purple card `Maintainer · ทำได้ทุกอย่าง` and its line (`states/09`).
  - **`งานที่ได้รับมอบหมาย` / `ขอบเขต`:** chips. External shows its jobs, or `ยังไม่มีงาน · มอบหมายจากหน้างาน`; the team shows `ทุกโครงการ`.
  - **`สิทธิ์` summary:** `ทำได้ n · มีเงื่อนไข n · ดู n · ไม่ได้ n` and a 4-colour bar.
  - **Groups:** collapsible permission groups (the first open), each with counts and rows ✓ / `!` / `ดู` / ✕ plus the condition note.
  - **Footer:** `ออกจากระบบทุกเครื่อง` (see "No source") and the suspend button (§2).
- **Invite** (`states/06`, `07`): `+ เพิ่มผู้ใช้` first confirms the key, then opens the 560 pt sheet `เพิ่มผู้ใช้ด้วยอีเมล`.
  - **Email:** checked with `MemberDirectory.validEmail` and against duplicates, with the green or red line below. The company domain suggests `ทีมภายใน`, others `ภายนอก`; the company domain comes from the signed-in account's domain.
  - **Name:** optional.
  - **Role:** the 3-segment control with the permission count line, and `Maintainer ตั้งจากหน้านี้ไม่ได้`.
  - **Team:** chips.
  - **`งานที่มอบหมาย`:** external only; it writes `Job.externals` on save.
  - **Note:** `สถานะ รอเข้าระบบ … คำเชิญส่งเมื่อกด บันทึกและซิงก์`.
  - `เพิ่มในรายชื่อ` adds a pending row and selects it. On save, send the invite as `MembersView` does (share sheet, `config/app.installLink`).

### 7. `บทบาทและสิทธิ์` tab (`states/10`, `11`)

- **Matrix card:**
  - **Rows and columns:** `สิทธิ์ n รายการ`, groups of capabilities (from `Capability` and the table), one column per role with the people count. The Maintainer is not a column.
  - **Cells:** `✓ ทำได้` / `มีเงื่อนไข` + note / `ดูอย่างเดียว` / ✕ / striped `ปิดใช้งาน`, plus a legend.
  - **Buttons:** `แก้ไขสิทธิ์และกฎ` (asks the key; then `กำลังแก้ไข · เสร็จ`) and `แสดงเฉพาะที่แก้ (n)`.
  - **Edit mode:** a tap cycles `allow → conditional → view → deny`; a changed cell gets an outline.
  - **Locked cells** (toast, no change):
    - `disabled`
    - `users.suspend` / `users.permissions` / `users.admin`
    - a manager's `users.manage`
    - **every capability that `firestore.rules` enforces** (list them in code, e.g. `job.delete`, `users.manage`, `daily.sign`, `iec.close`, `stationdocs.drafts` …), marked `บังคับใน rules` (see open question 3)
- **Overrides:** stored in `config/roleOverrides` (`{ "<role>|<capability>": "<access>" }`).
  - Writable by a Maintainer only, readable by members; add rules and tests.
  - `Permissions` applies them over the built-in table.
  - Add `UserRolesTests` cases: an override changes the result, and a locked capability ignores one.
- **`กฎการใช้งาน`** (right column): a toggle list. The rows that are facts of the system are locked on:
  - `ปิด / ระงับบัญชีได้เฉพาะ Maintainer`
  - `เข้าได้เฉพาะอีเมลในรายชื่อสมาชิก`
  - `คนภายนอกเห็นเฉพาะงานที่ได้รับมอบหมาย`
  - `iPad ใช้ร่วมกันต้องล็อกอินแยกคน`
- **Decisions box:** the static `ข้อตกลง` list, taken from the board's `v.dec`.

### 8. `ประวัติการแก้ไข` tab (`states/12`)

- **Rows:** time, avatar, title, detail, and a kind tag: `บทบาท` / `สิทธิ์` / `ผู้ใช้` / `คีย์` / `ปิดบัญชี`.
- **Source:** a new collection `auditLog/{id}` with `{ at, by, kind, title, detail }`.
  - Created only by a manager or Maintainer, with `by == self`. Read by a Maintainer. Never updated or deleted.
  - Add rules and tests.
- Written for every saved change of §5.

### 9. DEBUG flags and test

- **Flags:**
  - `-screen useradmin` opens the page.
  - `-userAdminDemo YES`: the board's example users, with nothing written; the key `246810` works only in this demo.
  - `-userAdminUnlocked YES`
  - `-userAdminTab users|roles|log`
  - `-userAdminUser <email>`
  - `-userAdminSheet invite|key`
  - `-userAdminEdit role|matrix`
  - `-userAdminWrongKey n`
- Add one line for them in `CLAUDE.md`.
- **`UserAdminUITests`** (iPad, demo):
  - [ ] A wrong key shows the count.
  - [ ] The right key opens the page.
  - [ ] `🔒 แก้ไขบทบาท` asks again, and a role change shows the diff and the pending bar.
  - [ ] `ยกเลิกทั้งหมด` clears it.
  - [ ] The invite button stays off for a bad email.
  - [ ] Suspend on a non-Maintainer shows `ระงับ`.
  - [ ] A matrix cell changes only in edit mode.
  - [ ] `ล็อกหน้านี้` returns to the pad.
  - [ ] With `-role manager` the Settings row is hidden.

## No source (hide and report, unless you find one)

- **`last seen` and the device** (`ออนไลน์`, `5 นาทีที่แล้ว`, `iPad Pro`, `2 เครื่อง`): no field records them.
  - Hide them, or add optional `lastSeenAt` / `device` written by each member to their own document at sync start (needs a rule); say which you did.
- **`รอเข้าระบบ`:** only with that field (no `lastSeenAt` = never signed in).
- **`ออกจากระบบทุกเครื่อง`:** there is no remote sign-out. Hide it.
- **The `กฎการใช้งาน` row `ปิดบัญชีเมื่อไม่ใช้งาน 30 วัน`:** there is no mechanism. Hide it.

## Check

- [ ] `swift test` (roles, overrides, key hash) and `tools/firestore-rules-tests` (`npm test`).
- [ ] Build with your own `-derivedDataPath`.
- [ ] Run `UserAdminUITests`, `RoleUITests` and the members flow (`-screen members -membersDemo YES`).
- [ ] iPad Pro 13", `-screen useradmin -userAdminDemo YES` plus the flags:
  - Save `screenshots/00`–`12` with the names of `states/`.
  - Compare them with the states.

## Open questions (report)

1. Is a 4th stored role `maintainer` right, or should the Maintainer be a list of emails in `config` (no role value)?
2. How is the first key set, and rotated every 30 days? Options: from the Firebase console with a small script, or a `ตั้งคีย์ใหม่` sheet on this page (not designed yet).
3. Matrix overrides can't change what `firestore.rules` enforces. Is locking those cells enough, or should overrides be read-only until the rules read `config/roleOverrides` too?
4. Should last seen / device be recorded (§ "No source")?
