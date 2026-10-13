# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/tcroof-home-iphone-v3/CLAUDE_CODE_TASK.md.

Rebuild the iPhone home (PhoneHome + PhoneTabs, compact width only; PadHome unchanged) to match
docs/ui/tcroof-home-iphone-v3/preview.png and states/*.png at 390 × 844. Do it in this order:

0. Tab bar: replace the full-width bar with the floating dock shown in states/08-dock-crop.png.
   The tabs, in order: หน้าหลัก · งานบ้าน · กปภ. · เครื่องมือ · ตั้งค่า.
   Add the tab-homework, tab-pwa and tab-tools template assets from icons/.
   The selected tab is a navy capsule. Today's-appointments badge goes on the tab that owns the job.
   The feed scrolls under the dock behind a fade. Rename PhoneTab cases and the -homeTab values.
   This replaces docs/ui/tcroof-tools-tab-iphone; skip that one.
1. Remove the six module rows. Ask me first where the plan calendar, scan and install modules should go.
2. Show the นัดวันนี้ card only when there are appointments today.
3. Add the project feed: filter chips (ทั้งหมด · กปภ. · งานบ้าน · ทีมของฉัน) and post cards generated
   from existing records (daily reports, install logs, IEC tests, site issues, an 18:00 daily summary).
   No manual posting and no comments. รับทราบ toggles a shared count; issue posts have แก้แล้ว / เปิดอีกครั้ง.
4. Put the pure feed logic in TCRoofCore (FeedBuilder + tests) and the views in TCRoofUI (add them to ComponentGallery).
5. Add the DEBUG launch arguments from the task to CLAUDE.md.

Read PhoneMenu.dc.html as text for exact sizes and colours, but use Theme tokens in views (no hex, no Color.white).
Keep hit areas ≥ 44 pt and the data rules in CLAUDE.md. Use code-review-graph first, then read the source.
Build with your own -derivedDataPath. Finish with simulator screenshots next to states/, the files changed,
and answers to the open questions.
```
