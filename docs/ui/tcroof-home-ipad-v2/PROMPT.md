# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/tcroof-home-ipad-v2/CLAUDE_CODE_TASK.md.
Change only what it lists on the iPad home (PadHome): (1) replace the six module rows in the
right column with the project feed "ฟีดโครงการ" by reusing the iPhone feed (HomeFeed, TCFeedPost,
ProjectFeed) — header row with filter chips, scrolling posts; (2) add the floating dock built
from TCTabBar (หน้าหลัก · สำรวจ · แผนงาน · ติดตั้ง · สแกน · กปภ. · เครื่องมือ | ตั้งค่า), ตั้งค่า opens
the existing settings sheet; (3) remove the account avatar from the navbar; (4) hero title one
line, "ดูทั้งหมด" opens the survey home. Do not touch the hero, timeline, pending card,
notification panel, settings sheet or anything on iPhone. Read the task, then iPadMenu.dc.html
as text; measure on states/*.pdf. Use code-review-graph first as CLAUDE.md says. Build with
your own -derivedDataPath, run on an iPad Pro 13" simulator in landscape, save screenshots in
docs/ui/tcroof-home-ipad-v2/screenshots/, compare with states/, then report differences, the
navigation choice for the dock, and the open questions.
```
