# Offline layout regression tests

`seafileLayoutTests` runs inside the app and loads its actual storyboards and
controllers. It needs no server or account and performs no login or upload.

Use a **dedicated simulator**: Xcode installs the test host app on the destination.
Do not point this command at a simulator containing your regular app data.

```sh
xcodebuild -workspace seafilePro.xcworkspace -scheme seafileLayoutTests \
  -configuration Debug -destination 'platform=iOS Simulator,id=TEST_SIMULATOR_UDID' \
  -derivedDataPath /tmp/seafile-layout-derived CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO test
```

The suite checks iPad portrait/landscape and compact/regular transitions, column
identity and back navigation, preview accessibility targets, fixed list and
settings fonts, Dynamic Type in the grid, and native action-sheet anchoring.
Screenshots are attached to the XCTest results. Compact layouts are exercised
through container size and trait overrides. Actual window dragging, hardware
keyboard, and VoiceOver still need device-level acceptance testing.
