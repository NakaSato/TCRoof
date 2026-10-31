# Project Swift skills

Skills are committed locally for Codex and other Agent Skills clients. Claude Code
uses relative aliases in `.claude/skills/`. No global plugin or home-directory
installation is required. Start a new agent session if newly added skills are not
automatically discovered.

| Skill / guide | Use |
| --- | --- |
| [swift-codebase-analysis](swift-codebase-analysis/SKILL.md) | Ten-section audit with file:line evidence, quick wins, strategic refactors, and a P0–P3 table |
| [swiftui-performance-audit](swiftui-performance-audit/SKILL.md) | Source investigation, profiling plan, and evidence-based performance report |
| [swiftui-expert-skill](swiftui-expert-skill/SKILL.md) | AvdLee's SwiftUI state, composition, performance, and API guidance |
| [swiftui-pro](swiftui-pro/SKILL.md) | Existing Paul Hudson installation; navigation, layout, accessibility, localization |
| [swiftui-gotchas](swiftui-gotchas/SKILL.md) | Daniel Eden's SwiftUI/concurrency/SwiftData antipattern catalog |
| [swift-concurrency](swift-concurrency/SKILL.md) | Piemonte's concurrency and isolation reference |
| [swift-testing-expert](swift-testing-expert/SKILL.md) | AvdLee's original Swift Testing guidance; incremental XCTest coexistence |
| [Swift code reviewer](../../swift-code-reviewer.md) | Project-adapted Vinicius Carvalho review guide for changed files/specs |

## Example requests

- “Use swift-codebase-analysis for a read-only pre-release audit of this repository.”
- “Use swiftui-performance-audit to investigate photo-grid responsiveness; separate
  source hypotheses from measured results.”
- “Use swiftui-expert-skill to review this view's state ownership and API availability.”
- “Use swift-concurrency to review cancellation and account switching.”
- Claude Code: `/review` or `/review TCRoof/Auth/GoogleSession.swift`.

AGENTS.md defines project-specific overrides. Keep existing deployment targets,
Swift language mode, and XCTest conventions unless the user authorizes changes.
Liquid Glass is optional and requires an explicit request. Skill statements about
new SDKs/devices are not authoritative evidence of API availability.

## Sources and licenses

[sources.lock.json](sources.lock.json) records upstream repositories, exact revisions
for new imports, original paths, local content hashes, and license locations. Skill
files and references were copied from those revisions; their root MIT licenses were
retained. The pre-existing `swiftui-pro` installation is unchanged; its original
revision was not recorded, so the lock records that limitation rather than inventing
one. Its license is retained under `docs/licenses/agent-skills/`.

The existing root `skills-lock.json` remains the skills CLI's record for its earlier
`swiftui-pro` installation. The new imports are vendored, with provenance tracked
separately in `sources.lock.json`; do not assume `npx skills update` updates them.

The reviewer guide uses the upstream self-contained Codex template, with a short
project integration preamble. The Claude agent and `/review` command are local wrappers.
We did not duplicate the reviewer's companion bundle: its Swift Testing notice says
the original license was unknown, so testing guidance instead comes directly from
[AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill).

Additional discovery: [twostraws/Swift-Agent-Skills wiki](https://github.com/twostraws/Swift-Agent-Skills/wiki).
This directory is a curated reference, not an executable skill to install wholesale.
Use AvdLee's canonical repository, not the DexZane fork linked in the original list.

## Validation and updates

Run from the repository root:

```bash
python3 tools/agent-skills/verify.py
git diff --check
```

To update an import, fetch its recorded upstream repository into a temporary folder,
review the revision diff, then copy only that skill and its referenced resources.
Preserve license/NOTICE files. Update the revision and content hash in
`sources.lock.json`, review changed instructions for compatibility with AGENTS.md,
and rerun validation. For the reviewer guide, preserve the project preamble while
refreshing the upstream template. Do not edit vendored advice to apply local policy;
put overrides in AGENTS.md or the project-owned audit skills.

The SHA-256 digest is computed over files sorted by relative POSIX path, adding
`relative-path`, a NUL byte, file bytes, and a NUL byte for each file. For a single
file, use its basename. The verifier checks these hashes but deliberately never
rewrites the lock. Refresh a hash only after reviewing the intended content changes.
