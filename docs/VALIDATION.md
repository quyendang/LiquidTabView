# Validation

Distribution dated October 30, 2026. The Swift and Kotlin files are unchanged from the components integrated and tested in the demo apps.

## Builds and automated checks

- Xcode builds succeeded for iOS Simulator and generic iOS devices. The device build used disabled code signing; it is not an IPA ready to install on a physical iPhone.
- Swift motion checks passed: 12 transition directions, continuous retargeting, press/release/cancel, 2–5 tabs, input sampling at 30/60/120 Hz, and Reduce Motion.
- Android: `:app:testDebugUnitTest :app:assembleDebug --offline` succeeded, with eight tests and no failures or errors.
- The demo APK was installed on a Pixel 7 and Pixel 10 Emulator.
- The iOS app has no external `default.metallib`; its embedded shader ran on iOS 26.3 and iOS 27 Simulators.

## Layouts and interactions

- Both platforms: selected the last tab in six configurations — 4, 3, or 2 tabs with an action button, and 3, 2, or 5 tabs without one. The [iOS](media/ios-layouts.jpg) and [Android](media/android-layouts.jpg) screenshots were captured after the animation settled.
- README videos were recorded from the packaged components: iOS 27 in Coral/light mode and Android 17 in Coral/dark mode.
- iOS: hold, swipe across distant tabs, return, and tap to select. Android: drag for 1.8 seconds in each direction from Home to Account and back.
- On iOS 26.3, the separate action button was also tested after switching tabs. Pages in the recordings use sample data.

## Not yet verified

- FPS, jank, and latency have not been measured with Instruments or Macrobenchmark.
- Physical iPhone execution and visual QA of the Android API 31–32 fallback remain outstanding.
- The demo environment's XCTest UI runner failed to start; that suite is not counted as passing. The UI checks above used device interactions and recording review.
- RTL layouts do not automatically mirror; tabs follow the supplied list from left to right.
- Swift preserves each tab's view tree. Compose preserves saveable state; plain `remember` state is not retained when a page leaves composition.

These results come from the integration demos, not from CI running in this repository.
