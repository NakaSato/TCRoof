# Prompt for Claude Code

Open Claude Code in the TCRoof repo (`/Users/chanthawat/Developments/TCRoof`) and paste:

```
Follow docs/ui/tcroof-home-iphone-v4/CLAUDE_CODE_TASK.md.

The iPhone home (v3) is already built. Change ONLY these three things, on iPhone only:

1. Dock: the 4th tab "เครื่องมือ" becomes "เอกสาร".
   - It uses the existing "tab-docs" asset.
   - It opens the PWA documents page (board PhonePwaDocsV2), not HomeLibraryView.
     That overview is not built yet, so for now open what PWAPhoneTabs' เอกสาร tab opens, and report it.
   - Rename PhoneTab.tools to .docs and update "-homeTab".
   - Do not delete ToolsView: keep it reachable from a "เครื่องมือวัด" row in the settings sheet, and report where.

2. When there is no survey appointment today, show the hero titled "แผนงานถัดไป" instead of hiding it.
   - Reuse AppointmentHero with title:.
   - Use up to 3 upcoming plan items, nearest first: install days, IEC tests, PWA document deadlines.
   - Each page's button follows its type: "ดูแผนงาน ›", "เปิดฟอร์มทดสอบ ›" or "ดูเอกสาร ›".
   - The top-right shows the item's date and position.
   - If nothing is upcoming, hide the card as before.
   - Add "-homeHeroPlan demo".

3. Feed filter: replace the iPhone chip row with TCCountSegments.
   - Equal widths, 4 segments with counts.
   - Same filter rules and the same "-homeFeedFilter".
   - The iPad keeps its chips.

Do not touch:
- the header, bell, feed posts, acknowledgements or FeedBuilder
- the dock's look
- the hero when appointments exist
- the iPad, or the PWA module's own dock

Steps:
1. Read the task, then PhoneMenu.dc.html as text, and measure on states/*.png.
2. Use code-review-graph first, as CLAUDE.md says.
3. Build with your own -derivedDataPath and run on an iPhone simulator.
4. Save screenshots of states 01, 02, 05 and 08 in docs/ui/tcroof-home-iphone-v4/screenshots/ and compare them with states/.
5. Report:
   - the differences from states/
   - where the tools modules went
   - which plan sources had no model
   - the open questions
```
