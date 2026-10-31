# Crashlytics for TCRoof

The iPhone and iPad use the same app target, bundle identifier and Firebase app.
`CrashReporting.configure()` runs immediately after Firebase initialization, before
creating the SwiftData container. Startup sync stages are recorded as breadcrumbs;
project contents and account details are not added to these logs.

The final app build phase uploads symbols using the Firebase Swift package.
Both build configurations generate dSYMs. The Debug input file list also includes
Xcode's debug dylib; Release disables that dylib and uses the shorter input list.
Keep these lists aligned with `ENABLE_DEBUG_DYLIB` when adding configurations.

To verify a new integration, temporarily add a DEBUG-only, explicitly triggered
fatal error after a short delay, launch without the debugger, and relaunch normally
to upload the report. Confirm the event in the Firebase Crashlytics dashboard,
then remove the temporary crash code before installing the final build.

Dashboard: https://console.firebase.google.com/project/tcroof-1564c/crashlytics
Apple SDK setup: https://firebase.google.com/docs/crashlytics/ios/get-started
