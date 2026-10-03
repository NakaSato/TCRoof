Follow docs/ui/components/CLAUDE_CODE_TASK.md

Build the TCRoof SwiftUI component library from the board in docs/ui/components. The board is in preview.png, sections/01–09 *.png and components.pdf; exact values are in preview.html, grf.css and tokens.css.
1. Theme: match tokens.css in light and dark. Add okTick #3B7420, okSoft, pendingSoft #FFF4E5, dangerText, dangerSoft, onPrimary, sun. Add the type scale (30/24/17/13), spacing (4/8/12/16/24) and radii (8/10/12/16).
2. Components, one file per board section, each with #Preview for every state on the board:
   - Layout: survey header + 13 capsules, PWA header, white nav bar, bottom bar 53 pt (iPad: status button · บันทึกร่าง · ‹ · ›; iPhone: บันทึก + 72×53 ‹ ›), page scaffolds
   - Buttons: styles, states, and the iPad/iPhone size table
   - Inputs: field label, required-empty, read-only, default/nameplate tag, dropdown, date/time, stepper, chips, segmented, checkbox 22 pt #3B7420, radio card, switch, long text + counter, signature, search + clear
   - Status chips, ring, segmented bar, banners, toast
   - Cards and list rows
   - Media: photo slot, map, compass
   - Overlays: dialog, alert, side panel, notification panel
   - NumberPadPopover replacing the system keyboard for numeric fields (range, step, unit, out-of-range state)
3. Reuse and extend the existing views (Theme.swift, Components.swift, PhotoComponents.swift, SurveyUI/Components.swift, Fields.swift, InputFields.swift) rather than duplicating them. Swap them into existing screens only where the look matches directly, and keep the current iPad layouts.
4. Add a DEBUG-only ComponentGallery screen reachable from Settings that lays the components out like the board.

Thai UI text exactly as on the board. No hex literals in views. Touch targets ≥ 44 pt. Prefer SF Symbols (icons/README.md). Use code-review-graph first (run `code-review-graph build` if it's empty), then read the source.

Work on a new branch feat/component-library. Build, run ComponentGallery on an iPad Pro 13" (landscape) and an iPhone 16 simulator, and compare with sections/*.png. Finish with a summary of files changed, which screens now use the components, and the remaining differences from the board.
