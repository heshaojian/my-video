# Aiyifan iOS Wrapper Design

## Goal

Build a personal iOS app that opens `yfsp.tv` in a native shell so John can watch the site more comfortably on iPhone. The first version focuses on local sideloading, persistent login/session state, basic browser controls, and iOS media settings that make background audio and Picture in Picture possible when the website player supports them.

## Scope

- Native SwiftUI app named `Aiyifan`.
- App launches to a native latest-updates page for `电影`, `电视剧`, `综艺`, and `动漫`.
- The latest page fetches Aiyifan's embedded category feed data and displays poster rows.
- WKWebView loads the selected item or category section after the user taps it.
- Persistent cookies, local storage, and normal website login state are preserved by WebKit.
- Browser controls: back, forward, reload, home, and current loading progress.
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
- `WebView`: `UIViewRepresentable` bridge for `WKWebView`.
- `BrowserViewModel`: observable browser state such as loading progress and navigation availability.

This structure keeps native UI separate from WebKit setup and makes it easy to add share/open-url features later without touching app startup.

## Risks

Background playback and floating video are partly controlled by iOS and the website player. The app will enable the native capabilities Apple exposes, but if the embedded page suppresses PiP or stops playback when backgrounded, the first version will not override that behavior.

## Verification

- Build the app for an iOS simulator.
- Launch on simulator and confirm the native latest page shows the four requested sections.
- Confirm latest update posters and titles render from live Aiyifan data.
- Select an item or category and confirm the web view loads.
- Attempt device deployment when John's iPhone is available to Xcode.
