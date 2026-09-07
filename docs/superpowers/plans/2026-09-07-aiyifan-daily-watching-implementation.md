# Aiyifan Daily Watching Implementation Plan

## Principles

- Deliver in dependency order and keep each slice buildable.
- Write the behavioral test first, observe failure, implement the smallest complete behavior, then refactor.
- Keep app-source coverage at or above 80 percent after every completed slice.
- Preserve native playback, advertisement muting, Saved/Played migration, website fallback, AirPlay, and existing Cast behavior throughout.
- Keep provider URLs and signed playback data out of persistence, logs, notifications, and iCloud.

## Phase 1: Library Domain And Discovery

### Models And Persistence

Create `LibraryModels.swift` and `LibraryRepository.swift`.

1. Add tests for versioned snapshot decoding, legacy Saved/Played migration, immutable updates, completion overrides, and corrupt-data recovery.
2. Add `SavedRecord`, `LibrarySettings`, `FeedCacheEntry`, `UpdateSnapshot`, and `LibrarySnapshot` value types.
3. Implement a repository protocol and UserDefaults-backed repository.
4. Adapt existing Saved and Played stores to the repository while preserving their public UI contracts.

### Feed Cache, Search, And Updates

Create `FeedRepository.swift`, `LibrarySearch.swift`, and `UpdateTracker.swift`.

1. Add tests for independent category refresh, partial failure, cache fallback, metadata classification, search normalization, and combined filters.
2. Add tests for first-refresh baselines, changed update keys, seen state, duplicate suppression, and Continue Watching projection.
3. Refactor feed loading through a repository that returns stable category snapshots and cache status.
4. Expose search results, filters, Continue Watching, and New for You projections from the browser view model.

## Phase 2: Library UI

Refactor `BrowserView.swift` into focused feature files while preserving stable accessibility identifiers.

1. Add UI tests for Continue Watching resume, New for You, search, filters, no results, and cached/partial states.
2. Add UI tests for Saved sorting/update actions and Played watched-state controls.
3. Implement compact home sections, a searchable results view, filter sheet, Saved controls, and Played controls.
4. Add Settings as a toolbar sheet and keep Latest/Saved/Played as the only tabs.

## Phase 3: Playback Session

Create `PlaybackSession.swift`, `SleepTimer.swift`, `NowPlayingCoordinator.swift`, and `PlaybackRecoveryCoordinator.swift`.

1. Add unit tests for chronological previous/next mapping from newest-first episode arrays, boundaries, autoplay countdown, and cancellation.
2. Add tests for playback-rate persistence, timer expiration, selectable media option projections, and preferred quality mapping.
3. Add fake command-center tests for metadata, play/pause, seek, skip, and episode commands.
4. Add recovery tests for transient retry, expired URL refresh, position handoff, terminal validation errors, and cancellation.
5. Integrate the tested coordinators into `NativePlayerViewModel` and add the corresponding player controls.

## Phase 4: Notifications And iCloud

Create `NotificationCoordinator.swift`, `BackgroundRefreshCoordinator.swift`, and `CloudLibrarySync.swift`.

1. Add tests for authorization states, first-baseline suppression, grouped notifications, deep-link validation, and scheduling.
2. Add tests for every iCloud merge rule and local fallback state.
3. Register the background task identifier and required Info.plist modes.
4. Add the iCloud key-value entitlement and keep sync opt-in with explicit unavailable/error states.
5. Route notification payloads into native title/episode navigation.

## Phase 5: Cast Experience

Refactor `Casting.swift` and create `CastControlsView.swift`.

1. Extend fake-adapter tests for session states, media status, confirmed requests, errors, retry, and position handoff.
2. Publish receiver, playback, timing, mute, and error state from the SDK adapter.
3. Add the persistent mini controller and expanded controller.
4. Keep local playback ready as fallback and preserve advertisement mute restoration.

## Phase 6: Integrated Verification

1. Run all unit and UI tests with coverage after each source change.
2. Run the critical test groups three times consecutively.
3. Run the deterministic 50-action heavy-user UI scenario on compact and large simulator destinations.
4. Run live four-feed loading plus native movie and serial playback checks.
5. Run Release build, `xcodebuild analyze`, dependency audit, secret scan, and diff review.
6. Verify app-source line coverage is at least 80 percent.
7. Run reachable physical-device checks and explicitly list any unavailable Apple TV, Android TV/Chromecast, notification, iCloud, Picture in Picture, or background-audio checks.

## Commit Sequence

Use focused conventional commits:

1. `test: define daily library behavior`
2. `feat: add daily library discovery`
3. `feat: add daily library interface`
4. `test: define playback continuity behavior`
5. `feat: add playback continuity controls`
6. `feat: add update notifications and cloud sync`
7. `feat: complete cast controls`
8. `test: expand heavy user regression coverage`
9. `docs: document daily watching release`

Push only after the final security review and complete verification report.
