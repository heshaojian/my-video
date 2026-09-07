# Aiyifan iOS

Personal iOS wrapper for `https://m.yfsp.tv/`.

## What It Does

- Starts on a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- Fetches the latest embedded Aiyifan category feeds and shows poster rows for quick browsing.
- Saves titles for later in a persistent Saved library and supports removing them from either view.
- Opens the selected Aiyifan item or category section in a native `WKWebView`.
- Keeps normal WebKit website data such as cookies and login state.
- Provides back, forward, home, reload, and open-in-Safari controls.
- The home control returns to the native latest-updates page.
- Enables inline playback, AirPlay, Picture in Picture support, and background audio mode where iOS and the website player allow it.

## Build

```sh
xcodebuild -project Aiyifan.xcodeproj -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath DerivedData build
```

## Regression Tests

Run unit and UI tests separately with parallel testing disabled. This avoids an Xcode 26 simulator-clone crash seen when both targets are launched together.

```sh
xcodebuild -project Aiyifan.xcodeproj -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath DerivedData -parallel-testing-enabled NO -only-testing:AiyifanTests test
xcodebuild -project Aiyifan.xcodeproj -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath DerivedData -parallel-testing-enabled NO -only-testing:AiyifanUITests test
```

The UI suite uses a deterministic local fixture. Release verification also includes loading the four live feeds and playing a real episode until its timeline advances.

## Run On iPhone

1. Open `Aiyifan.xcodeproj` in Xcode.
2. Add the Apple account for Team `VGGZ34H2PS` in Xcode Settings > Accounts if it is not already present.
3. Connect and unlock John's iPhone, then trust this Mac if prompted.
4. Select John's iPhone as the run destination.
5. Press Run.

If Xcode says it cannot create a provisioning profile, keep the bundle id `com.john.aiyifan` or change it to a unique personal bundle id, then let Xcode manage signing automatically.

## Notes

Background audio and floating Picture in Picture are enabled at the app level, but final behavior depends on the embedded website's video player. Verify both on a paired physical iPhone before relying on them.
