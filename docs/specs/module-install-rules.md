# Module installation rules (ZNSHINE), iPad / iPhone

**Status:** Phase 1 (2026-10-21): the `ModuleRules` target (catalog types, mounting profiles, the rule set, the rule
engine and the four calculators, with unit tests). Phase 2 (2026-10-21): the residential survey's
`ตรวจตามคู่มือติดตั้งแผง` card / section (`SurveyFormView+Install.swift`, stored as `SurveyForm.installCheckJSON`,
synced as `installCheck`; saving stops on a block or a warn without a reason; the altitude comes with the GPS fix;
`img/module-install-survey-ipad.png`). Phase 3 (2026-10-21): C1 แผงบนหลังคา's `ตรวจตามคู่มือติดตั้งแผง` card (`RoofPageWide+Rules.swift`, stored as C1's
`pvRules`, `ArrayLayoutCheck`): the catalog model (matched from the layout's module, or picked, which sets it), the
mounting method with torque, washer and load rating, the clamp zone drawn on a module bar against the offsets the layout
uses (`RoofMountLayout.clampOffsetsMm`, the side from `clampsLongSide`), a one-tap `ใช้ช่วงจับตาม ZNSHINE ในงานนี้` that
sets the job's clamping zone to L/4 ± 50 mm (decided 2026-10-21: ZNSHINE's zone for ZNSHINE modules, existing layouts
unchanged until then), the string builder (N_max and cold Voc live), cable and grounding; the list is `ModuleRulesList`,
shared with the survey; `img/module-install-layout-ipad.png`. Phase 4 (2026-10-21): the daily report's
`ตรวจติดตั้งแผงตามคู่มือ` card (both layouts) and sheet (`DailyModuleCheck.swift`, stored as `RoutineReport.Daily.moduleCheck`,
`InstallDailyCheck`, nil on days without module work so other reports encode as before): safety ticks, mounting
readings (bolt torques typed as a list, washer, clamps, overlap, gap, rear clearance, frame), cable, grounding and
serials typed in; ตรวจ & ลงนาม stops while a block is open or a warn has no reason, and signing stamps the versions;
`img/module-install-daily-ipad.png`. Not built: evidence photos per item and the barcode scan of serials (typed for now).
Phase 5 (2026-10-21): the string test on IEC step 2 (`StringTest.swift` in `ModuleRules`, `IECReport+StringTest.swift`,
the app's `IECVIPage+Manual.swift`), with the module's values from its datasheet (decided 2026-10-21: ZNSHINE follows
the datasheet): the IEC test's module (brand and power) is matched to the catalog, and each string's expected Voc is
N × Voc × (1 + β × (T − 25)) at the module temperature, typed in step 1 (`แผง | ไม่มีใน Excel`,
`Conditions.moduleTempC`, no Excel cell) or estimated from the air, the light and NMOT (T = T_air + (NMOT − 20) × G / 800).
ZN-132 (warn, rule set A.2) flags a string more than 5 % off at 200 W/m² or more, in step 2's `ตรวจตามคู่มือแผง` card;
it doesn't fail the string. ZN-110 (block) fails both strings of an MPPT whose Voc differ by more than 10 V (a reversed
string already fails as `ขั้วสายกลับ`), and applies to any module. The Excel sheet and its median check are unchanged. `img/module-install-string-test-ipad.png`.

**Sources** (Claude Docs, the team's): *TCRoof Dev Spec — Module Installation Rules*
(<https://claude.ai/artifact/PV7GXqcwu67rvmjmJR2a1B>) and its source *ZNSHINE Module Installation Spec — TCRoof*
(<https://claude.ai/artifact/X7PUwouCKkoUq9ao3yNHhB>), Section 5 of ZNSHINE's *PV Modules Installation Manual — Regular
Single-glass Modules*, Doc No. QES/ZX-RD-III033A, Edition A, effective 2020-10-13. Rule ids `ZN-xx` are the source's.

## 1. Goal and scope

Every survey and installation record is checked on the iPad against the module maker's installation rules, and keeps
the evidence the module warranty depends on. ZNSHINE first; catalog and rules are data, so other brands plug in later.

| Item | Decision |
|---|---|
| Platform | iOS / iPadOS, SwiftUI, offline-first; the same flows on iPhone and iPad |
| Phase | Phase 1: internal docs, survey and report |
| Rule ids | Reuse `ZN-xx` from the source so QA and field staff speak the same ids |
| Manufacturer | ZNSHINE first; data-driven |

In scope: the module catalog; mounting-method profiles (bolt, single-axis tracker, 2V, clamp) with torque, washer and
load data; the rule engine with block / warn / info; installation checks in the residential site survey; the installation
daily report checklist with photo and value evidence; string sizing, cable ampacity, tilt and clamp-position calculators;
pre-commissioning hooks (polarity, string Voc difference).

Out of scope: BOQ (disabled in TCRoof); preliminary energy yield (a separate feature that reads the catalog); the PWA
IEC 62446 report layout (stays as the original form); O&M and cleaning records (next phase).

## 2. Roles and workflow

The contractor's foreman fills the installation daily report, the rule engine checks it, and only a TC engineer's
sign-off on a report with no open block moves the MP plan. A report with any open block returns to the foreman; warn
items pass to the engineer with the foreman's reason attached.

| Role | In this feature |
|---|---|
| Maintainer | Edits catalog, mounting profiles and rule sets; publishes new versions |
| Manager / Project Manager | Views all records, warn reasons and rule versions; exports |
| Internal Engineer | Fills survey and layout; signs daily reports (รับทราบ); accepts or rejects warn reasons |
| External Engineer / Contractor | Fills daily reports and string tests; scans serials; cannot sign |

## 3. Data model

Catalog and mounting profiles are read-only reference data shipped as versioned JSON; survey, layout, install and
commissioning records are project data synced per job. Every record stores the catalog version and the rule-set version
it was validated against, so an old report re-opens with the rules it was signed under.

| Entity | Kind | Key fields |
|---|---|---|
| `ModuleModel` | Reference | model, size class, cell count, STC values, dimensions, weight, max system voltage, max series fuse, β Voc / γ Pmax (optional) |
| `MountingProfile` | Reference | method, hole spec, bolt, torque range, washer spec, load rating per module group |
| `SiteInstallCheck` | Project | latitude, altitude, sea distance band, humidity, temperatures, roof fireproof, rear clearance, planned tilt, T_min |
| `ArrayLayout` | Project | module model, orientation, mounting profile, clamp side, clamp offset A, gap, strings |
| `InstallDailyReport` | Project | date, checklist items, torque readings, photos, scanned serials, signatures |
| `StringTest` | Project | string id, Voc measured, polarity ok, irradiance, temperature |

Size class: **big** = 72 / 78 / 144 / 156 cells, **small** = 60 / 66 / 120 / 132.

## 4. Mounting methods (source §5.5)

Only these four are approved; anything else needs ZNSHINE sign-off. Loads assume two continuous rails under each module
and a safety factor of 1.5.

| Method | Holes | Bolt set | Torque (N·m) | Washer |
|---|---|---|---|---|
| A. Bolt, fixed rack | middle 4 of 8 × φ9×14 | M8 + flat + spring washer + nut | 16–20 | flat SS ≥ 1.8 mm, OD 20–24 mm |
| B. Single-axis tracker | 4 × φ7×10 | M6 SS + flat + spring washer + nut | 16–20 (as stated) | flat SS ≥ 1.5 mm, OD 16–20 mm |
| C. 2V tracker | 2 × φ7×10 + 2 × φ9×14 | per hole size | per hole size | as A / B |
| D. Clamp | — | ≥ M8 | 16–20 for M8 | — |

| Method | Modules (cells) | Load + / − (Pa) | Position |
|---|---|---|---|
| A. Bolt | 60/66/72/78/120/132/144 | +3600 / −1600 | rails ⟂ long frame, middle 4 holes |
| A. Bolt | 156 | +2400 / −1600 | as above |
| B. Tracker (UL 1703) | all | ±1436 (30 lb/ft²) | 4 × φ7×10 holes |
| B. Tracker, holes at L/2 | 60/66/72/120/132/144 | +1600 / −1600 | hole pair 400 mm apart at mid-length |
| C. 2V | 60/66/72/120/132/144 | +1600 / −1600 | per hole layout |
| D. Clamp, long side | 60/66/72/78/120/132/144 | +3600 / −1600 | A = L/4 ± 50 mm, rails ⟂ long frame |
| D. Clamp, long side | 156 | +2400 / −1600 | A = L/4 ± 50 mm |
| D. Clamp, short side | 60/66/120/132 only | +1050 / −1050 | A = W/5 ± 50 mm, rails ⟂ short frame |

A is measured from the module edge to the clamp centre; L = module length, W = module width.

## 5. Validation rules

The engine runs on every field change and on submit: a **block** stops submit, a **warn** needs a written reason from the
engineer, an **info** only shows a hint. The rules' ids, stages, severities and messages (Thai and English) are a
versioned JSON rule set; their conditions are the engine's.

| Rule | Stage | Condition | Severity | Message (EN) |
|---|---|---|---|---|
| ZN-70 | Survey | altitude > 2000 m | block | Above 2,000 m — not allowed for these modules |
| ZN-73a | Survey | sea distance < 100 m | warn | Under 100 m from sea/sulfur — installation not recommended |
| ZN-73b | Survey | sea distance 100 m–1 km | warn | Use anti-salt modules and SS/Al hardware |
| ZN-69 | Survey | humidity > 85 % RH | warn | Consult ZNSHINE before installing |
| T5-1 | Survey | monthly average temperature outside −20…+47 °C | warn | Outside recommended working temperature |
| ZN-77 | Survey | roof fireproof layer = no | warn | Roof needs a fireproof layer under the array |
| ZN-81 | Survey / Layout | tilt < 10° | warn | Tilt under 10° — faults not covered by warranty |
| ZN-82 | Survey / Layout | tilt ≠ recommended (Table 5-2) | info | Recommended tilt for this latitude is X° |
| ZN-79 | Layout | modules in one string differ in tilt or azimuth | block | All modules in a string need the same tilt and orientation |
| ZN-52 | Layout | big AND landscape AND clamp side short | block | Big modules cannot be fixed on the short frame |
| ZN-53 | Layout | small AND landscape AND two modules share one long-frame rail | block | Small modules cannot share one horizontal rail on the long frame |
| ZN-85 | Layout | bifacial AND height outside 0.5–2 m | warn | Bifacial height should be 0.5–2 m |
| ZN-90 | Layout / Install | rear clearance < 115 mm | warn | Clearance under 115 mm recommended minimum |
| ZN-91 | Layout / Install | module gap < 10 mm | block | Gap between modules must be ≥ 10 mm |
| ZN-95 | Layout | clamp length < 60 mm OR thickness < 3 mm | block | Clamp below tested size |
| ZN-97 | Layout / Install | clamps per module < 4 | block | At least 4 clamps per module |
| §5.5.3 | Layout | clamp offset A outside L/4 ± 50 mm (long) or W/5 ± 50 mm (short) | block | Clamp outside the rated zone |
| §5.5.3 | Layout | clamp side short AND cell count not 60/66/120/132 | block | Short-side clamping not rated for this module |
| ZN-88 | Layout | rails per module < 2 | warn | Load rating assumes 2 continuous rails |
| ZN-105 | Layout | mixed module models in one string | block | One module model per string |
| ZN-106 | Layout | string cold Voc > min(1500 V, inverter max DC) | block | String voltage exceeds limit at T_min |
| ZN-106b | Layout | β Voc missing | block | Add datasheet temperature coefficient before sizing |
| ZN-112 | Layout | cable ampacity < 1.25 × Isc × Np | block | Cable under-rated |
| ZN-107 | Layout | DC cable < 4 mm² | block | DC cable must be ≥ 4 mm² |
| ZN-122 | Layout | grounding chain > 4 parallel OR > 8 series | warn | Grounding chain too long |
| §5.5.1 | Install | bolt torque outside 16–20 N·m | block | Re-torque to 16–20 N·m |
| §5.5.1 | Install | washer thickness / OD below spec | block | Washer below spec |
| §5.5.3 | Install | clamp overlap outside 7–10 mm | block | Clamp overlap must be 7–10 mm |
| ZN-121 | Install | ground torque outside 4–8 N·m | block | Ground bolt must be 4–8 N·m |
| ZN-108 | Install | bend radius < 43 mm | block | Cable bent tighter than 43 mm |
| ZN-61 | Install | crew count < 2 | block | Never work alone |
| ZN-63 / 99 | Install | frame drilled or modified | block | Frame modification voids warranty |
| ZN-110 | Commission | parallel strings' Voc differ > 10 V OR polarity reversed | block | Recheck string before paralleling |

The `§5.5.x` rows have no ZN number in the source; the code names them `S551-torque`, `S551-washer`, `S553-zone`,
`S553-short` and `S553-overlap`.

## 6. Calculations

Pure functions in `ModuleRules` (no UI), the same in the app, the tests and a later web port.

- **Max modules in series (ZN-106, Table 5-4):** N_max = ⌊V_sys / (Voc · [1 + β (T_min − 25)])⌋, V_sys = the lower of
  the module's max system voltage and the inverter's max DC input; nil without β (ZN-106b).
- **Min cable ampacity (ZN-112):** I = 1.25 × Isc × Np.
- **Recommended tilt (Table 5-2):** |lat| < 15° → 15°; < 25° → lat; < 30° → lat + 5°; < 35° → lat + 10°; < 40° → lat + 15°;
  else lat + 20°. Latitude exactly 15° takes the 15°–25° row (both give 15°).
- **Clamp zone (§5.5.3):** long side L/4 ± 50 mm; short side W/5 ± 50 mm, only for 60 / 66 / 120 / 132 cells (else nil).

| Function | Input | Expected |
|---|---|---|
| maxModulesInSeries | NH144-445 (Voc 50.1 V), β −0.28 %/°C, T_min 15 °C, no inverter | 29 |
| maxModulesInSeries | same, inverter max DC 1100 V | 21 |
| minCableAmpacity | Isc 11.40 A, Np 1 | 14.25 A |
| recommendedTilt | 13.7° (Bangkok) | 15° |
| recommendedTilt | 18.8° (Chiang Mai) | 18.8° |
| clampZone long | L 2094 mm | 473.5–573.5 mm |
| clampZone short | 144-cell module | nil (not rated) |

## 7. Screens and forms (phases 2–5)

The rules surface in four places, each with a live rule banner at the top and badges on the fields that triggered it.

1. **Survey → Installation checks (residential only):** latitude / longitude (GPS, editable → ZN-82), altitude (ZN-70),
   distance to sea / sulfur (`< 100 m | 100 m–1 km | > 1 km`, ZN-73a/b), ammonia site (info), high wind / lightning
   (notes ZN-75 / 76), monthly min / max temperature and T_min (T5-1, string sizing), humidity (ZN-69), roof fireproof
   layer with photo (ZN-77), rear clearance (ZN-90), roof-edge safe zone with photo (ZN-77), shading sources with photos
   (ZN-72).
2. **Layout → Module and mounting:** module picker from the catalog; mounting method filling hole, bolt, torque, washer
   and load rating (shown beside the site's design load); clamp side and offset A with the allowed zone on a module
   outline; string builder (modules per string, inverter max DC → live N_max and cold Voc); cable size and parallel count
   → live ampacity.
3. **Installation daily report → module install checklist:** crew count, PPE, no jewellery (ZN-61, ZN-54); dry weather
   and connectors (ZN-56/57); broken or corroded modules rejected with their serials scanned (ZN-17/26); bolt torque
   sampled per row with a photo of the wrench (§5.5.1); washer spec (§5.5.1); clamp count, offset, overlap (ZN-96/97);
   module gap, rear clearance (ZN-90/91); drain holes clear, frame not drilled (ZN-92, ZN-63); same cell colour together
   (ZN-89); cable routing: no loops, bend ≥ 43 mm, out of sun, in conduit (ZN-100/108/65/116); grounding wire size, M4 +
   star washer, torque (ZN-120/121); installed module serials by barcode (catalog match).
4. **Commissioning → string test hook:** per-string Voc with irradiance and module temperature; expected Voc = N × Voc
   corrected to the measured temperature, deviation > 5 % at ≥ 200 W/m² flags a poor connection (ZN-132); before
   paralleling, polarity confirmed and Voc difference ≤ 10 V (ZN-110). Values feed the existing IEC 62446 report without
   changing its layout.

## 8. Acceptance

- Each rule id has one passing and one failing unit test; the calculation table and the tilt boundaries 15°, 25°, 30°,
  35°, 40° are tested.
- The catalog loads the ZXM7-UHLDD144 datasheet's models (each with size class, STC values, dimensions and the datasheet's loads, NMOT and coefficients).
- A block disables submit and lists the rule id; a warn cannot be submitted without a reason.
- Changing the rule-set version does not re-validate signed reports; they show the version they were signed under.
- A daily report can't be signed by the TC engineer while any block is open.
- Barcode `ZX7523351920xxxx` decodes to mono with coating, 5BB, workshop 3, 2020-01-08.
- All forms work offline and sync on reconnect without losing photos.

| Case | Steps | Expected |
|---|---|---|
| Low tilt | Survey at Bangkok, planned tilt 5° | ZN-81 warn, ZN-82 suggests 15° |
| Big module short-side clamp | NH144-445, landscape, clamp side short | ZN-52 block; short side greyed out |
| String too long | NH144-445, 24 modules, inverter 1100 V, T_min 15 °C, β −0.28 %/°C | ZN-106 block; N_max 21 shown |
| Missing β | a model with no temperature coefficient, string builder | ZN-106b block until β entered |
| Torque out of range | daily report bolt reading 22 N·m | §5.5.1 block; engineer sign-off disabled |

## 9. Open items

- ~~**The 59-model catalog**~~ Decided 2026-10-21: the catalog follows the team's module datasheet, ZNSHINE
  ZXM7-UHLDD144 Series version 2301.E (`docs/reference/datasheets/ZXM7-UHLDD144_Series.pdf`), 565–595 W, with 570 W
  first; the app's default module `p570` follows it (2278 × 1134 × 30 mm, was 2279).
- ZNSHINE datasheets for β (Voc), γ (Pmax), NOCT per model (blocks ZN-106 and energy yield).
- Confirm with ZNSHINE: M6 tracker torque (16–20 N·m as stated), parallel fusing wording, 78-cell allowed methods, the
  big-module landscape rule.
- Confirm the warranty accepts Thai code (EIT / PEA / MEA) in place of NEC / AS3000.
- Torque sampling rule for the daily report (every bolt, or N per row).
- An inverter catalog (max DC input); manual entry until then.
- The barcode decoder (Section 7 of the manual, not in the sources).
- C1's own clamp zone (`RoofMountStandard.clampFromModule`, 0.34–0.68 m on a 2.28 m module) is wider than ZNSHINE's
  L/4 ± 50 mm (0.52–0.62 m); phase 3 decides which the layout uses.
