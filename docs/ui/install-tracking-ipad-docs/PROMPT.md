# Prompt for Claude Code

Get the branch on your Mac first:

```
cd /Users/chanthawat/Developments/TCRoof
git fetch origin
git switch design/install-tracking-ipad-docs
```

Then open Claude Code in the repo and paste:

```
Follow docs/ui/install-tracking-ipad-docs/CLAUDE_CODE_TASK.md.
On iPad, the install tracking page's เอกสาร tab becomes an in-page tab (it pushes
StationDocsScreen today): a summary card, the permit path เส้นทางขออนุญาต (อ.1 / แจ้งเทศบาล →
ขนานไฟ (กฟภ.) → พค.2 (กกพ.)), the selected package's papers and a detail panel, drawn in
docs/ui/install-tracking-ipad-docs/iPadInstall.dc.html (menu 'dc'). Do only the change list
in §5, in order, and nothing else. Read every value from Job.stationDocs / StationDocs and
reuse StationDocsScreen's sheets for upload, open and export; never hard-code a board
value (assets/sample-data.json are examples). Use code-review-graph first as CLAUDE.md
says. Build with your own -derivedDataPath, run -screen home -homeTab pwa -homeBoard YES
-installOpen YES -installDemo YES -installTab docs on an iPad simulator, save screenshots
to docs/ui/install-tracking-ipad-docs/screenshots/ with the names of states/, compare,
tick the change list and answer the open questions in §7.
```

Work on `design/install-tracking-ipad-docs` (or a `feat/…` branch made from it), not on `main`. It is separate from
`design/install-tracking-iphone`, so the two can be built in parallel.
