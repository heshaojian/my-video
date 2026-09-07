# Aiyifan Continuous Playback, Quality, Episode Recovery, and Saved Updates Implementation Plan

## Objective

Add native resolution selection with a 1080p initial preference, keep one playback session alive while the user browses the app, recover missing or partial episode lists without silently starting episode 1, and directly check every saved serial title for updates once per day on a best-effort basis.

## Working Rules

- Write focused failing tests before each behavior change and run only affected suites while implementing.
- Keep provider content unchanged and retain HTTPS, host, identifier, redirect, and response-size validation.
- Preserve the existing program-only playback queue, progress identity, Now Playing, PiP, AirPlay, Google Cast, background audio, Saved, and Played behavior.
- Do not persist signed URLs, certificates, cookies, or HLS payloads.
- Do not promise exact background execution time; iOS owns `BGAppRefreshTask` scheduling.
- Run the complete unit and UI regression once after all slices are integrated.

## Slice 1: Quality Contracts and Preferences

Files:

- Add `Aiyifan/App/PlaybackQuality.swift`.
- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `AiyifanTests/PlaybackFeaturesTests.swift`.
- Modify `AiyifanTests/NativePlayerViewModelTests.swift`.

Steps:

1. Add failing tests for valid AVFoundation variant projection, malformed-value rejection, resolution deduplication, descending ordering, and standard labels.
2. Add failing tests for exact 1080p initial selection, highest fallback, persisted manual target, highest-at-or-below fallback, single-rendition hiding, and corrupt preference recovery.
3. Implement immutable `PlaybackQualityOption`, variant projection, and a versioned `PlaybackQualityPreferenceStore`.
4. Load HLS variants asynchronously from the resolved program asset and publish available quality options from the player model.
5. Apply the chosen maximum resolution and matching peak bitrate before player-item insertion.
6. Add a Quality submenu only when multiple valid resolutions exist; changing it updates current and queued program items without replacing the player or resetting progress.
7. Keep Google Cast on the validated master HLS URL and present its quality as receiver-controlled.

## Slice 2: Shared Playback Session and Mini-Player

Files:

- Add `Aiyifan/App/PlaybackSessionController.swift`.
- Modify `Aiyifan/App/BrowserView.swift`.
- Modify `Aiyifan/App/BrowserViewModel.swift` as needed for navigation-only state.
- Modify `Aiyifan/App/NativePlayerView.swift` so the screen consumes a session-owned model.
- Add or extend unit and UI tests.

Steps:

1. Add failing state-machine tests for inactive, expanded, collapsed, expand, explicit close, and replacement behavior.
2. Lift `NativePlayerViewModel` ownership from `NativePlayerScreen` into a `PlaybackSessionController` owned by `BrowserView`.
3. Separate view disappearance from playback stop. Back persists progress and collapses; Close remains the explicit stop command.
4. Keep library and native catalog navigation mounted while playback is collapsed.
5. Add a stable mini-player above the tab bar or native catalog bottom edge with video/artwork, title, episode, Play/Pause, Expand, and Close controls.
6. Selecting another item persists and stops the prior session before creating the replacement.
7. Add UI scenarios proving continued playback and timestamp identity through Latest, Saved, Played, and All navigation.

## Slice 3: Independent Episode Recovery

Files:

- Modify `Aiyifan/App/NativePlaybackResolver.swift`.
- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `Aiyifan/App/EpisodeNavigator.swift` if the recovered-list boundary requires it.
- Extend `AiyifanTests/NativePlaybackResolverTests.swift` and `AiyifanTests/NativePlayerViewModelTests.swift`.

Steps:

1. Add failing tests for serial inference from provider detail, item serial flag, latest episode key, and Series/Variety/Anime category paths.
2. Add a cancelable episode-list loader with four attempts at 0, 0.5, 1.5, and 3 seconds.
3. Retry transport failures, empty or invalid envelopes, and lists missing the expected latest key; reject terminal authentication, host, identifier, preview, and cancellation failures immediately.
4. When a trusted latest or preferred episode key exists, resolve that media immediately and load the complete list independently.
5. Publish a recovered list into the active player model without replacing its player item, changing time, or resetting route/Cast state.
6. If retries exhaust while known playback is active, keep playing and expose Retry Episodes. Without a trustworthy key, fail recoverably instead of choosing episode 1.
7. Ignore canceled or stale episode results after title/episode replacement.

## Slice 4: Direct Daily Saved Update Checking

Files:

- Add `Aiyifan/App/SavedUpdateChecker.swift`.
- Modify `Aiyifan/App/BackgroundRefresh.swift`.
- Modify `Aiyifan/App/SavedItemsStore.swift`.
- Modify `Aiyifan/App/LibraryServices.swift` if shared notification projections need extension.
- Modify `Aiyifan/App/AiyifanApp.swift` and `Aiyifan/App/BrowserView.swift` for foreground catch-up.
- Add focused Saved/update/background tests.

Steps:

1. Add failing tests for 24-hour due calculation, first-success baseline suppression, strictly newer episode detection, deduplication, per-title opt-out, and metadata updates.
2. Add failing tests for bounded concurrency, isolated title failure, cancellation/expiration, removal races, and coalesced foreground/background requests.
3. Implement a direct saved-title update service that reuses one certificate and calls validated detail plus playlist endpoints for serial titles.
4. Persist versioned per-title baselines, last completed check date, and sanitized partial-failure state without signed provider data.
5. Check at most three titles concurrently and commit immutable results only for titles still saved.
6. Schedule the next background request no earlier than 24 hours after a completed check and reschedule after every task attempt.
7. Trigger one coalesced catch-up when the app becomes active and the last completed check is overdue.
8. Continue using the global and per-title alert preferences, notification batching, and deep-link routing.

## Slice 5: Settings and Cross-Feature UI

Files:

- Modify `Aiyifan/App/AppSettingsView.swift`.
- Modify player and mini-player views.
- Extend UI tests.

Steps:

1. Add Last Checked, Check Now, in-progress, success, and partial-failure states to Settings.
2. Verify quality, episode-retry, and mini-player controls use concise English labels and stable accessibility identifiers.
3. Verify compact and large iPhone layouts, including long provider titles and episode names, without toolbar overlap.
4. Verify replacing playback, opening website fallback, notification deep links, and explicit Close have unambiguous stop/preserve behavior.

## Slice 6: Major Regression and Delivery

1. Run all unit and integration tests on the warmed iPhone 17 Pro simulator.
2. Run the complete UI suite once, including the heavy-user flow and new mini-player, quality, episode-retry, and daily-update scenarios.
3. If failures occur, rerun only the affected cases after each fix, then rerun the complete suite once after the last major correction.
4. Run Release build, Xcode static analysis, plist and generated-project validation, dependency status, secret scan, and `git diff --check`.
5. Run bounded live read-only probes for one multi-variant HLS asset, one serial playlist, and one saved-title update without retaining signed data.
6. Review correctness, concurrency, security, background expiration, and stale-result handling.
7. Update README and the release verification report.
8. Commit, push `master`, build the exact commit for the paired iPhone, install, and launch.

## Acceptance Gate

- A fresh installation selects exact 1080p when available and otherwise the highest valid rendition.
- Manual quality choices persist and apply without restarting playback or losing time.
- Back collapses playback into a functional mini-player while every native library surface remains browsable.
- Expanding restores the same player, timestamp, episode, rate, route, and progress record.
- Serial playback never silently substitutes episode 1 for missing or partial episode metadata.
- Episode metadata retries four total times and can populate after known-latest playback begins.
- Every saved serial title receives a direct best-effort daily check plus overdue foreground catch-up.
- Update notifications are baseline-safe, deduplicated, preference-aware, and deep-link correctly.
- Existing playback, ads exclusion, metrics, Saved, Played, fullscreen, PiP, lock-screen, AirPlay, Cast, filters, and fallback tests remain green.
- Release checks pass before GitHub push and signed-device installation.
