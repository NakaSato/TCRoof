# Prompt for Claude Code

Get the branch on your Mac first:

```
cd /Users/chanthawat/Developments/TCRoof
git fetch origin
git switch design/install-tracking-iphone
```

Then open Claude Code in the repo and paste:

```
Follow docs/ui/install-tracking-iphone/CLAUDE_CODE_TASK.md.
Build the iPhone (compact width) install tracking page from the board
docs/ui/install-tracking-iphone/PhonePwaInstall.dc.html: an installing PWA station opens it
on iPhone instead of JobDetailView. Do only the change list in §5, in order, and nothing
else: the iPad layout of InstallTrackingPage stays as it is. Reuse InstallPageData,
InstallDailyData, InstallGantt, InstallPlan, MPWorkbook and the existing screens; never
hard-code a board value (they are examples, assets/sample-data.json). Use code-review-graph
first as CLAUDE.md says, then read the source and the board as text. Build with your own
-derivedDataPath, run -screen pwa -installOpen YES -installDemo YES -installTab <tab> on an
iPhone simulator, save screenshots to docs/ui/install-tracking-iphone/screenshots/ with the
names of states/, compare, tick the change list and answer the open questions in §7.
```

Run it as its own branch: commit on `design/install-tracking-iphone` (or a `feat/…` branch made from it), not on `main`.
