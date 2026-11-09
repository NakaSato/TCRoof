"""Split a monolithic CLAUDE.md into the root file, per-folder CLAUDE.md files and two docs/ catalogues.
Run from the repo root on a CLAUDE.md that still has the old one-file layout. Text moves word for word."""
import sys
s = open('CLAUDE.md').read()

def between(a, b):
    i = s.index(a)
    j = s.index(b, i) if b else len(s)
    return s[i:j].rstrip() + '\n'

uitests = between('### UI tests (iPhone taps)', '### Simulator checks')
flags = between('### Simulator checks (DEBUG launch arguments)', '## Architecture')
app = between('**App target (`TCRoof/`)**', '**Master Plan sheet**')
sheet = between('**Master Plan sheet**', '**Travel log**')
travel = between('**Travel log**', '**Roles**')
roles = between('**Roles**', '**`TCRoofKit` Swift package**')
kit = between('**`TCRoofKit` Swift package**', '**Data rules every change must keep:**')
data = between('**Data rules every change must keep:**', '## Design specs')
design = between('## Design specs', '## MCP Tools: code-review-graph')
build = between('## Build and test', '### UI tests (iPhone taps)')
project = between('## Project', '## Build and test')

# UI tests: per-test paragraphs to the catalogue, the rest (intro, command, general notes) stays as rules
ui_rules, ui_tests = [], []
for para in uitests.split('\n'):
    if para.startswith('`TCRoofUITests/') or (para.startswith('`') and 'UITests' in para.split(' ')[0]):
        ui_tests.append(para)
    elif para.strip() and not para.startswith('### UI tests'):
        ui_rules.append(para)

# flags: the intro stays with the app, the bullets go to the catalogue (survey and app apart)
head, bullets, cur = [], [], None
for ln in flags.split('\n'):
    if ln.startswith('- '):
        if cur: bullets.append(cur)
        cur = [ln]
    elif cur is not None:
        cur.append(ln)
    elif not ln.startswith('### Simulator'):
        head.append(ln)
if cur: bullets.append(cur)
is_survey = lambda b: b[0].startswith('- `-survey') or b[0].startswith('- `-screen surveyForm')
join = lambda bs: '\n'.join('\n'.join(b).rstrip() for b in bs) + '\n'
survey = [b for b in bullets if is_survey(b)]
other = [b for b in bullets if not is_survey(b)]
intro = '\n'.join(head).strip() + '\n'

files = {
    'docs/debug-flags.md': '# DEBUG launch arguments\n\nEvery DEBUG launch argument the app reads, to open a screen in a given state on a simulator or device. Read this when you need a screenshot or a state to check; add a new flag here, beside its area.\n\n' + intro + '\n## App\n\n' + join(other) + '\n## Survey editor\n\n' + join(survey),
    'docs/ui-tests.md': '# UI tests\n\nWhat each XCUITest taps and the launch arguments it uses. How to run them and the general rules are in `TCRoofUITests/CLAUDE.md`; add a new test here.\n\n' + '\n'.join(ui_tests).strip() + '\n',
    'TCRoofUITests/CLAUDE.md': '# UI tests\n\nThe catalogue of tests (what each taps, its launch arguments) is `docs/ui-tests.md`; the DEBUG launch arguments are `docs/debug-flags.md`. Add a new test to the catalogue.\n\nRun on a simulator of the size the test needs (each test says iPad or iPhone), with your own derived data path; add `-only-testing:TCRoofUITests/<Class>` for one class:\n\n' + '\n'.join(ui_rules).strip() + '\n',
    'TCRoof/CLAUDE.md': '# App target (`TCRoof/`)\n\nRead with the root CLAUDE.md. DEBUG launch arguments (`-screen`, `-homeTab`, `-install…`, `-monitoring…`, `-iec…`, `-survey…`, …) are in `docs/debug-flags.md`; UI tests in `docs/ui-tests.md`. Add a new flag or test there.\n\n' + app + '\n' + travel + '\n' + roles,
    'TCRoofKit/CLAUDE.md': '# `TCRoofKit` Swift package\n\nRead with the root CLAUDE.md (build, test and data rules). Run package commands from this folder.\n\n' + kit,
    'tools/master-plan-sheet/CLAUDE.md': "# Master Plan sheet\n\nThe team's Google Sheet and its Apps Script. Tests: `node --test tools/master-plan-sheet/core.test.js`.\n\n" + sheet,
    'docs/ui/CLAUDE.md': '# Design specs\n\nHow to follow the design boards and specs in `docs/ui/` and `docs/specs/`.\n\n' + design.split('\n', 1)[1].lstrip('\n'),
}
root = '''# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. It holds what every change needs. Each area's details are in a `CLAUDE.md` in its folder, which Claude Code reads when it works there, and two catalogues are read on demand:

| File | What it has |
|---|---|
| `TCRoof/CLAUDE.md` | the app target (sign-in, sync, Drive, travel log) and roles in full |
| `TCRoofKit/CLAUDE.md` | the package's layers: TCRoofUI, TCRoofCore (DXF, drawings, IEC, MP plan, assistant…), PDFReport, ExcelExport, DriveSync, PVYield, ModuleRules |
| `TCRoofUITests/CLAUDE.md` | how to run UI tests and their rules |
| `tools/master-plan-sheet/CLAUDE.md` | the Master Plan Google Sheet and its Apps Script |
| `docs/ui/CLAUDE.md` | how to follow the design boards and specs |
| `docs/debug-flags.md` | every DEBUG launch argument (open a screen in a state, for checks and screenshots) |
| `docs/ui-tests.md` | every UI test: what it taps and its launch arguments |

When a change adds a flag, a UI test or a behaviour, document it in the file of the area it belongs to, not here.

''' + project + '\n' + build.rstrip() + '''

To open a screen in a given state (screenshots, checks), read `docs/debug-flags.md`; to write or run UI tests, `TCRoofUITests/CLAUDE.md` and `docs/ui-tests.md`. Screenshot a simulator with `xcrun simctl io <udid> screenshot`, a paired device with `xcrun devicectl device capture screenshot`.

## Architecture

- **App target (`TCRoof/`):** Google sign-in, SwiftData models, Firestore sync (`Sync/CloudSync.swift`, limited by `firestore.rules`, project `tcroof-1564c`), Google Drive for photos and files, and the non-survey screens. Details: `TCRoof/CLAUDE.md`.
- **`TCRoofKit` package:** all survey work and shared logic: `TCRoofUI` (design system and the survey editor), `TCRoofCore` (pure values and rules), `PDFReport`, `ExcelExport`, `DriveSync`, `PVYield`, `ModuleRules`, `TCRoofMCP`. Details: `TCRoofKit/CLAUDE.md`.
- **Master Plan sheet** (`tools/master-plan-sheet`): a Google Sheet that reads Firestore; renaming or re-encoding the fields it reads breaks it. Details: its CLAUDE.md.
- **Roles:** `members/<email>.role` is `manager`, `internal` or `external` (`docs/reference/roles/user-roles.json`, `TCRoofCore/UserRoles.swift`, kept the same by `RoleTableTests`). Check `permissions.can(.capability, on: job.access)` before showing an action; `firestore.rules` enforces it (tests in `tools/firestore-rules-tests`), and a newly synced collection needs a rule. Raise `AppCompat.syncVersion` when a change needs every device on it before its rules go live. Details: `TCRoof/CLAUDE.md`.

''' + data + '''
UI conventions (all screens): colours from `Theme`, never hex or `Color.white`; buttons with `TCButtonStyle`; hit areas at least 44 pt; content being fetched shows a skeleton in its shape, spinners only for actions; plans and PDF drawings are vector (`Sketch`); split long SwiftUI expressions into computed properties. Details: `TCRoofKit/CLAUDE.md` (design system) and `docs/ui/CLAUDE.md` (boards).

## Code search

If the `code-review-graph` MCP server from `.mcp.json` is connected (`uv tool install code-review-graph`), narrow scope with it (`semantic_search_nodes_tool`, `query_graph_tool`, `get_impact_radius_tool`, `detect_changes_tool`), then read the source; the source wins when they disagree. If it isn't connected, use grep and Read.
'''
old = s
files['CLAUDE.md'] = root
for p, t in files.items():
    open(p, 'w').write(t)

# every line of the old file must be in one of the new ones (the code-review-graph section excepted)
new = ''.join(files.values())
cut = old[old.index('## MCP Tools: code-review-graph'):]
missing = [l for l in old.split('\n') if l.strip() and not l.startswith('#') and l not in new and l not in cut]
print(f'{len(missing)} lines lost', *missing[:10], sep='\n  ')
sys.exit(1 if missing else 0)
