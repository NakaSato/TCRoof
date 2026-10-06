Follow docs/ui/tcroof-home-iphone-v2/CLAUDE_CODE_TASK.md

The iPhone home (PhoneHome, built from docs/ui/tcroof-home-iphone in c677022) has a v2 design: minimal and readable outdoors. Apply only the listed differences, on compact width only (HomeSize .phone); the iPad home must stay pixel-identical:
1. Minimal header:
   - no greeting text on compact (keep HomeGreeting for iPad)
   - white, no border, bottom radius 2, soft shadow
   - AppLogo 44 pt (r12) at the leading edge
   - bell + avatar in one 48 pt capsule (#F5F8FB, no border, no divider) at the trailing edge
   - bell is a 44 target with a red #D9453B badge; avatar is a 36 pt navy #16325C circle inside a 44 target
2. Hero card:
   - solid #0E2747 (no gradient)
   - text opacity 95/92 %
   - ring #9BE26E on white 28 %
   - primary button text #0E2747 weight 800
   - navigate/call buttons white 20 % with a 1 pt white 35 % border
3. Module rows: border #C9D3E0, subtitle #44546A, chevron #7A8BA3; page bottom padding 86 so the rows clear the tab bar.
4. New docked bottom tab bar, minimal and as short as possible:
   - full width, white, 1 pt #C9D3E0 top border, no shadow
   - 5 tabs min 48 pt: หน้าหลัก, สำรวจ (badge = today's survey appointments), แผนงาน, ติดตั้ง, ตั้งค่า (opens the Settings sheet)
   - glyph 22 + label 10.5; selected = 52×28 #E3EEF8 capsule behind the glyph, #1F6FB5, weight 800; unselected #3E4C60
   - build it as TCRoofUI `TCTabBar`, add it to ComponentGallery, show it on tab roots (home and the survey list), hide it on pushed screens
5. Same contrast pass on notifications and settings: #5B6B82→#44546A, #56657A→#3E4C60, #AAB6C5→#7A8BA3, #DDE4ED→#C9D3E0.

Add the new colours as Theme tokens (heroSolid, ringOutdoor, inkStrong, inkTab, borderOutdoor); no hex in views. Add the DEBUG arg -homeTab survey|plan|install. Use code-review-graph first, then read the source. Work on a new branch feat/iphone-home-v2. Build, run on an iPhone 16 simulator and compare with states/*.png (measure in the PDFs). Finish with a summary: the files changed, the tokens, the tab navigation model you chose, and the answers to the open questions.
