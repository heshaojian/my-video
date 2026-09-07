# Aiyifan iOS

Personal iOS client for Aiyifan (`https://m.yfsp.tv/`).

## What It Does

- Starts on a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- Fetches the latest embedded Aiyifan category feeds and shows poster rows for quick browsing.
- Saves titles for later in a persistent Saved library and supports removing them from either view.
- Resolves supported streams into native `AVPlayer` playback with Picture in Picture and background audio.
- Mutes front advertisements and restores the viewer's previous mute choice for the program.
- Lists multi-episode shows newest-first and remembers progress separately for each episode.
- Provides a third Played tab with resume, remove, and clear-history controls.
- Supports AirPlay to Apple devices and Google Cast to Chromecast and compatible Android TVs.
- Uses `WKWebView` only for explicit category browsing or the website fallback.

## Build

```sh
pod install
xcodebuild -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Regression Tests

Run the full unit and UI suite after every source change:

```sh
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES
```

The UI suite uses a deterministic local fixture. Release verification also includes loading the four live feeds and playing a real episode until its timeline advances.

## Run On iPhone

1. Run `pod install`, then open `Aiyifan.xcworkspace` in Xcode.
2. Add the Apple account for Team `VGGZ34H2PS` in Xcode Settings > Accounts if it is not already present.
3. Connect and unlock John's iPhone, then trust this Mac if prompted.
4. Select John's iPhone as the run destination.
5. Press Run.

If Xcode says it cannot create a provisioning profile, keep the bundle id `com.john.aiyifan` or change it to a unique personal bundle id, then let Xcode manage signing automatically.

## Notes

Background audio, Picture in Picture, AirPlay, and Google Cast require physical-device verification. The iOS Simulator cannot discover or validate real receivers.
