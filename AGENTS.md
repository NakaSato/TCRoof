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
