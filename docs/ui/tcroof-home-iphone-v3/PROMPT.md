# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/tcroof-home-iphone-v3/CLAUDE_CODE_TASK.md.

Rebuild the iPhone home (PhoneHome, compact width only; PadHome unchanged) to match
docs/ui/tcroof-home-iphone-v3/preview.png and states/*.png at 390 × 844:
1. Remove the six module rows. Ask me first where the scan / install / PWA modules should go.
2. Show the นัดวันนี้ card only when there are appointments today.
3. Add the project feed: filter chips (ทั้งหมด · กปภ. · งานบ้าน · ทีมของฉัน) and post cards generated
   from existing records (daily reports, install logs, IEC tests, site issues, an 18:00 daily summary).
   No manual posting and no comments. รับทราบ toggles a shared count, and issue posts have แก้แล้ว / เปิดอีกครั้ง.
4. Put the pure feed logic in TCRoofCore (FeedBuilder + tests) and the views in TCRoofUI (add them to ComponentGallery).
5. Add the DEBUG launch arguments from the task to CLAUDE.md.

Read PhoneMenu.dc.html as text for exact sizes and colours, but use Theme tokens (no hex in views).
Use code-review-graph first, then read the source. Build with your own -derivedDataPath.
Finish with screenshots next to states/, the files changed, and answers to the open questions.
```
