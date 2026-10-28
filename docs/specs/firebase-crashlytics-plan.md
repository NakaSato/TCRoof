# Firebase Crashlytics integration plan

Status: planned, not implemented.

## Current project state

- `TCRoofApp.init()` already calls `FirebaseApp.configure()`.
- The Xcode project already uses Firebase's Swift Package Manager repository and links `FirebaseAuth` and `FirebaseFirestore`; `Package.resolved` currently pins Firebase iOS SDK 12.19.2.
- `TCRoof/GoogleService-Info.plist` is present. Confirm in Firebase Console that its registered Apple app matches `com.tcroof.internal` before relying on Crashlytics reports.
- The app target enables `ENABLE_USER_SCRIPT_SANDBOXING`. Debug uses `DEBUG_INFORMATION_FORMAT = dwarf`; Release uses `dwarf-with-dsym`. There is no Crashlytics build phase yet.

## Implementation steps

1. **Confirm the Firebase app.** In the existing Firebase project, verify Crashlytics is enabled for the Apple app registered with bundle ID `com.tcroof.internal`. Keep using the existing `GoogleService-Info.plist`; do not add a second `FirebaseApp.configure()` call. Firebase's setup guide covers console registration and SDK setup: [Crashlytics for Apple platforms](https://firebase.google.com/docs/crashlytics/ios/get-started).

2. **Add the SDK product.** Add `FirebaseCrashlytics` to the existing `firebase-ios-sdk` Swift package reference and link it to the `TCRoof` app target only. Preserve the current resolved SDK version unless a separate Firebase upgrade is intentionally reviewed.

3. **Upload symbols on every build.** Set Debug and Release `DEBUG_INFORMATION_FORMAT` to `dwarf-with-dsym`. Add Firebase's Crashlytics run script as the final app build phase:

   ```sh
   "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
   ```

   With user script sandboxing enabled, declare these input files:

   ```text
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist
   $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist
   $(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)
   ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}.debug.dylib
   ```

   The `.debug.dylib` input accounts for Xcode's debug dylib builds. Firebase documents the symbol script and sandbox inputs in [its dSYM setup guide](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports).

4. **Add small, privacy-safe context.** Use Crashlytics custom keys for non-identifying app context such as the active feature and sync phase, and concise logs for important navigation or sync transitions. Never attach email addresses, station/customer names, report contents, coordinates, document numbers, or tokens. Report only actionable, unexpected caught errors as non-fatals, with stable error categories and rate limiting; do not report routine offline or user-cancelled errors. Keep this instrumentation in a small diagnostics wrapper so feature code does not depend directly on Crashlytics.

5. **Decide whether Analytics is needed.** Do not add Google Analytics in the first pass. Crashlytics works without it; Analytics is an optional addition for automatic breadcrumb events. Add it only after deciding on analytics consent, disclosure, and data collection scope. See Firebase's [Crashlytics setup guide](https://firebase.google.com/docs/crashlytics/ios/get-started) for this distinction.

6. **Verify end to end.** Build Debug and Release for iPhone and iPad, confirm the Crashlytics script succeeds with sandboxing enabled, and inspect the generated dSYM UUIDs. Use a deliberately triggered `#if DEBUG` test crash on a developer device, relaunch to send the report, and verify the issue is symbolicated in the correct Firebase app. Remove or disable the test trigger before shipping. Then verify one representative non-fatal and confirm no sensitive context appears in the event.

## Acceptance criteria

- Fatal reports from both device families arrive in the intended Firebase app and show readable TCRoof frames.
- Debug and Release builds generate and upload the matching dSYMs, including the debug dylib symbol where produced.
- Non-fatal reports are limited to actionable unexpected failures, grouped with stable error categories, and contain no user or project identifying data.
- No duplicate Firebase configuration, additional Analytics dependency, or Crashlytics test trigger remains in Release.

## References

- [Get started with Crashlytics for Apple platforms](https://firebase.google.com/docs/crashlytics/ios/get-started)
- [Get readable Crashlytics reports with dSYMs](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports)
- [Customize Crashlytics reports for Apple platforms](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports)
