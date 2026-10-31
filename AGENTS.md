# Repository Guidelines

## Project Structure & Module Organization

`TCRoof/` contains the iOS app, organized by feature (for example `Views/Install`, `Survey`, `Sync`, and `Models`); app images and colors live in `Assets.xcassets`. `TCRoofKit/` is the reusable Swift package, with modules under `Sources/` and tests under `Tests/`. `TCRoofUITests/` contains Xcode UI automation. Firebase Cloud Functions are in `functions/`, with Firestore security rules tests in `tools/firestore-rules-tests/`. Supporting scripts and utilities live in `tools/`; specifications and design references live in `docs/`.

## Build, Test, and Development Commands

- Open `TCRoof.xcodeproj` in Xcode and use the shared `TCRoof` scheme to build and run the app.
- `swift test` from `TCRoofKit/` runs the package tests on macOS.
- `tools/linux-swift/test.sh` runs the supported Swift package tests on Linux; pass `--filter TestName` to select tests or `--build-only` to compile.
- `npm install && npm test` from `functions/` compiles and runs Cloud Functions tests.
- `npm install && npm test` from `tools/firestore-rules-tests/` runs rules tests using the Firebase emulator.

## Coding Style & Naming Conventions

Follow the surrounding code when editing. Use four spaces for Swift and JavaScript/TypeScript indentation. Keep Swift type and protocol names in `UpperCamelCase`, members in `lowerCamelCase`, and group app code by feature. Name UI test files and classes with the `*UITests` suffix; keep package test names descriptive and consistent with their module. TypeScript is compiled with `tsc`; no repository-wide formatter or linter is configured, so avoid unrelated formatting changes.

## Testing Guidelines

Add or update the closest relevant test when changing behavior: Swift package tests for reusable logic, `TCRoofUITests/` for user flows, and `functions/src/*.test.ts` or `tools/firestore-rules-tests/rules.test.js` for backend behavior and access rules. Run the focused test command first, then broader suites when practical. No coverage threshold is configured. UI tests require an Xcode simulator; emulator-based rules tests require the Firebase CLI.

## Commit & Pull Request Guidelines

Recent commits use imperative summaries, often prefixed by an area (for example, `PWA home: ...`, `Install tracking: ...`, or `Design: ...`). Keep subjects concise and describe the user-visible change. Pull requests should explain the behavior and affected area, list validation performed, link related issues when applicable, and include screenshots for UI changes. Call out configuration or Firestore rules changes explicitly.

## Security & Configuration

Keep credentials and local secrets out of commits. Use `Secrets.example.xcconfig` as the configuration template; `Secrets.xcconfig`, `.env` files, and Firebase emulator state are local-only. Review `firestore.rules` changes alongside corresponding rules tests.

## Swift Review Skills

Project-local skills are in `.agents/skills/`, with aliases in `.claude/skills/`. See
`.agents/skills/README.md` for usage, provenance, licenses, and update instructions.

- Whole-codebase reports: use `swift-codebase-analysis` (ten sections, cited evidence, P0–P3 actions).
- Deep responsiveness/memory reviews: use `swiftui-performance-audit`.
- SwiftUI implementation/API checks: use `swiftui-expert-skill`; use `swiftui-pro` for
  complementary navigation, accessibility, localization, and composition checks.
- Cross-check relevant antipatterns with `swiftui-gotchas`; use `swift-concurrency` for
  async lifecycles and isolation, and `swift-testing-expert` for test design.
- Change/spec reviews: read `swift-code-reviewer.md`; Claude Code also has `/review`
  and an explicitly invokable `swift-code-reviewer` agent.

Read only references relevant to the task. Project settings and user instructions take
precedence over generic skill defaults. The app currently targets iOS 18; the package
declares iOS 17/macOS 14, uses Swift 6.2 tooling, and retains Swift 5 language mode.
Verify these settings before giving version-specific advice. Verify newer API claims
against the selected SDK or official Apple documentation; use availability guards when
needed. Do not raise deployment targets, change Swift mode, mandate an architecture,
migrate XCTest suites, or adopt Liquid Glass unless the requested work requires it.
Existing XCTest conventions remain valid; keep UI automation in XCTest. Third-party
skills may mention optional tools/commands such as `/verify-ios`; if unavailable, use
the repository's documented checks and state what remains unverified. Do not install
tools or request interactive login just to satisfy an optional skill dependency.
Audits are read-only unless edits are requested. Cite file:line evidence, separate
measured results from source hypotheses, and never present Linux tests or parsing as
Apple SDK, simulator/device, SwiftData, or Firebase integration validation.
