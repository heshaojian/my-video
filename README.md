# YFSP iOS

Personal iOS wrapper for `https://m.yfsp.tv/`.

## What It Does

- Starts on a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- Fetches the latest embedded YFSP category feeds and shows poster rows for quick browsing.
- Opens the selected YFSP item or category section in a native `WKWebView`.
- Keeps normal WebKit website data such as cookies and login state.
- Provides back, forward, home, reload, and open-in-Safari controls.
- The home control returns to the native latest-updates page.
- Enables inline playback, AirPlay, Picture in Picture support, and background audio mode where iOS and the website player allow it.

## Build

```sh
xcodebuild -project YFSP.xcodeproj -scheme YFSP -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath DerivedData build
```

## Run On iPhone

1. Open `YFSP.xcodeproj` in Xcode.
2. Add the Apple account for Team `VGGZ34H2PS` in Xcode Settings > Accounts if it is not already present.
3. Connect and unlock John's iPhone, then trust this Mac if prompted.
4. Select John's iPhone as the run destination.
5. Press Run.

If Xcode says it cannot create a provisioning profile, keep the bundle id `com.john.yfsp` or change it to a unique personal bundle id, then let Xcode manage signing automatically.

## Notes

Background audio and floating Picture in Picture are enabled at the app level, but final behavior depends on the embedded website's video player.
