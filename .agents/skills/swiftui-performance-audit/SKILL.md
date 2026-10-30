---
name: swiftui-performance-audit
description: Audit SwiftUI responsiveness, invalidation, scrolling, images, memory, and background work with source citations, profiling plans, and prioritized P0–P3 recommendations. Analysis only unless fixes are requested.
---

# SwiftUI performance audit

Read AGENTS.md and establish the commit, scope, deployment target, Swift mode, actor
isolation settings, and available Apple tooling. Default to analysis only. Preserve the
working tree, existing framework choices, and deployment target unless edits are requested.

## Specialist references

From the repository root, load relevant portions of:

- `.agents/skills/swiftui-expert-skill/SKILL.md` and its performance/image/list references.
- `.agents/skills/swiftui-pro/SKILL.md`; use `references/performance.md` initially and
  `references/performance-plus.md` for this explicit deep-audit workflow as needed.
- `.agents/skills/swiftui-gotchas/SKILL.md` for applicable antipatterns.
- `.agents/skills/swift-concurrency/SKILL.md` for isolation, task ownership, and cancellation.

Treat these as review aids, not proof. Verify SDK-specific claims and inspect actual
call sites. Do not add Liquid Glass, rewrite architecture, or replace UIKit merely to
satisfy generic advice.

## Source investigation

1. Ask for the affected screen/workload when missing; meanwhile inspect its navigation,
   state ownership, queries, and representative data sizes. State any assumptions.
2. Trace SwiftUI dependencies and invalidation boundaries. Examine body-time filtering,
   sorting, formatting, geometry, identity churn, eager containers, nested scrolling,
   per-frame state writes, layout feedback, and work repeated by hidden screens.
3. Trace image decode/resize/encode and cache identity, costs, eviction, prefetching,
   duplicate requests, cancellation, and stale results. Inspect full-screen viewers too.
4. Inspect actor isolation of CPU and I/O work, synchronous persistence, export buffers,
   upload bodies, task fan-out, cooperative cancellation, and retained closures/observers.
5. Read relevant regression/performance tests and existing instrumentation. Cite the
   execution path, not just a suspicious API name. Do not assume async means off-main,
   repeated body evaluation means a redraw, NSCache is unlimited, or strong capture proves a leak.

## Measurement

For each hypothesis, define a repeatable workload, fixture size, baseline commit, device,
OS, configuration, and metric. Prefer physical-device Release measurements for resource
claims. Use Instruments Time Profiler/SwiftUI, Hangs, Allocations/Leaks, and signposts as
appropriate. Record cold versus warm runs and compare like-for-like medians/tails.
Use the project's existing budgets; label proposed thresholds as unmeasured targets.
Do not collect personal data or credentials in traces.

If Apple tools or a suitable device are unavailable, give exact profiling/reproduction
steps and mark findings as source hypotheses. Do not claim FPS, memory savings, leaks,
or speedups without measurements. Portable microbenchmarks and syntax checks do not
establish on-device responsiveness. Run only relevant checks within the user's scope.

## Report contract

Start with a 5–10 line executive summary and validation limits. Organize the investigated
areas with **Findings**, **Risks**, and **Recommendations**. Each finding includes:

- File:line and the actual execution/invalidation path.
- Evidence category: measured, source-confirmed behavior, or hypothesis requiring profiling.
- Trigger, affected scale, metric/evidence, and confidence.
- Smallest justified change and a before/after validation plan.

Include quick wins (each less than one day) and strategic refactors. End with:

| Priority (P0–P3) | Issue | Location | Effort (S/M/L) | Suggested fix |
| --- | --- | --- | --- | --- |

Use P0 only for confirmed critical failures; P1 for high-impact hangs, terminations, or
correctness risks; P2 for meaningful responsiveness/memory issues; P3 for smaller
improvements. Do not promote an unmeasured optimization to a confirmed release blocker.
