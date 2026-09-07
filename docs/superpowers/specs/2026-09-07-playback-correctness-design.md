# Aiyifan Playback Correctness Design

Date: 2026-09-07
Status: Approved

## Goal

Make playback state truthful and stable for daily use: Played rows must not look active after playback stops, separately supplied provider advertisements must not enter local or Cast queues, and fullscreen transitions must preserve the current player and position.

## Played History

- Keep resume behavior: selecting an unfinished Played record resumes from its saved program position.
- Replace the moving relative-date label with a fixed `Paused at mm:ss / mm:ss` position label.
- Persist periodic progress only while the local program player is genuinely playing.
- Persist once when playback transitions from playing to paused or stalled, and when the user explicitly leaves the player.
- Never record advertisement time, loading time, or a clock-derived estimate.

## Advertisement Removal

- Treat only the resolved program entry as playable media.
- Remove separately returned advertisement entries before preparing either `AVQueuePlayer` or Google Cast playback.
- Do not proxy, rewrite, or bypass DRM, provider authentication, or advertisements embedded inside the program stream.
- Fail with the existing playback error when no program entry is available.

## Fullscreen Lifecycle

- Keep one `NativePlayerViewModel` and one `AVPlayer` for inline, fullscreen, and Picture in Picture presentation.
- Make `start()` idempotent so repeated SwiftUI appearance callbacks do not resolve or restart playback.
- Do not stop playback from `onDisappear`, because `AVPlayerViewController` can temporarily change presentation ownership while entering fullscreen.
- Stop and clear playback only from explicit player exits: Back and Open Website.
- Keep progress monitoring owned by the view model so a temporary presentation transition cannot cancel it.

## Error Handling

- Existing resolver and retry errors remain visible in the native player.
- If fullscreen presentation changes without a playable item, retain the current error state rather than starting a second load.
- Explicit exits always persist the last valid program position before clearing the queue.

## Verification

- Unit tests cover program-only queue selection, idempotent start, progress persistence only during real playback, and explicit shutdown.
- UI coverage confirms no advertisement label appears and fullscreen presentation does not dismiss or replace the native player.
- Run affected unit/UI tests first, then the full regression because these changes alter shared playback lifecycle behavior.
