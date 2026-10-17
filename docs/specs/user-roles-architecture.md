# User Roles & Access Architecture (Swift & Firestore Spec)

**Status:** Built, integrated, and verified (`TCRoofCore/UserRoles.swift`, `MemberRole.swift`, `TCRoofApp.swift`, `CloudSync.swift`, `DriveRoute.swift`, and `firestore.rules`). Verified with automated unit tests in `tools/firestore-rules-tests/rules.test.js` and `TCRoofCoreTests`.  
**Reference:** [`docs/reference/roles/user-roles.json`](../reference/roles/user-roles.json)

---

## 1. Overview & The Three Roles

TCRoof provides role-based access control across 3 roles:

| Role | Enum | Description | Key Capabilities |
|---|---|---|---|
| **ผู้จัดการ** | `.manager` | Project Manager / Executive | Full system control, permanent deletion of jobs (`job.delete`), member invitation & role assignment (`users.manage`). |
| **ทีมภายใน** | `.internalTeam` (`internal`) | Internal Engineer / Admin | Full visibility over all residential & PWA stations, MP scheduling, customer contacts, signing daily logs (`daily.sign`), closing IEC tests (`iec.close`). |
| **วิศวกรภายนอก / ผู้รับเหมา** | `.external` | External Engineer / Contractor | Sees **only assigned jobs** (`externals`). Fills daily logs, scans devices, performs IEC tests and submits results to the team (`iec.fill_submit`). Customer contacts hidden. |

### People on a job

The role is the member's, across the app. Each job also names people, in the job screen's `JobAccessCard`:

| List | Field | Set by | What it does |
|---|---|---|---|
| ทีมงานของเรา | `Job.teamMembers` (`teamMembers` in Firestore) | `job.assign_team`: manager, internal | Our team members working on the job, picked from the team directory (`TeamDirectory`) or typed. Opens nothing (the team sees every job): the job is in their `งานของฉัน` filter on the PWA home, and its news is announced to them. An address not in the directory is flagged `ไม่อยู่ในรายชื่อทีม`. |
| ผู้รับเหมา / วิศวกรภายนอก | `Job.externals` | `job.assign_external`: manager, internal | The only jobs an external member sees and works on. |
| ผู้ควบคุมงาน | `Job.supervisorEmail` | `job.assign_external` | May sign final acceptance (`handover.final_signoff`). |

`Permissions.isNamed(job)`: on its team, its supervisor or an assigned external. `Permissions.hearsNews(job)`: a feed notification about the job (a daily report sent, a test result, an issue and its due reminder) and its reminders (install days, the MP plan's start-tomorrow and behind-plan, the ERC flow's time limits, the routine reports) are posted on a device when the member is a manager, is named on the job, or the job names none of ours (no team member and no supervisor). The bell's list keeps every post.

---

## 2. Five-Layer Implementation Architecture

```mermaid
flowchart TD
    subgraph L1["1. Core Data Models (TCRoofKit)"]
        UR["UserRole & Capability"]
        Perm["Permissions (can / canView)"]
    end
    subgraph L2["2. Session & State (TCRoof)"]
        MR["MemberRole.shared"]
        App["TCRoofApp (.environment(\.permissions))"]
    end
    subgraph L3["3. UI Permission Gates (SwiftUI)"]
        Views["JobViews / DailyReport / IEC / Settings"]
    end
    subgraph L4["4. Data Sync Isolation (CloudSync)"]
        CS["CloudSync.whereField('externals', arrayContains:)"]
    end
    subgraph L5["5. Backend Enforcement (Firestore)"]
        Rules["firestore.rules (isMember / isTeam / isExternal / readsMine)"]
    end

    L1 --> L2
    L2 --> L3
    L2 --> L4
    L4 <--> L5
```

### Layer 1: Core Models (`TCRoofCore/UserRoles.swift`)
- **`UserRole`**: `manager`, `internal` (`.internalTeam`), `external`. Default fallback for legacy documents without a role is `.internalTeam`.
- **`Capability`**: 37 granular capabilities across 5 groups (Jobs & Plan, Survey/Design, Customer Docs/Permits, Site/Contractor, System/Users).
- **`RoleAccess`**: `.allow`, `.view`, `.deny`, `.conditional`, `.disabled` (e.g. BOQ features are disabled for all roles).
- **`Permissions`**: Evaluates `can(capability, on: job.access)`. Resolves conditional access:
  - `.external` can only act on jobs if their email is in `job.externals`.
  - `.finalSignoff` is permitted only for managers or the job's assigned supervising engineer (`isSupervisor`).

### Layer 2: Global State & Environment (`MemberRole.swift` & `TCRoofApp.swift`)
- When signing in, `MemberRole.shared.signedIn(email)` loads the role from local cache, then asynchronously reads `members/<email>` from Firestore.
- Injected at app root into SwiftUI environment:
  ```swift
  .environment(\.permissions, MemberRole.shared.permissions)
  ```

### Layer 3: UI Permission Gates in Views
Every view queries `@Environment(\.permissions) private var permissions`:
- **Member Directory**: `if permissions.can(.usersManage)` in `PhoneSettings.swift`.
- **Job Assignment**: `if permissions.can(.assignExternal, on: job.access)` in `JobAccessCard.swift`.
- **Job Deletion**: manager only (`.jobDelete`). The app has no delete-job button yet; when one is added it must check `permissions.can(.jobDelete)`. `firestore.rules` already refuses a delete from anyone but a manager.
- **Daily Report Sign-off**: Contractor fills (`.dailyFill`), internal engineer signs (`.dailySign`).
- **IEC 62446**: Contractor submits to team (`.iecFillSubmit`), internal engineer closes (`.iecClose`).

### Layer 4: Cloud Sync Data Isolation (`CloudSync.swift`)
External members only download jobs, surveys, and logs assigned to them:
```swift
if let external = me.role == .external ? me.email : nil {
    return all.whereField("externals", arrayContains: external)
}
```

### Layer 5: Backend Enforcement (`firestore.rules`)
Cloud Firestore rules enforce exact matching logic server-side:
```javascript
function isMember() {
  return request.auth != null
    && request.auth.token.email_verified == true
    && exists(/databases/$(database)/documents/members/$(signedInEmail()));
}
function role() {
  return get(/databases/$(database)/documents/members/$(signedInEmail())).data.get('role', 'internal');
}
function isTeam()    { return isMember() && role() != 'external'; }
function isManager() { return isMember() && role() == 'manager'; }
function isExternal(){ return isMember() && role() == 'external'; }
function readsMine() { return isExternal() && signedInEmail() in resource.data.externals; }
```
- **`members/{email}`**: Read allowed for self or managers; write allowed only for managers (managers cannot delete or edit their own document).
- **`jobContacts/{doc}`**: Customer phone & address isolated to this sub-collection; external members have zero read access.
- **`jobs/{doc}`**: The team creates and edits jobs; only a manager deletes one. External members can only update `iecReport` and `iecState`, and only while the test is `open` (`open` -> `sent`), never close or reopen it. Team devices drop a closing result the document's `iecState` doesn't record (`IECReport.trusting`).
- **`installLogs/{doc}`** (daily reports): External members create and edit the reports of their jobs, but never set or remove `engineerSignedAt` or `inspectorAckAt`, and never delete one.
- **`devices`, `surveyForms`, `pwaSurveys`**: External members write only the documents of their jobs, and never change who a document is open to (`externals`).
- **`photos/{doc}`**: An external member's photo must point at a daily report of their own job or at their job's IEC test; never at an ICL.
- **`inspections/{doc}`** (ICL): External members read theirs, never write.
- **`pwaSurveyRevisions/{doc}`** (issued REVs): The team's only; written once, deleted by a team member only once its survey is gone, or by a manager.
- **`directory/{email}`** (team directory): names and emails of the team and managers, no roles, for picking a job's team members. The team reads it, external members never. Each team member writes their own entry (at sync start, with the name in settings), a manager any team member's (on invite and role change); only listed team members or managers can be in it; a manager deletes entries (on removal or a change to external).
- **`feedAcks/{doc}`**: Any member adds or removes only their own email.
- **`config/{doc}`**: Read by every member, written only in the Firebase console.

Tests: `tools/firestore-rules-tests` (`npm install && npm test`) covers each role, a new user from invite to removal, and the IEC hand-over.

---

## 3. Google Drive Routing by Role (`DriveRoute.swift`)

File storage on Google Drive is separated according to corporate data governance:

1. **Internal Team & Manager** signed in with full Drive access (`GoogleAuth.scope` is `drive`; `hasFullDrive`):
   - Files are stored directly in the **Company Center Drive** (`DriveConfig.centerFolderID`).
   - A team account still signed in under the older `drive.file` access uploads to its own `TCRoof Projects/<job>/`, as a contractor does, until it signs in again.
   - Automatically generates structured handover folders:
     - `1. เอกสารส่งมอบ/` (PWA Handover folders)
     - `2. เอกสารระหว่างก่อสร้าง/` (Daily logs, test reports, inspection photos)
2. **External Contractor**:
   - Files upload to the contractor's **own Google Drive** (`TCRoof Projects/<job>/`).
   - Automatically shares the job folder (read-only) with the company's designated team emails (`DriveConfig.shareWith`).

---

## 4. Key Workflows

### 4.1 Daily Reports & MP Progress
1. Contractor foreman opens the assigned job -> **รายงานประจำวัน**.
2. Fills workers, equipment, attached site photos, and scans barcodes/serials.
3. Internal engineer reviews the report in the app and applies digital signature (`daily.sign`).
4. Only signed daily reports are credited into the **Master Plan (MP) Schedule** progress calculations.

### 4.2 IEC 62446 Testing & Handover State Machine
```text
[Open] (Contractor fills Voc, Imp, IR, thermal photos)
   ↓ (Contractor taps 'ส่งผลให้ทีม')
[Sent] (Locked read-only; waiting for engineer inspection)
   ↓ (Internal engineer inspects and approves)
[Closed] (Locked; books Task 3.1 Pre-Commissioning in MP at 100%)
   ↳ [Sent] can go back to [Open] with ส่งกลับให้แก้; [Closed] reopens to [Open] with แก้ไข (internal team only)
```

### 4.3 Shared iPad on Site
For shared iPads in the field:
- **ตั้งค่า › สลับบัญชี**: Flushes pending offline sync to the cloud, signs out of Google Session, and allows the next user to sign in with their personal Google account.
- The UI and visible data dynamically reload based on the new user's role.
- When the next account is external, the previous account's records are removed from the iPad before sync starts (`LocalData`), so a contractor never sees other jobs; a team account keeps them.
