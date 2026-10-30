---
name: swift-codebase-analysis
description: Analyze a Swift repository for onboarding, refactor planning, release readiness, or technical debt and produce an evidence-based report with file and line citations and P0–P3 actions. Analysis only unless the user requests edits.
---

# Swift codebase analysis

Read the repository's `AGENTS.md` first. Treat the user's context fields as placeholders
until verified from the project. Default to a read-only review; do not fix code, install
dependencies, change instructions, commit, or publish the report unless requested.

## Explore before judging

1. Record the commit, branch, working-tree state, review scope, and available toolchain.
2. Inspect Package.swift, Xcode targets/configurations/schemes, both lockfiles, Info.plist,
   entitlements, privacy manifests, resources, tests, CI, and repository instructions.
3. Establish actual application and package deployment targets independently. Check Swift
   language mode, strict-concurrency settings, and default actor isolation before applying advice.
4. Read the implementation and relevant tests. Trace representative flows from navigation
   through state, persistence, networking, authentication, and account teardown.
5. Cite repository paths and line numbers for every concrete finding. Distinguish a verified
   defect, a source-level risk, a measurement hypothesis, and an unanswered question.
   For an absent file/configuration, identify the search scope and cite the related usage;
   do not fabricate a file/line for an absence. Do not print credentials or personal data.

## Load specialist guidance selectively

Resolve paths from the repository root. Read only references relevant to the review:

- SwiftUI correctness and API checks: `.agents/skills/swiftui-expert-skill/SKILL.md`.
- Navigation, accessibility, localization, and composition: `.agents/skills/swiftui-pro/SKILL.md`.
- Antipattern cross-checks: `.agents/skills/swiftui-gotchas/SKILL.md`.
- Actors, Sendable, cancellation, and async lifecycles: `.agents/skills/swift-concurrency/SKILL.md`.
- Test design and migration options: `.agents/skills/swift-testing-expert/SKILL.md`.
- Change/spec review: `swift-code-reviewer.md`.
- Deep performance work: `.agents/skills/swiftui-performance-audit/SKILL.md`.

Project facts and user scope override generic recommendations. Check version-specific
claims against the selected SDK or authoritative Apple documentation. Do not infer that
an async function blocks the UI, every strong capture leaks, or every force unwrap crashes.
Do not mandate an architecture, Swift Testing migration, or Liquid Glass adoption.

## Required report

Start with a 5–10 line executive summary. State scope and validation limits. Include these
ten sections, each with **Findings** (file:line evidence), **Risks**, and **Recommendations**:

1. **Overview:** purpose, features, targets/extensions/widgets, frameworks, dependencies,
   resolved versus allowed versions. Claim a dependency is outdated only after checking upstream.
2. **Architecture:** actual patterns and consistency, modules/layers/dependency direction,
   navigation/routing, dependency injection and global services.
3. **State & Data Flow:** Observation/Combine/property wrappers, persistence/migrations/recovery,
   API boundaries, errors, account isolation, refresh, retries, pagination, and caches.
4. **Concurrency:** async/await, actors, Task ownership/cancellation, GCD/Combine,
   MainActor, Sendable, reentrancy, stale publication, and Swift 6 readiness.
5. **Code Quality:** naming/API design, force operations and their actual preconditions,
   large types, duplication/dead code evidence, errors/logs, captures and observer teardown.
6. **Performance:** UI work, invalidation, lists/identity, images, allocations, I/O, and caches.
   Separate source hypotheses from measured regressions.
7. **Security & Privacy:** credential storage, bundle-extractable values, trust/ATS,
   sensitive logs, auth/biometrics if present, privacy declarations and required-reason APIs.
8. **Testing:** critical-path tests, mocks/isolation, integration gaps and flakiness.
   Test-file counts are not coverage percentages; historical test results are not current results.
9. **Build, CI & Tooling:** schemes/configurations, lint/format, automation, compiler diagnostics,
   deprecated API and toolchain/runtime compatibility. Identify checks actually executed.
10. **Accessibility & Localization:** Dynamic Type, VoiceOver, focus, contrast, Reduce Motion,
    touch targets, string resources, pluralization and locale-aware formatting.

If authorized and available, run focused checks that do not alter tracked files; record
commands, results, and skipped checks. Never substitute Linux tests or syntax parsing for
an Apple SDK build, simulator/device testing, or actual Firebase/SwiftData integration.

Include quick wins (each less than one day) and strategic refactors. End with:

| Priority (P0–P3) | Issue | Location | Effort (S/M/L) | Suggested fix |
| --- | --- | --- | --- | --- |

P0: confirmed critical exposure/data loss or release-stopping failure requiring immediate
action. P1: high-impact correctness/security/release risk. P2: meaningful reliability,
performance, accessibility, or maintenance issue. P3: lower-impact improvement.
Do not invent findings to fill a priority or section. State uncertainty explicitly.
