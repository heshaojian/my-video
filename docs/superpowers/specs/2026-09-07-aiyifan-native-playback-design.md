# Aiyifan Native Playback Design

## Goal

Replace webpage playback for Latest and Saved cards with Apple's native media player. Tapping a content card must start a native playback experience and must never silently navigate to an HTML page.

## Product Behavior

- Latest and Saved cards open a native player immediately.
- The player displays the title, standard transport controls, loading state, and actionable failure state.
- Picture in Picture, AirPlay, background audio, system Now Playing controls, and rotation use AVKit and AVFoundation behavior.
- The category `全部` command may continue opening the Aiyifan category webpage because it is a browsing action, not a playback action.
- If native playback fails, the app displays `Retry` and `Open Website`. The website fallback only opens after the user explicitly selects it.
- Returning from the player preserves the loaded latest feed, current scroll context where SwiftUI retains it, and Saved state.

## Architecture

### Media Model

`AiyifanItem` decodes the feed's `rtmp` field as its native stream URL. Production media URLs must use HTTPS. Local file URLs are permitted only for deterministic UI test fixtures.

The existing webpage URL remains available solely for the explicit fallback command.

### Navigation State

`BrowserViewModel` distinguishes three states:

1. Library: native Latest and Saved tabs.
2. Player: a selected `AiyifanItem` shown through AVKit.
3. Browser: category browsing or an explicitly requested website fallback.

Selecting a card enters Player. Selecting `全部` enters Browser. Selecting `Open Website` from a failed player enters Browser.

### Native Player

`NativePlayerViewModel` owns an `AVPlayer`, observes item readiness and failure, and exposes loading, playing, and error state. It creates a fresh player item for Retry and releases observers and playback when dismissed.

`AVPlayerViewController` is wrapped for SwiftUI and configured to allow Picture in Picture, including automatic PiP when moving to the background where iOS permits it. The existing playback audio session and background mode remain enabled.

### Error Handling

- Missing, malformed, non-HTTPS, or unsupported production stream URLs fail before opening the player.
- Network and media decoding errors produce a readable failure screen rather than an indefinite spinner.
- Retry creates a new `AVPlayerItem` from the original stream URL.
- The app does not attempt to bypass DRM, authorization, regional restrictions, or provider access controls.

## Test Contract

The regression gate after every source change remains mandatory.

### Unit Tests

- Decode and normalize native HLS stream URLs.
- Reject missing, malformed, and insecure production stream URLs.
- Preserve webpage fallback URLs separately from media URLs.
- Verify Player, Browser, and Library state transitions.
- Verify Retry creates fresh playback state without losing the selected title.

### UI Tests

- Every requested category appears on Latest.
- Tapping a Latest card opens the native player and no WebView exists.
- Tapping a Saved card opens the native player and no WebView exists.
- Saving multiple items, removing them from both surfaces, and relaunch persistence work.
- Native failure exposes Retry and Open Website; only Open Website creates a WebView.
- Repeated open, close, and alternate-title playback remains stable.

### Power-User Verification

- Test on iPhone 16e and iPhone 17 Pro simulators in portrait and landscape.
- Load all four live feeds and play at least one current HLS stream through AVKit.
- Confirm playback time advances and that the HTML page never appears after a card tap.
- Exercise Home, category browsing, explicit fallback, rapid repeated navigation, foreground/background transitions, and saved-item relaunch persistence.
- Confirm PiP, lock-screen controls, background audio, and AirPlay on a paired physical iPhone; simulator results do not replace this device check.

## Scope Boundary

This change replaces the playback path only. It does not recreate Aiyifan's complete website, bypass advertisements or access controls, add downloads, or add account synchronization.
