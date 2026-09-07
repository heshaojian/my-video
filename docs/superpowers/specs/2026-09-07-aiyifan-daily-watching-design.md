# Aiyifan Daily Watching Design

## Goal

Make Aiyifan a dependable daily iPhone client for discovering the latest movies and episodes, saving them, resuming them, controlling playback from anywhere, and handing playback to Apple TV or Cast devices. The release extends the existing native playback architecture without introducing a required account, hosted backend, download system, or provider-control bypass.

## Delivery Approach

Use a local-first modular expansion of the current SwiftUI application.

- Local storage remains authoritative and works without iCloud.
- iCloud key-value sync is optional and merges Saved, Played, watch-state, and settings when the signed build has the required entitlement and the user enables sync.
- Background refresh compares saved-title snapshots against refreshed feeds and schedules local notifications. It is opportunistic because iOS controls refresh timing.
- The existing resolver, native AVPlayer path, website fallback, advertisement mute policy, AirPlay route picker, and Google Default Media Receiver remain intact.
- New behavior is implemented behind small testable services rather than expanding the existing resolver or player view into more responsibilities.

A hosted backend and remote push notifications are not part of this release. They would be required for guaranteed immediate update alerts.

## Product Structure

Keep three primary tabs in this order: `Latest`, `Saved`, and `Played`. Add Settings as a toolbar destination rather than a fourth tab so the primary navigation stays focused on watching.

### Latest

The Latest tab starts with these sections:

1. `Continue Watching`, shown only when resumable records exist.
2. `New for You`, shown only when saved serial titles have unseen updates.
3. The four existing latest-update sections: 电影, 电视剧, 综艺, and 动漫.

Continue Watching uses one card per title. For serial titles, it chooses the most recently played incomplete episode. A card displays artwork, title, episode label when applicable, progress, and a one-tap resume action. Its context menu supports restart, mark watched, and remove from Played.

New for You compares each saved title's current update label and latest resolved episode key with the last-seen snapshot. A title is new when either value changes to a nonempty value after the initial baseline. Opening the title marks the current update as seen only after its episode list resolves successfully. Users can also mark the update seen without playing it.

### Search And Filters

Add a native search field to Latest. Search matches case-insensitive title, update label, and available category metadata across the four fetched feeds. Results update without another network request.

Filters use compact controls and may be combined:

- Category: All, 电影, 电视剧, 综艺, 动漫.
- Language: All, 中文, English, Other/Unknown.
- Year: All plus years actually present in provider metadata or a recognizable four-digit title/update label.
- Watch state: All, Unplayed, In Progress, Watched, New Update.

Language classification uses provider metadata when present. Otherwise, titles containing Han characters are classified as 中文, titles containing Latin letters without Han characters as English, and ambiguous titles as Other/Unknown. The UI never invents missing metadata.

If the feed fails but cached items exist, search uses the cache and labels the results as previously loaded. Search is limited to the provider data fetched by the app; it does not claim to search the provider's complete historical catalog.

### Saved

Saved keeps the existing grid and adds:

- New-update badges.
- Sort by recently updated, recently saved, or title.
- Filter to titles with unseen updates.
- Notification preference per title, enabled by default after notification permission is granted.
- Context actions for remove, mark update seen, and reset watch state.

Saving a title stores its category and update snapshot when available. Existing saved data migrates without data loss; absent fields remain optional.

### Played

Played keeps newest activity first and adds:

- In Progress and Watched filter segments.
- Mark watched and mark unwatched actions.
- Restart from beginning.
- Per-record deletion and existing confirmed Clear All.
- A progress summary that distinguishes completed from resumable records.

Marking watched stores a completion override and opens from the beginning on the next play. Marking unwatched clears the override and position. Resetting a title removes all of that title's episode records after confirmation.

## Playback Experience

### Episode Navigation

Episode browsing remains newest-first. Playback order remains chronological.

- `Next Episode` means the next newer episode number/date than the current episode.
- `Previous Episode` means the next older episode number/date.
- Buttons are disabled at the boundaries.
- Selecting either control persists the current progress before resolving the destination episode.
- Autoplay Next is a setting enabled by default for serial content.
- Autoplay begins only after the program entry reaches completion; advertisement completion never advances episodes.
- A five-second nonblocking countdown allows cancellation before the next episode starts.

The player also exposes playback speed values supported by AVPlayer: 0.5x, 0.75x, 1x, 1.25x, 1.5x, and 2x. The chosen speed persists locally and is restored after pause, seek, episode changes, and advertisement transitions.

### Tracks And Quality

Subtitle and audio-language controls appear only when the resolved AVAsset exposes selectable media options. They use the asset's native media-selection groups and never synthesize unavailable tracks.

Quality selection appears only when the stream exposes multiple HLS variants that AVFoundation can represent safely. `Auto` remains the default. Manual choices set an appropriate preferred peak bit rate and can always return to Auto. A single-rendition stream shows no quality control.

### Sleep Timer

Add timer choices Off, 15, 30, 45, 60 minutes, and End of Episode. Expiration pauses local or Cast playback and clears the timer. The remaining duration is visible in the player controls and survives temporary backgrounding, but not an app termination.

### Now Playing And Remote Commands

A dedicated `NowPlayingCoordinator` publishes program-only metadata to the system:

- Title, episode label, artwork, duration, elapsed time, playback rate, and live/non-live status.
- Play, pause, toggle, 15-second skip backward/forward, change position, previous episode, and next episode commands where applicable.
- Updates when local playback changes episode, seek position, rate, or state.
- Clears metadata when the player is stopped and no Cast session is active.

Advertisement metadata is labeled as Advertisement and does not overwrite the saved program progress. Remote next/previous commands are unavailable during advertisements.

## Casting Experience

### AirPlay

Continue using AVPlayer and `AVRoutePickerView`. Now Playing metadata and remote commands stay synchronized because AirPlay follows the local player.

### Google Cast

Extend `GoogleCastManager` into a published session state with disconnected, connecting, connected, loading, playing, paused, and failed states. It owns the current receiver name, media metadata, position, duration, mute state, and recoverable error.

Add two native controls:

- A persistent mini controller above the tab bar whenever a Cast session is active. It shows artwork, title/episode, play/pause, and an expand button.
- An expanded Cast controller with seek, 15-second skip, previous/next episode, mute, stop casting, receiver name, and error/retry state.

All remote commands go through `GCKRemoteMediaClient` request objects and update UI only from confirmed SDK callbacks. Disconnecting transfers the latest confirmed program position back to local playback. A receiver playback failure keeps the Cast session available for retry and offers local playback.

The existing queue-based advertisement mute behavior remains. No custom receiver, stream proxy, download, or receiver-side bypass is added.

## Update Notifications

### Permission And Preferences

The app requests notification permission only after the user enables update alerts in Settings or on a saved title. Denial does not affect any other feature. Settings shows the current permission state and a shortcut to system settings when denied.

### Refresh Flow

Register one `BGAppRefreshTask` identifier. After a successful foreground or background feed refresh:

1. Compare refreshed saved-title snapshots with the last successful baseline.
2. Persist the new snapshot atomically.
3. Schedule one grouped local notification for newly updated saved titles that have alerts enabled.
4. Schedule the next background refresh request.

The first successful refresh establishes a baseline and sends no notification. Failed or partial feed loads do not advance snapshots or generate alerts. Duplicate episode/update keys are notified at most once.

Tapping a notification opens the saved title in the native player. If the stream cannot resolve, the standard Retry and website fallback remain available.

## Persistence And Sync

### Local Model

Introduce a versioned `LibrarySnapshot` containing:

- Saved title records with category, saved date, update baseline, seen update, and notification preference.
- Played records and completion overrides.
- Feed cache with category and last successful refresh date.
- Playback and library settings.

Migration reads the existing Saved and Played UserDefaults keys, preserves their order and progress, writes the new snapshot, and retains the old keys for one release as rollback protection.

All state updates create a new immutable snapshot and persist it through a `LibraryRepository` protocol. Persistence errors surface in Settings and never erase the in-memory state.

### iCloud

Use `NSUbiquitousKeyValueStore` for this personal app's compact library state. Sync is off by default until the user enables it. The local snapshot remains usable when iCloud is unavailable, signed out, over quota, or missing from the provisioning profile.

Merge rules are deterministic:

- Saved membership uses the newest explicit save/remove operation per title.
- Played records use the newest `lastPlayedAt` per title and episode.
- The furthest valid position wins when timestamps are equal.
- Explicit watched/unwatched actions use their newest action date.
- Seen-update state uses the newest seen date.
- Device-local settings such as sleep timer are not synced.

Sync never sends stream URLs, cookies, website data, or playback request parameters to iCloud.

## Reliability And Recovery

Add a `PlaybackRecoveryCoordinator` with bounded behavior:

- Retry transient resolution or stream failures once after a short delay.
- On an expired or rejected media URL, resolve a fresh playback plan and seek to the last confirmed program position.
- Never retry authentication, preview-only, unsupported-codec, private-network, or validation failures automatically.
- Cancel stale recovery when the user closes the player or selects another episode.
- After automatic recovery fails, show Retry and Open Website with the diagnostic category, not sensitive URLs or request data.

Cache only feed metadata and artwork URLs for offline browsing. Video is never downloaded. Opening a cached title while offline shows its saved metadata and a clear connection error without discarding progress.

Settings includes a compact diagnostics screen containing app version, last feed refresh, cache age, notification state, iCloud state, Cast state, and recent sanitized playback failure categories. It includes Clear Feed Cache and Reset Playback Settings commands with confirmation.

## Deep Links And Sharing

Support internal URLs for a title and optional episode key. Shared links use the provider's public title URL so recipients do not need Aiyifan installed. App-owned links are used for notification routing and restored navigation only; no associated-domain server is required.

## Component Boundaries

- `LibraryRepository`: versioned local snapshot, migration, queries, and immutable updates.
- `CloudLibrarySync`: optional iCloud observation, merge, and status reporting.
- `FeedRepository`: live feed fetch, validated cache, search projection, and partial-failure reporting.
- `UpdateTracker`: baseline comparison, seen state, and notification candidates.
- `NotificationCoordinator`: permission, local scheduling, background refresh registration, and deep-link payloads.
- `PlaybackSession`: player state, episode navigation, autoplay, speed, track selection, quality, and timer.
- `NowPlayingCoordinator`: system metadata and remote-command registration.
- `PlaybackRecoveryCoordinator`: bounded URL refresh and retry policy.
- `GoogleCastManager`: Cast SDK session and media controls behind a protocol.
- SwiftUI feature views consume read-only projections and send explicit commands to these coordinators.

No new service directly parses provider HTML except the existing feed and playback resolver boundaries.

## Error Handling

- Four feed categories refresh independently; one failure does not hide successful categories.
- Cached data remains visible with a stale indicator after refresh failure.
- Search and filters always operate on a stable snapshot.
- Notification, iCloud, AirPlay, and Cast failures never block local playback.
- Missing metadata hides unsupported controls instead of showing nonfunctional choices.
- Every asynchronous operation is cancelable and ignores obsolete results.
- User-facing errors are concise; logs use sanitized categories and never include signed media URLs.

## Test Strategy

Tests are written before each implementation slice. App-source coverage must remain at or above 80 percent.

### Unit Tests

- Snapshot migration, immutable updates, corruption recovery, cache expiry, and every iCloud merge rule.
- Continue Watching projection, one-card-per-title behavior, progress, watched overrides, restart, and removal.
- New-update baseline, seen state, first-refresh suppression, duplicate suppression, and partial-feed failure.
- Search normalization and combined category, language, year, and watch-state filtering.
- Newest-first episode display, chronological previous/next mapping, boundaries, autoplay countdown, and cancellation.
- Playback rate persistence, sleep timer expiration, media-track availability, and quality mapping.
- Now Playing metadata and each remote command through a fake command center.
- Recovery retry classification, fresh resolution, position handoff, cancellation, and terminal fallback.
- Cast state transitions, confirmed command callbacks, mini-controller projection, error/retry, disconnect handoff, and advertisement mute restoration.
- Notification permission states, refresh scheduling, grouped payloads, and deep-link routing through fakes.

### Integration Tests

- Feed refresh to cache, search projection, update detection, notification candidate, and Saved badge.
- Existing Saved and Played data migration followed by local changes and simulated iCloud merges.
- Resolver to AVPlayer preparation, program-only progress, system metadata, remote seek, and next-episode selection.
- Expired-stream recovery resolves a new URL and resumes without duplicate Played records.
- Cast connect, load, control, failure, retry, and local position handoff using a deterministic adapter.

### UI Tests

- Latest empty/loading/partial/cached states plus Continue Watching and New for You.
- Search text, combined filters, clear filters, no results, and compact-device layout.
- Saved update badges, sorting, alert preference, seen state, and removal.
- Played filters, mark watched/unwatched, restart, title reset, deletion, and Clear All.
- Player previous/next, autoplay cancellation, speed, sleep timer, optional track/quality controls, rotation, background, and Picture in Picture entry where supported.
- Mini and expanded Cast controllers in disconnected, connecting, playing, paused, failed, retried, and disconnected states.
- Notification deep link, Settings permission states, iCloud state, diagnostics, and cache reset.
- Existing category browser and explicit website fallback regressions.

### Heavy-User Verification

- Run the complete unit and UI suite after every source change.
- Run critical playback, persistence, notification, recovery, and Cast groups three consecutive times.
- Exercise at least 50 mixed actions across refresh, search, save, resume, seek, speed, episode change, background/foreground, rotation, Cast presentation, and player close/reopen.
- Relaunch with migrated, empty, large, corrupt, offline, and partially synchronized library fixtures.
- Verify live feeds for all four categories and native playback for one movie plus newest and older episodes from each serial category.
- Verify Release build, static analysis, dependency audit, secret scan, and at least 80 percent app-source coverage.
- On physical hardware, verify Lock Screen controls, background audio, Picture in Picture, local notifications, iCloud merge across two devices, AirPlay on Apple TV, and Cast on Android TV/Chromecast.
- Hardware-dependent results remain unverified until the required devices are reachable.

## Security And Privacy

- Validate all external URLs, response sizes, schemas, and host/network boundaries through existing resolver rules.
- Store no account credentials, cookies, signed stream URLs, or provider request secrets in library snapshots, diagnostics, notifications, or iCloud.
- Notification bodies contain title and update label only.
- Deep-link inputs are schema-validated and ignored when malformed.
- Keep dependency versions locked and audit them before release.

## Scope Boundaries

- No advertisement removal, skipping, suppression, or provider countermeasure bypass.
- No video download, offline media, DRM circumvention, regional bypass, credential capture, or stream proxy.
- No custom Cast receiver.
- No hosted backend or guaranteed real-time push notifications in this release.
- No complete historical-catalog claim when search only has current and cached feed data.
- Siri and Shortcuts actions are deferred until the daily watching flows are proven stable.

## Acceptance Criteria

- The home screen exposes Continue Watching, unseen saved-title updates, and the four latest categories without clutter or overlap on compact and large iPhones.
- Search and filters return honest results from available metadata and remain usable from cache.
- Movies and episodes resume reliably; serial playback supports chronological previous/next and optional autoplay while episode browsing stays newest-first.
- Lock Screen, Control Center, headphone, and system seek commands control the active program and show correct metadata.
- Supported tracks, quality choices, speed, and sleep timer work without presenting controls for unavailable capabilities.
- Saved update alerts are duplicate-free and degrade honestly when background refresh or permission is unavailable.
- Local library behavior works without iCloud; enabled iCloud sync converges deterministically without losing newer progress.
- Cast has persistent mini and expanded controls, recoverable errors, and position handoff; local playback remains available through receiver failures.
- Expired streams receive one bounded fresh-resolution attempt before clear Retry and website fallback.
- All automated and manual verification gates pass, app-source coverage is at least 80 percent, and unperformed physical-device checks are reported explicitly.
