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
On iPhone it also checks all five storyboard Tab navigation controllers: pushed
pages hide the tab bar, multi-level returns and batch-created directory paths
keep it hidden, and returning to a root or switching tabs restores the correct
visibility. The file-list fixture checks the hidden bar leaves no bottom inset
and the last row remains fully visible above the home indicator.
Offline iPhone search fixtures open the real search controller without submitting
a query: root search hides tabs, repeated custom and system dismissals restore
the selected stack's visibility, and directory search keeps tabs hidden until
returning to the root. Inactive search cancellation and dismissal callbacks also
check that they cannot restore tabs owned by a different active search.
The search fixture also checks that dismissing only the keyboard keeps tabs
hidden and that opening a result directory transfers visibility through the
pending asynchronous push before restoring tabs on return to the root.
Screenshots are attached to the XCTest results. Compact layouts are exercised
through container size and trait overrides. Actual window dragging, hardware
keyboard, and VoiceOver still need device-level acceptance testing.
