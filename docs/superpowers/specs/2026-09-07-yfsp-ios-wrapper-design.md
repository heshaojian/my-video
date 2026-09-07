# Aiyifan iOS Wrapper Design

## Goal

Build a personal iOS app that makes the latest `yfsp.tv` updates easy to find, save, and watch on iPhone. The app must provide a focused four-category home screen, persistent Save for Later/Favorites, reliable in-app playback, and the iOS media configuration needed for background audio and Picture in Picture when the website player supports them.

## Scope

- Native SwiftUI app named `Aiyifan`.
- App launches to a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- The latest page fetches Aiyifan's embedded category feed data and displays poster rows.
- Each latest item has a clearly accessible Save for Later/Favorite control.
- Saved items persist across app launches and can be browsed from a dedicated Saved view.
- Removing a saved item immediately updates both Home and Saved views.
- WKWebView loads the selected item or category section after the user taps it.
- Persistent cookies, local storage, and normal website login state are preserved by WebKit.
- Browser controls: back, forward, reload, home, and current loading progress.
- Loading UI must never prevent the user from tapping website playback controls.
- Playback-friendly WebKit configuration:
  - inline video playback allowed
  - user action not required for media playback after page interaction
  - Picture in Picture allowed
  - AirPlay allowed
- Background audio mode declared in `Info.plist`.
- App configures `AVAudioSession` for playback.
- Local deployment through Xcode/dev signing.

## Non-Goals

- No content scraping, downloading, mirroring, or ad skipping.
- No bypass of site restrictions, DRM, login, geo-blocking, or copyright controls.
- No App Store publishing.
- No custom video extractor in the first version.

## Architecture

The app is intentionally small:

- `AiyifanApp`: SwiftUI entry point and app-wide audio session setup.
- `BrowserView`: SwiftUI wrapper around the native category landing screen, web experience, and toolbar.
- `AiyifanCategory`: section definitions and destination URLs.
- `AiyifanFeedService`: fetches category pages and decodes the embedded latest update feed.
- `AiyifanItem`: native model for latest update cards.
- `SavedItemsStore`: persists saved items as JSON in `UserDefaults` and publishes immutable snapshots to the UI.
- `WebView`: `UIViewRepresentable` bridge for `WKWebView`.
- `BrowserViewModel`: observable browser state such as loading progress and navigation availability.

This structure keeps native UI separate from WebKit setup and makes it easy to add share/open-url features later without touching app startup.

## Risks

Background playback and floating video are partly controlled by iOS and the website player. The app will enable the native capabilities Apple exposes, but if the embedded page suppresses PiP or stops playback when backgrounded, the first version will not override that behavior.

## Verification

Every code change must pass the following regression gate before it is committed:

1. Build the app for the iPhone 17 Pro simulator.
2. Run unit tests for URL normalization and saved-item persistence.
3. Run UI tests for the four latest sections, saving/removing an item, and opening an item in the WebView.
4. Launch with live data and confirm posters and titles render for all four categories.
5. Open a current `电视剧` item, start playback, and confirm the playback time advances.
6. Verify returning Home preserves the latest feed and saved state.
7. Verify background audio and Picture in Picture on a physical iPhone when it is paired with Xcode; Simulator results alone are not considered final for these two OS features.
