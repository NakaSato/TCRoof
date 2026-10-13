# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/tcroof-home-ipad-v3/CLAUDE_CODE_TASK.md.

The iPad home (PadHome) is built from tcroof-home-ipad-v2, with the แผนงานวันนี้ hero from dbc6cb3.
Change ONLY these five things, on iPad (regular width) only:

1. "วันนี้" lists EVERY plan item of today, in time order:
   - Item types: install (home + PWA MP tasks), ตรวจรับ, เอกสาร, ทดสอบ, นัดสำรวจ.
   - Each type has its own tag and button: เปิดบันทึกประจำวัน / เปิดงานตรวจรับ / ดูเอกสาร / เปิดฟอร์มทดสอบ / ทำต่อ.
   - Use the plan data PWAPlanPhoneView already reads. Add no models, and report any source that has none.
   - The card fills the free height and scrolls inside. The "next" row is open by default.
   - Subtitle: "n รายการ · ทุกแผนงาน".
2. "งานสำรวจค้างอยู่" is capped at 2 rows (166 pt).
3. Feed filter: the iPad chip row becomes TCCountSegments.
   - 440 pt, 4 segments with counts.
   - Same rules and the same -homeFeedFilter.
4. Feed posts on iPad lose the coloured badge after the author's name.
   - Add a TCFeedPost parameter for this. iPhone keeps its badge.
5. Post stat tiles on iPad become one summary strip: icon + label, a 24 pt coloured value, and a 5 pt bar for x/y values.
   - iPhone keeps its tiles.

Dock: if docs/ui/pwa-solar-survey-ipad-v3 §1 is not built yet, do it here as written there. Otherwise skip it.

Do not touch:
- the hero (keep แผนงานวันนี้ from dbc6cb3)
- the header, bell, feed content and FeedBuilder
- the iPhone home, data models

Steps:
1. Read the task, then iPadMenu.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPad Pro 13" simulator (landscape).
4. Save screenshots of states 01, 02, 04 and 08 in docs/ui/tcroof-home-ipad-v3/screenshots/ and compare them with states/.
5. Report:
   - the differences from states/
   - which plan sources had no model
   - whether the new items joined the hero
   - whether you did the dock
   - the open questions
```
