# Aiyifan Saved Freshness and Compact Cards Implementation Plan

## Objective

Refresh Home and Saved automatically at app opening, reconcile every newer provider observation without episode regression, publish player-discovered episodes back to Saved, and use one compact two-group footer across shared poster cards.

## Working Rules

- Write focused failing tests before each implementation slice.
- Keep network work outside `SavedItemsStore`; apply persisted changes on the main actor.
- Preserve Save membership, alert preferences, seen state, Ready-to-Watch intent, Played history, native playback, background audio, PiP, and casting.
- Treat provider responses as partial and untrusted. Never downgrade a known newer episode.
- Run focused tests during development and the complete regression after integration.

## Slice 1: Immutable Observation and Merge Rules

Files:

- Add `Aiyifan/App/SavedLibrarySynchronization.swift`.
- Add `AiyifanTests/SavedLibrarySynchronizationTests.swift`.
- Modify `Aiyifan/App/SavedItemsStore.swift`.
- Modify `AiyifanTests/SavedItemsStoreTests.swift`.

Steps:

1. Add failing tests for immutable catalog and episode observations.
2. Add failing tests proving episode 10 replaces 9, duplicate keys are removed, and a delayed or partial episode-9 response cannot replace 10.
3. Add tests for nonnumeric episode fallback, current-key retention, persistence, update detection, and preservation of user preferences and seen state.
4. Implement a pure episode-snapshot reconciler and provider-metadata merge.
5. Route existing Home and daily/background observations through the same store methods.
6. Run synchronization and Saved-store tests.

## Slice 2: App-Open Home and Saved Refresh

Files:

- Modify `Aiyifan/App/BrowserView.swift`.
- Modify `Aiyifan/App/SavedUpdateService.swift`.
- Modify `AiyifanTests/LibraryServicesTests.swift`.
- Modify relevant Saved-update tests.

Steps:

1. Add failing policy tests for cold launch, foreground reopening after 15 minutes, rapid reopen suppression, and manual force refresh.
2. Make the Saved monitor return a small completion result so partial checks do not advance successful app-open freshness.
3. Add one top-level app-open refresh path that refreshes Home and Saved and coalesces overlapping tasks.
4. Remove duplicate launch checks from Home while retaining Home pull-to-refresh and background scheduling.
5. Add force pull-to-refresh to Saved with existing data retained during failures.
6. Run policy, feed, Saved-update, and cancellation tests.

## Slice 3: Player-to-Saved Episode Observation

Files:

- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `Aiyifan/App/PlaybackSessionController.swift`.
- Modify `Aiyifan/App/BrowserView.swift`.
- Modify `AiyifanTests/NativePlayerViewModelTests.swift`.
- Modify `AiyifanTests/PlaybackSessionControllerTests.swift`.

Steps:

1. Add failing tests that initial playback resolution and independent episode recovery publish validated snapshots.
2. Pass an observation callback through the playback-session factory without coupling the player to `SavedItemsStore`.
3. Publish observations after resolved and recovered episode arrays are committed.
4. Have `BrowserView` reconcile those observations only when the title is saved.
5. Prove the observed episode 10 immediately replaces a Saved card's stale episode 9 and cannot later regress.

## Slice 4: Compact Shared Poster Footer

Files:

- Modify `Aiyifan/App/MediaCard.swift`.
- Modify `Aiyifan/App/SavedItemsView.swift`.
- Modify Home, Search, All, and compact-rail call sites only where an update-label override is required.
- Modify relevant unit and UI tests.

Steps:

1. Add failing presentation tests for latest-update priority, missing metadata, and Saved episode override.
2. Replace separate update and metadata rows with one line containing a cyan update segment and muted year/region segments.
3. Keep title at two lines and ensure update text truncates after metadata has yielded space.
4. Project Saved cards from reconciled episode state instead of the original saved subtitle.
5. Verify score, `NEW`, Save, and Remove overlays remain unchanged.

## Slice 5: Integrated Verification and Delivery

Steps:

1. Regenerate the Xcode project for new Swift files and run `pod install` if workspace references change.
2. Run the complete unit suite with coverage.
3. Run UI flows for cold launch, Saved force refresh, episode-10 synchronization, Home/Search/Saved/All card consistency, and the heavy-user session.
4. Capture and inspect iPhone 17 Pro Max and iPhone 14 Pro Max simulator screenshots for compact layout and overlap.
5. Run static analysis, `git diff --check`, dependency and secret checks, and a signed device build.
6. Perform correctness, concurrency, accessibility, and security review; resolve critical and high findings.
7. Update `DEVELOPMENT.md`, commit, push, then install and launch the exact commit on every available paired iPhone.

## Acceptance Gate

- Cold launch refreshes Home and Saved automatically.
- Foreground reopening refreshes both after 15 minutes without duplicate requests.
- Player discovery of episode 10 immediately updates a Saved title previously showing 9.
- Older or partial responses never downgrade a newer episode.
- Home, Search, Saved, All, and compact poster rails show a title plus one compact information row.
- Existing playback, Saved, Played, Ready-to-Watch, alerts, filters, search, PiP, AirPlay, and Cast behavior remains intact.
