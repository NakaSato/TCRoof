# Prompt for Claude Code

```
git fetch origin && git switch -c feat/iec62446-step4-after-vi-ipad origin/design/iec62446-step4-after-vi-ipad
```

```
Follow docs/ui/iec62446-step4-after-vi-ipad/CLAUDE_CODE_TASK.md.

FIRST check that TCRoof/Views/Install/IEC/IECBeforeVI*.swift and TCRoofKit/Sources/TCRoofCore/IECReport+BeforeVI.swift
exist (step 2 is built on this branch). If not, STOP and report.

Build ONLY step 4/7 "หลังออน · แรงดัน / กระแส" on iPad, by GENERALISING the step-2 page for the after phase
(a phase parameter), not by copying it:

1. Header "IEC 62446 · หลังออนระบบ · แรงดัน / กระแส", 4/7.
2. Green banner "ออนระบบแล้ว HH:MM น. · วัดขณะจ่ายไฟ" / "… เติม INV 0n-หลัง แถว 17, 19".
3. Photo cards and dialog for Vmp (E17, Slot.vmpV, .voltageAfter) and Imp (E19, Slot.impA, .currentAfter),
   no polarity row; report line "7 · ภาพถ่าย IEC-test After".
4. Table columns String · MPPT · ช่อง · แผง · Vmp · ต่าง · Imp · ผล;
   footer วัดแล้ว · มัธยฐาน Vmp · กระแสรวม · Excel แถว 17 · 19.
5. Bottom bar ‹ 3/7 ฉนวน (IR) and 5/7 พลังงานและ PR › (existing screens until built; report).
6. Shared board updates (step 2 gets them too): table labels "String n"; the selected slot's YELLOW highlight
   (ring #FFD400 + MPPT column #FFF6CC / #E8B21A).
7. DEBUG -iecStep4 / -iecStep4State (one line in CLAUDE.md).

Rules:
- Vmp ±5 % of the median of strings with the same module count.
- Imp is recorded only (never fails).
- No polarity after the connection.
- Excel cells and the exporter's map don't change.
- Optional IECReport fields only.

Steps:
1. Read the task, then iPadIECStep4.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says (grep if it doesn't connect).
3. Build with your own -derivedDataPath. Run swift test with the new tests, and IECStep2UITests.
4. Run on an iPad Pro 13" simulator. Save screenshots 01, 02, 05, 06 and 07 in
   docs/ui/iec62446-step4-after-vi-ipad/screenshots/ and compare them with states/. Re-check step 2's states 01 and 06.
5. Commit on feat/iec62446-step4-after-vi-ipad and push it (no merge).
6. Report:
   - the differences
   - the new type names
   - where ก่อนหน้า / ถัดไป link to
   - the open questions
```
