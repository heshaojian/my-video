# Aiyifan Continuous Playback, Quality, Episode Recovery, and Saved Updates Design

Date: 2026-09-07

## Objective

Make native playback behave like a durable app session rather than a modal screen. Viewers can choose a video resolution, return to the library without stopping playback, recover complete episode lists when the provider is temporarily incomplete, and receive best-effort daily notifications when saved serial titles add episodes.

This work preserves the existing native `AVPlayer`, AirPlay, Google Cast, Picture in Picture, background audio, lock-screen controls, Played progress, newest-first episode display, provider-content language, and validated provider boundaries.

## Decisions

- The initial preferred quality is 1080p. If an exact 1080p variant is unavailable, use the highest available resolution.
- A manual quality choice is remembered for future videos. If that choice is unavailable for a title, use the highest available resolution at or below the preference; if none exists, use the highest available variant.
- Back collapses an active session into a visible video mini-player above the library tab bar. It does not stop playback.
- A serial title with a known latest episode key may begin that episode while the complete episode list retries independently.
- Episode-list loading receives four total attempts with bounded increasing delays.
- Saved-title checks run at most once per day through best-effort iOS background refresh and an overdue foreground catch-up.
- This release remains local-only. Exact-time daily delivery is not promised because iOS schedules `BGAppRefreshTask` opportunistically.

## Considered Approaches

### Recommended: Native Shared Session and AVFoundation Variant Preferences

Keep one app-owned playback session alive across full-player and mini-player presentations. Use AVFoundation's HLS variant metadata to discover resolutions, and use `AVPlayerItem.preferredMaximumResolution` plus the matching peak bitrate as native selection preferences.

This approach preserves adaptive streaming, audio tracks, subtitles, AirPlay, Picture in Picture, and the current playback pipeline. It also avoids rewriting provider playlists.

### Minimal View-Level Patch

Keep the player owned by `NativePlayerScreen`, add a quality menu, and hide the screen when Back is tapped. This is smaller but SwiftUI can destroy the view and its `AVQueuePlayer`, so playback continuity remains fragile. It does not satisfy the browsing requirement reliably.

### Forced Rendition URLs

Parse the HLS master playlist and replace the master URL with a specific media-playlist URL. This can force a rendition but risks losing alternate audio/subtitle groups and duplicates protocol parsing that AVFoundation already performs. It is not selected.

## Playback Session Architecture

Introduce a `PlaybackSessionController` owned by `BrowserView`. It owns the active `NativePlayerViewModel`, selected item, presentation state, and explicit stop/replace commands.

The session has these presentation states:

- `inactive`: no player or mini-player.
- `expanded`: full native player is visible.
- `collapsed`: library or catalog is visible and the mini-player is visible.

Presentation changes never recreate the player. The full player and mini-player receive the same session-owned view model and `AVQueuePlayer`.

Commands behave as follows:

- Back from the player persists progress and changes `expanded` to `collapsed`.
- Tapping the mini-player changes `collapsed` to `expanded` without seeking or resolving again.
- Close explicitly persists progress, stops local playback, clears Now Playing, and disconnects the app-owned playback plan. It does not force-disconnect an independently active receiver session.
- Selecting another title persists the current title, cancels its obsolete resolver work, and replaces the session with the selected title.
- Navigating among Latest, Saved, Played, and native All catalogs does not affect playback.
- Website fallback remains a deliberate terminal action that stops native playback before opening the provider page.

The mini-player sits above the tab bar or the bottom edge of the native catalog. It contains a stable video/artwork region, title, optional provider episode name, Play/Pause, Expand, and Close. It uses compact controls and does not contain explanatory text.

## Resolution Discovery and Selection

Add an immutable `PlaybackQualityOption` projection containing display height, presentation size, average bitrate, peak bitrate, and a stable identifier. Load `AVURLAsset` variants asynchronously after the program asset resolves. Reject variants with non-finite or nonpositive dimensions or bitrates, deduplicate equivalent display heights, and sort choices highest-first.

Display common labels from vertical resolution, such as 480p, 720p, 1080p, 1440p, and 2160p. Provider labels are not synthesized when AVFoundation exposes no trustworthy video dimensions.

Selection rules:

1. On first launch, target an exact 1080p variant.
2. If 1080p is unavailable, select the highest valid variant.
3. After a manual selection, persist its target height in versioned `UserDefaults`.
4. For a later title without that exact height, choose the highest variant not exceeding the target; if none exists, choose the highest variant.
5. A single-rendition asset uses that rendition and hides the Quality submenu.
6. A stream whose variants cannot be loaded continues in AVFoundation automatic mode and hides the unavailable choices.

Apply the selected option to every program `AVPlayerItem` before insertion. Changing quality updates the current and queued program items in place, preserves playback time and rate, and does not create a new Played record. AVFoundation may temporarily use a lower rendition when bandwidth is insufficient; the UI describes the selected preference, not a guaranteed instantaneous network rendition.

AirPlay follows the same `AVPlayerItem` preferences. Google Cast continues to receive the validated HLS master URL, and its Default Media Receiver retains final adaptive-bitrate control. The quality menu must not claim that a Cast receiver is locked to the iPhone preference.

## Episode Reliability

Separate episode-list recovery from program-URL resolution. Serial intent is true when any trusted app/provider signal indicates serial content:

- Provider detail reports serial content.
- The catalog item has `isSerial == true`.
- The item has a valid latest episode key.
- The item's validated top-level category is Series, Variety, or Anime.

When a valid preferred or latest episode key is already available, resolve and start that episode while the complete playlist loads. Never substitute the first provider response entry merely because the list is incomplete.

The playlist loader makes four total attempts with delays of 0, 0.5, 1.5, and 3 seconds. It retries transient transport failures, invalid/empty playlist envelopes, and a partial list that does not contain the expected latest episode key. It does not retry login-required, preview-only, unsupported-host, invalid-identifier, or cancellation errors.

When recovery succeeds:

- Publish the complete newest-first episode list.
- Match the active media key to its episode without replacing the playing item.
- Enable episode navigation and autoplay boundaries.
- Preserve the current timestamp, play/pause state, AirPlay route, and Cast handoff.

If all attempts fail but a trusted episode key is already playing, keep playback active and show `Retry Episodes` from the episode control. If no trustworthy episode key exists, do not silently play episode 1; show a recoverable episode-loading error before playback starts.

Every retry task is cancelable. Results from a prior title or episode generation are ignored.

## Daily Saved-Title Updates

Add a `SavedUpdateChecker` that checks saved titles directly instead of relying only on the first eight Latest results. It reuses one short-lived provider certificate, fetches detail metadata, and fetches the episode playlist for serial content. Requests use the existing HTTPS host allowlist, response-size limits, signed request builder, and identifier validation.

The checker compares the newest validated episode against the stored per-title baseline:

- The first successful check establishes a baseline and sends no notification.
- A strictly newer episode updates the saved item's latest metadata and creates one notification candidate.
- Repeated checks for the same latest episode are deduplicated.
- Per-title alert preferences and the global update-alert setting remain authoritative.
- A failed title remains unchanged and can retry later; successful titles in the same batch are retained.
- Removed saved titles are excluded even if an obsolete request finishes later.

Use bounded concurrency of three titles and honor task cancellation/expiration. Persist the last completed check date and sanitized per-title result state. A partially completed background run does not advance the global completed-check date, allowing an overdue foreground catch-up to finish the work.

`BackgroundRefreshScheduler` requests the next run no earlier than 24 hours after the last completed check. Because `earliestBeginDate` is not an execution guarantee, app activation starts one catch-up check when the last completed check is older than 24 hours. Concurrent background and foreground checks coalesce into one operation.

Settings shows `Last checked`, `Check Now`, current notification permission, and a concise partial-failure result. `Check Now` is disabled while a check is active. Notification deep links continue to open the corresponding saved title and latest known episode.

## Failure and Security Behavior

- Do not log or persist signed URLs, provider certificates, cookies, or HLS payloads.
- Reject private-network, non-HTTPS, credential-bearing, oversized, unsupported-host, and malformed media resources.
- Variant discovery failure never blocks otherwise valid playback.
- Quality changes that cannot be applied retain the current playable item and show a short nonterminal error.
- Episode retries are bounded and never retry authentication or validation failures.
- Daily checks isolate title failures and never delete a saved item or regress its latest episode metadata.
- Stale asynchronous results cannot replace a newer playback session or saved-item state.
- Background expiration cancels network work and reports task completion honestly.

## Test Strategy

Write focused tests before each implementation slice, then run the complete major-change regression once before push and device deployment.

Required unit and integration scenarios:

- Variant projection validation, deduplication, sorting, common labels, and single-rendition hiding.
- Initial 1080p selection, highest fallback, remembered manual target, unavailable-target fallback, and corrupt preference recovery.
- Quality changes preserve current time, rate, progress identity, queued episodes, and AirPlay playback.
- Cast remains on the validated master URL and does not claim a forced receiver resolution.
- Back collapses without stopping; expand restores the same player and timestamp; Close stops; replacement persists prior progress.
- Mini-player remains available across Latest, Saved, Played, and native catalog navigation.
- Serial inference from each trusted signal.
- Known latest episode playback while the full playlist is loading.
- Retry success on later attempts, partial-list retry, exhausted retry with known playback, exhausted retry without a known key, cancellation, and stale-result rejection.
- Recovered episode lists do not reset playback, AirPlay, Cast state, or progress.
- Daily due-date calculation, background rescheduling, foreground catch-up, and background/foreground coalescing.
- Direct checks for every saved serial title, bounded concurrency, first-check suppression, newer-episode detection, deduplication, per-title opt-out, partial failure, removal race, and task expiration.
- Settings `Last checked` and `Check Now`, plus notification deep-link routing.
- Existing native playback, ads exclusion, metrics, Saved, Played, fullscreen, Picture in Picture, background audio, lock-screen controls, AirPlay, Google Cast, filters, and heavy-user scenarios remain green.

Physical-device verification covers uninterrupted lock-screen playback, full-to-mini transitions, Picture in Picture, AirPlay quality preference, Google Cast continuity, background refresh opportunity, local notification delivery, and notification deep-link opening. Receiver quality adaptation is reported separately from local selection.

## Acceptance Criteria

- Every multi-variant native video exposes a working Quality menu.
- A fresh installation prefers exact 1080p and otherwise uses the highest valid resolution.
- Manual quality selection is remembered and does not restart playback or lose progress.
- Back allows continued playback while the user browses every native library surface.
- Returning to the player resumes the same session and timestamp.
- Serial titles do not silently start episode 1 when episode metadata is missing or incomplete.
- Episode lists retry four total times and can populate after playback starts without interruption.
- Every saved serial title receives a best-effort daily direct update check, with foreground catch-up and duplicate-free notifications.
- The app communicates that iOS controls background timing and does not promise exact-time delivery.
- The complete major-change regression, static analysis, Release build, review, push, and signed-device deployment complete before delivery.
