# Aiyifan iOS

Personal iOS client for Aiyifan (`https://m.yfsp.tv/`).

Developers and coding agents should read [DEVELOPMENT.md](DEVELOPMENT.md) before
changing navigation, playback, provider requests, persistence, or casting.

## What It Does

- Starts on an English native Home page for Movies, Series, Variety, and Anime while preserving provider titles and metadata in their original language.
- Uses the established Aiyifan folded-mark identity for the app icon, launch screen, in-app header, and Now Playing artwork.
- Fetches the latest signed Aiyifan category results and refreshes Home plus
  Saved on cold launch, after 15 minutes in the foreground, or on demand.
- Opens All as a native, pull-to-refresh catalog with 24-item pagination, score badges, Save/Favorite controls, and direct native playback.
- Keeps Home focused on discovery, with Continue Watching and New for You sections; filtering and sorting live in each native All catalog.
- Provides a collapsed global search that queries Aiyifan's signed catalog API and returns native, playable, saveable cards rather than filtering the small Home sample.
- Uses one compact poster-card system for Home, Search, Saved, All, and poster rails: a one-line title plus one episode/language/year detail row that never exposes opaque provider episode identifiers. Continue Watching and Played use the matching progress-row variant.
- Remembers independently selected filters, sort order, and sort direction for each category across navigation and app relaunches.
- Saves titles for later, checks every saved serial title when the app opens and daily in the background, and supports per-title update alerts with episode deep links. Player-discovered episodes update Saved immediately and never regress to an older partial response.
- Adds a Saved-only Ready to Watch queue above the unchanged Saved grid. It combines exact new episodes, genuinely unfinished Saved episodes, and manually pinned titles; users can reorder pins, dismiss entries, mark them watched, or play the exact episode.
- Resolves supported streams through one native `AVPlayerViewController`, whose system chrome owns play/pause, seeking, fullscreen, Picture in Picture, volume, and AirPlay. Aiyifan keeps only title navigation, episodes, quality/settings, Cast, and contextual playback prompts outside the video controls.
- Excludes separately supplied front advertisements from native and Cast playback queues while leaving the full program stream untouched.
- Lists multi-episode shows newest-first, autoplays the next episode, and remembers progress per episode.
- Starts a known latest episode immediately while its complete episode list retries independently up to four times.
- Always exposes Quality with Automatic preferring exact 1080p and falling back to the highest delivered rendition. Manual choices come only from actual provider playback sources and HLS/AVFoundation variants; catalog quality metadata never fabricates a resolution.
- Keeps every listed resolution enabled. Direct-source changes are staged before promotion, and a failed selection reports nonterminal feedback while preserving the active player, source, playback state, and progress.
- Keeps one player session alive when Back is tapped, with a video mini-player for browsing Home, Saved, Played, and All without interrupting playback.
- Continues audio while the screen is locked and provides playback speed, sleep timer, lock-screen Now Playing controls, interruption recovery, and transient-load retry.
- Offers local Skip Intro/Skip Outro suggestions for serial content, with an eight-second Undo and manual timing corrections. Learned fingerprints stay on device, never gate playback, and skip is always user-triggered rather than automatic.
- Provides a third Played tab with resume, watched/unwatched, restart, remove, filter, and clear controls.
- Supports AirPlay from AVPlayer's native controls plus Google Cast with persistent and expanded TV playback controls.
- Caches each feed independently, refreshes in the background, and optionally syncs Saved and Played through iCloud.
- Uses `WKWebView` only for the explicit website playback fallback.

## Build

```sh
pod install
xcodebuild -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Regression Tests

During implementation, run the affected unit/contract tests and the UI scenarios touched by the change. After a major refactor or before push/deployment, run the complete unit and UI suite once on a warmed simulator:

```sh
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES
```

The UI suite uses a deterministic local fixture. The 50-action power-user scenario is a release gate rather than a per-edit check. Release verification also loads all four live feeds, resolves a current movie and serial episode through the production API, and validates that both HLS manifests are reachable.

## Run On iPhone

1. Run `pod install`, then open `Aiyifan.xcworkspace` in Xcode.
2. Add your Apple ID in Xcode Settings > Accounts and select your team under Signing & Capabilities.
3. Connect and unlock the iPhone, then trust the Mac if prompted.
4. Select the iPhone as the run destination.
5. Press Run.

If Xcode says it cannot create a provisioning profile, keep the bundle id `com.john.aiyifan` or change it to a unique personal bundle id, then let Xcode manage signing automatically.
The installed Xcode version must also support the iOS version currently running on the phone so its developer disk image can mount.

Personal Team builds keep Saved, Played, progress, and settings locally but disable iCloud sync because Apple does not allow the iCloud entitlement on free provisioning profiles. To regenerate for an eligible paid team with iCloud enabled:

```sh
AIYIFAN_DEVELOPMENT_TEAM=<team-id> AIYIFAN_ICLOUD_ENABLED=1 ruby scripts/create_xcode_project.rb
pod install
```

## Notes

Background refresh timing is controlled by iOS. A cold launch refreshes Home and Saved; later foreground returns use a 15-minute freshness window, while daily background work remains a best-effort notification safety net. Background audio, Picture in Picture, notifications, iCloud, AirPlay, and Google Cast require physical-device verification. The iOS Simulator cannot discover or validate real receivers.
