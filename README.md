# Aiyifan iOS

Personal iOS client for Aiyifan (`https://m.yfsp.tv/`).

## What It Does

- Starts on a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- Uses the established Aiyifan folded-mark identity for the app icon, launch screen, in-app header, and Now Playing artwork.
- Fetches the latest embedded Aiyifan category feeds and shows poster rows for quick browsing.
- Opens `全部` as a native, pull-to-refresh catalog with 24-item pagination, Save/Favorite controls, and direct native playback.
- Searches and filters the native library, with Continue Watching and New for You sections.
- Saves titles for later, detects new episodes, and supports per-title update alerts.
- Resolves supported streams into native `AVPlayer` playback with Picture in Picture and background audio.
- Mutes front advertisements and restores the viewer's previous mute choice for the program.
- Lists multi-episode shows newest-first, autoplays the next episode, and remembers progress per episode.
- Continues audio while the screen is locked and provides playback speed, sleep timer, lock-screen Now Playing controls, interruption recovery, and transient-load retry.
- Provides a third Played tab with resume, watched/unwatched, restart, remove, filter, and clear controls.
- Supports AirPlay plus Google Cast with persistent and expanded TV playback controls.
- Caches each feed independently, refreshes in the background, and optionally syncs Saved and Played through iCloud.
- Uses `WKWebView` only for the explicit website playback fallback.

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

The UI suite uses a deterministic local fixture. Release verification also loads all four live feeds, resolves a current movie and serial episode through the production API, and validates that both HLS manifests are reachable.

## Run On iPhone

1. Run `pod install`, then open `Aiyifan.xcworkspace` in Xcode.
2. Add `heshaojian@outlook.com` in Xcode Settings > Accounts. The generated project defaults to Personal Team `GM4SSCNNUK`.
3. Connect and unlock John's iPhone, then trust this Mac if prompted.
4. Select John's iPhone as the run destination.
5. Press Run.

If Xcode says it cannot create a provisioning profile, keep the bundle id `com.john.aiyifan` or change it to a unique personal bundle id, then let Xcode manage signing automatically.
The installed Xcode version must also support the iOS version currently running on the phone so its developer disk image can mount.

Personal Team builds keep Saved, Played, progress, and settings locally but disable iCloud sync because Apple does not allow the iCloud entitlement on free provisioning profiles. To regenerate for an eligible paid team with iCloud enabled:

```sh
AIYIFAN_DEVELOPMENT_TEAM=<team-id> AIYIFAN_ICLOUD_ENABLED=1 ruby scripts/create_xcode_project.rb
pod install
```

## Notes

Background audio, Picture in Picture, notifications, iCloud, AirPlay, and Google Cast require physical-device verification. The iOS Simulator cannot discover or validate real receivers.
