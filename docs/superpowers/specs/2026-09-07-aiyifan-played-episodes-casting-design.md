# Aiyifan Played, Episodes, and Casting Design

## Goal

Extend Aiyifan's native playback experience with quiet advertisement handling, durable watch history, newest-first episode selection, AirPlay, and Google Cast. The release must pass automated regression, stress, and live playback checks before it is considered ready.

## Product Behavior

### Advertisement Audio

- Provider-required advertisement entries remain in the playback timeline and are not skipped or removed.
- Playback is automatically muted while an entry is identified as an advertisement.
- When the first program entry begins, the player restores the mute state that existed before the advertisement. If the user had already muted playback, the program remains muted.
- Played history, resume position, and completion percentage exclude advertisement time.
- The player continues to label advertisement playback clearly.

### Played Tab

- The library has three tabs in this order: `Latest`, `Saved`, and `Played`.
- Played records are episode-level for serial content and title-level for movies.
- Each record stores an item snapshot, episode identifier and label when applicable, program position, program duration, completion state, and last-played date.
- Records are ordered by last-played date descending.
- Opening a Played record resolves a fresh stream and resumes near the saved program position. Resume positions are clamped to the current duration and restart from the beginning when the record was completed.
- A record is created only when program playback begins, never while an advertisement is playing.
- Progress is persisted every 10 seconds, when playback pauses or changes episode, when the player closes, and when the app backgrounds.
- A record is complete after reaching 90 percent of program duration. Reopening a completed record starts from the beginning.
- Users can remove one record or clear all Played records after confirmation.
- Played data persists locally across relaunches. It does not require or create an Aiyifan account.

### Episodes

- Any title that the detail API identifies as serial receives an episode picker. This covers 电视剧, 综艺, and 动漫 without relying on the feed category.
- The resolver returns the complete available episode list instead of discarding it after selecting one episode.
- Episodes are sorted by valid update date descending. Equal or missing dates use a numeric episode-label comparison descending, with original source order as the final stable tie-breaker.
- The newest episode is selected by default when a serial title is opened from Latest or Saved.
- Opening an episode-specific Played record selects that episode and resumes it.
- Selecting another episode replaces the active program safely, applies any required advertisement sequence for that request, and updates Played independently.
- The episode picker shows newest episodes first and marks the current episode.

### Apple Playback Routes

- Keep AVKit's built-in external playback support and add a visible `AVRoutePickerView` control in the player header.
- The route picker prioritizes video devices and exposes Apple TV, Mac, and compatible AirPlay receivers discovered by iOS.
- AirPlay follows the local AVPlayer queue, including advertisement muting, program playback, episode switching, seeking, and resume behavior.

### Google Cast

- Integrate the official Google Cast iOS Sender SDK using CocoaPods and open the generated Xcode workspace for development.
- Use Google's Default Media Receiver so this personal app does not require a hosted custom receiver or registered Cast application ID.
- Add the required local-network usage description and Bonjour service declarations for Cast discovery.
- Show the standard Google Cast button beside AirPlay and use the SDK's session manager for discovery, connection, reconnection, and disconnect handling.
- Load required advertisement entries followed by the HTTPS HLS program as a receiver queue with title, episode label, and artwork metadata. The receiver controls play, pause, seek, and position synchronization.
- Preserve the user's receiver mute state, temporarily mute the receiver during advertisement entries, and restore the prior state when the program begins.
- When moving between local and Cast playback, transfer the active program position and avoid writing duplicate Played records.
- A Cast failure leaves local playback usable and shows a concise recoverable error.
- Cast availability does not imply stream compatibility. The receiver must be able to fetch the expiring HLS URL and all segments directly with compatible codecs and CORS headers.

## Architecture

### Playback Domain

Split the current resolver output into explicit value types:

- `Episode`: stable media key, display label, and optional update date.
- `ResolvedTitle`: movie or serial metadata plus newest-first episodes.
- `NativePlayback`: advertisement entries, one program entry, selected episode, and title metadata.

`NativePlaybackResolving` first resolves title metadata and then resolves playback for a selected movie or episode. Request signing, HTTPS validation, supported-host validation, response-size limits, preview/login refusal, and private-network rejection remain mandatory.

### Player Coordination

`NativePlayerViewModel` coordinates local AVQueuePlayer state, selected episode, ad muting, resume, and Played updates. Cast-specific SDK calls sit behind a `Casting` protocol so tests use deterministic fakes and the main player does not depend directly on global Cast state.

Only immutable playback snapshots cross component boundaries. Stores replace value arrays when updating records rather than mutating shared objects.

### Persistence

`PlayedItemsStore` mirrors the existing small local `SavedItemsStore` pattern and persists versioned Codable records in UserDefaults. Corrupt or unsupported records are ignored without deleting valid records. The model is isolated so it can move to a database later without changing player or UI contracts.

### Dependency Setup

Add a `Podfile` and lockfile for the Google Cast SDK, ignore generated Pods, and update repository instructions to use `Aiyifan.xcworkspace`. The project generator remains the source of project structure and must continue producing all app and test targets before `pod install` integrates the Cast dependency.

## Error Handling

- Missing or malformed episode lists show the existing native failure view with Retry and explicit website fallback.
- Selecting an episode cancels obsolete resolution work so a slow prior request cannot replace the newest selection.
- Resume data is never applied to advertisements and never seeks beyond the program's seekable duration.
- Local-network denial disables Cast discovery without blocking local playback or AirPlay.
- Receiver disconnect transfers the last confirmed remote program position back to local playback when possible.
- Expired or receiver-incompatible streams surface a Cast error and offer local playback; the app does not proxy, download, decrypt, or bypass provider controls.

## Test Contract

The complete regression gate runs after every source change. Tests are written before implementation, and app-source coverage must remain at or above 80 percent.

### Unit Tests

- Episode decoding, malformed data, date parsing, numeric-label fallback, stable ordering, and newest selection.
- Movie and selected-episode playback requests, signed parameters, HTTPS/public-host restrictions, previews, login requirements, invalid ads, and full-program selection.
- Ad mute entry, preservation of prior mute state, program unmute transition, retry, cancellation, and episode switching.
- Played creation only at program start, periodic progress updates, completion, resume clamping, independent episode records, deduplication, ordering, removal, clearing, persistence, and corrupt-data recovery.
- Cast metadata, local-to-remote position transfer, remote-to-local recovery, mute restoration, reconnect, and errors through a fake casting client.

### Integration Tests

- Stub the complete page, detail, playlist, and playback request chain for movies and serial titles.
- Verify out-of-order playlist data renders newest first and selecting an older episode requests its own stream.
- Verify ad-to-program transitions update sound and history exactly once.
- Verify Cast session events update playback and Played state without duplicate records.

### UI Tests

- Latest, Saved, and Played tabs, including empty and populated Played states.
- Newest-first episode picker, current marker, rapid episode changes, and episode-specific resume.
- Muted advertisement state followed by restored program audio state.
- Played ordering, progress display, relaunch persistence, individual removal, and confirmed Clear All.
- AirPlay and Cast controls remain reachable in portrait and landscape without overlapping titles or player controls.
- Cast unavailable, local-network denied, connection failure, disconnect, reconnect, and local fallback states.
- Existing category browsing, explicit website fallback, popup isolation, save/remove, and repeated player navigation regressions.

### Heavy-User Verification

- Run the full suite on iPhone 16e and iPhone 17 Pro simulators and repeat the critical playback-history-casting UI group at least three times.
- Exercise at least 25 sequential open, close, resume, seek, and episode-switch actions without stale playback or duplicated history.
- Relaunch repeatedly with Saved and Played data, background and foreground during ads and programs, rotate in both directions, and test offline recovery and expired streams.
- Use live data from all four categories. Confirm full movie playback and newest plus older episode playback for one title from each serial category.
- Confirm background audio time advances and PiP starts where the simulator supports it.
- On a connected iPhone, verify AirPlay against an Apple TV or compatible receiver and Google Cast against an Android TV or Chromecast on the same network. Confirm discovery, connect, program playback, seek, pause, episode switch, disconnect, reconnect, mute restoration, and position handoff.
- Hardware casting is reported as unverified until both receiver families are physically reachable. Simulator and mocked SDK tests cannot replace this check.

## Scope Boundaries

- No advertisement removal, skipping, request suppression, or provider countermeasure bypass.
- No downloads, offline media, DRM circumvention, regional bypass, credential capture, or stream proxy.
- No custom Cast receiver or hosted backend in this iteration.
- No cloud synchronization of Saved or Played data.

## Acceptance Criteria

- Ads play silently and the user's prior audio state is restored for the program.
- Played is the third tab and reliably resumes movies and individual episodes with newest activity first.
- Serial episode pickers display the newest available episode first and play the selected episode natively.
- AirPlay and Google Cast controls are present, local playback remains usable through route failures, and hardware results are reported honestly.
- All unit, integration, UI, stress, static-analysis, security, and device-build gates pass with at least 80 percent app-source coverage before release.
