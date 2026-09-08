# Aiyifan Ready to Watch Implementation Plan

## Objective

Add the approved Saved-only hybrid Ready to Watch queue while leaving Home,
navigation, and the existing Saved grid unchanged. Implement with tests first,
preserve the current uncommitted transport-control work, and run the complete
regression only after the phase stabilizes.

## Working Rules

- Use immutable value models and pure projection logic.
- Persist user intent, not a materialized queue snapshot.
- Reuse saved-update episode requests; do not add a second provider request.
- Never assume episode 1 when exact episode metadata is missing.
- Keep signed URLs, certificates, cookies, and media data out of persistence.
- Do not regenerate the Xcode project until all new Swift files are present.

## Slice 0: Protect The Existing Baseline

Files already modified and intentionally preserved:

- `Aiyifan/App/NativePlayerView.swift`
- `AiyifanTests/NativePlayerViewModelTests.swift`
- `AiyifanUITests/AiyifanLatestTapTests.swift`

Steps:

1. Run `NativePlayerViewModelTests` and the serial-player continuity UI test.
2. Fix any failure within the existing transport patch before queue work.
3. Commit that patch separately if green so later diffs have clear ownership.

## Slice 1: Retain Saved Episode State

Files:

- Modify `Aiyifan/App/SavedUpdateService.swift`.
- Modify `Aiyifan/App/NativePlaybackResolver.swift`.
- Modify `Aiyifan/App/SavedItemsStore.swift`.
- Modify `AiyifanTests/SavedItemsStoreTests.swift`.
- Modify `AiyifanTests/NativePlaybackResolverTests.swift`.

Steps:

1. Add failing tests for baseline suppression, unseen exact episodes, detection
   dates, mark-seen behavior, partial-check retention, unsave cleanup, bounded
   episode lists, and old metadata decoding.
2. Return the validated newest-first playlist from the existing saved-title
   resolver operation instead of discarding all but the newest episode.
3. Add a backward-compatible `SavedEpisodeUpdateState` to Saved metadata with
   bounded episodes, latest key, seen key, and detected date.
4. Separate per-title observation time from the global complete-check time.
5. Run Saved-store and resolver tests.

## Slice 2: Pure Queue Projection

Files:

- Add `Aiyifan/App/ReadyToWatch.swift`.
- Add `AiyifanTests/ReadyToWatchProjectorTests.swift`.

Steps:

1. Add failing tests for one candidate per title, incomplete continuity,
   completed-to-next advancement, exact episode selection, manual pin
   precedence, update and Played sorting, stable ties, malformed records,
   dismissals, and deduplication.
2. Implement immutable `ReadyToWatchEntry`, source, and projector input values.
3. Implement one pure `ReadyToWatchProjector.project(...)` entry point.
4. Keep all candidate and ordering rules out of SwiftUI.
5. Run projector tests.

## Slice 3: Sparse Overrides Store

Files:

- Add `Aiyifan/App/ReadyToWatchOverridesStore.swift`.
- Add `AiyifanTests/ReadyToWatchOverridesStoreTests.swift`.

Steps:

1. Add failing tests for versioned round trips, corrupt or future envelopes,
   idempotent pins, stable reorder, removal tombstones, episode dismissal,
   unsaved pruning, persistence retry, cloud merge, and a 100-entry fixture.
2. Add immutable pins, dismissals, and tombstones with modification dates.
3. Implement pin, unpin, dismiss, reorder, prune, merge, and retry commands.
4. Inject a narrow persistence protocol so write failures are deterministic in
   tests and do not erase in-memory state.
5. Run override-store tests.

## Slice 4: Exact Episode Commands

Files:

- Modify `Aiyifan/App/BrowserViewModel.swift`.
- Modify `Aiyifan/App/PlayedItemsStore.swift`.
- Modify `AiyifanTests/LibraryFeaturesTests.swift`.
- Modify `AiyifanTests/PlayedItemsStoreTests.swift`.

Steps:

1. Add failing tests for exact episode selection and marking an unstarted exact
   episode watched.
2. Add `selectItem(_:episodeKey:)`, assigning the episode key before publishing
   the item.
3. Add an exact-episode mark-watched command with a completion override even
   when duration is unknown.
4. Run browser feature and Played-store tests.

## Slice 5: Saved Queue UI

Files:

- Add `Aiyifan/App/ReadyToWatchView.swift`.
- Modify `Aiyifan/App/SavedItemsView.swift`.
- Modify `Aiyifan/App/MediaCard.swift`.
- Modify `Aiyifan/App/BrowserView.swift`.
- Add `AiyifanUITests/AiyifanReadyToWatchUITests.swift`.

Steps:

1. Add fixture-backed UI tests for rail placement, the unchanged Saved grid,
   empty queue, NEW and resume labels, exact Play, See All, pin, reorder,
   dismiss, mark watched, persistence, long titles, and accessibility.
2. Add a compact horizontal `ReadyToWatchRail` using the shared card family.
3. Add the full vertical queue manager with native drag handles.
4. Own the Ready store in `BrowserView`, pass Played state into Saved, and
   recompute after Saved, Played, update, or override changes.
5. Add `Add to Ready to Watch` only on Saved-title actions and preserve all
   existing card identifiers and actions.
6. Run Ready UI tests on compact and large simulators.

## Slice 6: Notification Actions

Files:

- Modify `Aiyifan/App/LibraryServices.swift`.
- Modify `Aiyifan/App/AiyifanApp.swift`.
- Modify `AiyifanTests/LibraryServicesTests.swift`.

Steps:

1. Add failing tests for notification category descriptors, Play Now, Add to Up
   Next, exact episode payloads, malformed data, stale unsaved titles, duplicate
   actions, and default taps.
2. Add stable notification action identifiers and register the category at app
   startup.
3. Extract a pure response-routing decision.
4. Route Play Now to the validated episode deep link and Add to Up Next to a
   persisted pin without starting playback.
5. Keep denied permission independent of Saved and queue state.

## Slice 7: Optional iCloud Migration

Files:

- Modify `Aiyifan/App/LibraryServices.swift`.
- Modify `Aiyifan/App/AppSettingsView.swift`.
- Modify `AiyifanTests/LibraryServicesTests.swift`.

Steps:

1. Add failing tests for current V1 payload decoding, missing Ready fields,
   newest-operation conflict resolution, equal-time ties, removal tombstones,
   corrupt cloud data, and disabled iCloud.
2. Extend the cloud envelope with optional Ready overrides using a custom
   backward-compatible decoder.
3. Merge sparse operations deterministically; never sync the projected queue.
4. Keep Personal Team builds locally functional with iCloud unavailable.

## Slice 8: Integration, Documentation, And Review

Files:

- Add or extend Ready integration and heavy-user UI tests.
- Modify `README.md`.
- Modify `DEVELOPMENT.md`.
- Modify the dated release verification record with verified facts only.

Steps:

1. Test update check to queue to notification to exact playback.
2. Test incomplete playback to completion to next episode.
3. Test offline relaunch, partial checks, delayed unsave, large queues, and two
   simulated cloud payloads.
4. Update README and DEVELOPMENT with queue rules, ownership, migrations,
   provider failures, testing, and the future-feature checklist.
5. Run `scripts/create_xcode_project.rb` once, run `pod install`, and inspect all
   generated changes.
6. Run focused tests, then full tests with coverage, Release build, analysis,
   plist validation, dependency review, secret scan, and diff review.
7. Address all critical and high review findings before commit.

## Focused Verification

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/ReadyToWatchProjectorTests \
  -only-testing:AiyifanTests/ReadyToWatchOverridesStoreTests \
  -only-testing:AiyifanTests/SavedItemsStoreTests \
  -only-testing:AiyifanTests/PlayedItemsStoreTests \
  -only-testing:AiyifanTests/LibraryServicesTests \
  CODE_SIGNING_ALLOWED=NO
```

## Acceptance Gate

- Ready to Watch appears only in Saved, above the unchanged Saved grid.
- Candidate, continuity, pin, order, dismissal, and exact-play rules match the
  approved design.
- Provider failures retain valid queue state and never erase library data.
- Notification actions work without duplicate entries or accidental playback.
- Existing Home, Search, Played, All, playback, and mini-player tests pass.
- README and DEVELOPMENT contain enough guidance for a new coding agent.
- Full stabilized regression passes at 80 percent or greater coverage.
