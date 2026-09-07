# Aiyifan English Interface, Viewer Metrics, and Catalog Preferences Implementation Plan

## Objective

Remove the Latest search field, translate app-owned interface text to English, display provider scores in Latest and catalog lists, display Likes/Favorites/Score/Views in native playback, and restore each category's last successfully applied filter and sort query across navigation and app relaunches.

## Working Rules

- Write focused failing tests before each behavior change and run only the affected suites during implementation.
- Run the complete unit and UI suite once after the major change is assembled.
- Preserve provider-supplied text exactly and keep stable identifiers independent from translated labels.
- Do not add per-card detail requests, interaction submission, or authentication behavior.
- Retain request signing, response bounds, HTTPS and host validation, playback behavior, Saved/Played data, casting, and background playback.

## Slice 1: Metric and Preference Contracts

Files:

- Modify `Aiyifan/App/AiyifanItem.swift`.
- Modify `Aiyifan/App/NativePlaybackResolver.swift`.
- Add `Aiyifan/App/CatalogPreferenceStore.swift`.
- Modify `AiyifanTests/CategoryCatalogTests.swift`.
- Modify `AiyifanTests/NativePlaybackResolverTests.swift`.

Steps:

1. Add failing tests for score decoding, valid score bounds, nonnegative metric counts, malformed optional metric omission, and immutable playback metric propagation.
2. Add failing tests for versioned per-category query persistence, independent categories, corrupt storage, invalid queries, clear-filter behavior, and sort retention.
3. Add optional provider `score` to items while retaining `rating` as a separate sort field.
4. Add immutable Likes/Favorites/Score/Views playback metrics decoded from the existing detail response.
5. Implement the `UserDefaults` preference store with validated immutable snapshots and category raw-value keys.

## Slice 2: Latest Scores Without Per-Card Requests

Files:

- Modify `Aiyifan/App/AiyifanFeedService.swift`.
- Modify `Aiyifan/App/CategoryCatalogService.swift`.
- Modify `Aiyifan/App/FeedRepository.swift` if shared refresh configuration is required.
- Extend feed and catalog tests.

Steps:

1. Add failing tests that Latest requests page one, eight items, updated-time descending for each category.
2. Decode catalog `score` separately from `rating` and add deterministic fixture values.
3. Reuse the signed catalog request path for Latest and cache one provider certificate for the concurrent refresh operation.
4. Preserve independent category fallback and existing feed-cache compatibility.
5. Verify no detail endpoint is requested while rendering Latest cards.

## Slice 3: Persistent Catalog Query State

Files:

- Modify `Aiyifan/App/CategoryCatalogViewModel.swift`.
- Modify `Aiyifan/App/NativeCategoryCatalogView.swift`.
- Extend catalog unit and UI tests.

Steps:

1. Restore a validated per-category query before the initial page request.
2. Persist filters only after successful Apply and persist sort/direction only after a successful sort response.
3. Keep Cancel transactional; make Clear Filters retain sort and direction.
4. Reconcile restored choices with live filter metadata and reload only if stale options changed the effective query.
5. Cover navigation re-entry, relaunch, category independence, failed requests, stale responses, and stale provider options.

## Slice 4: English Interface and Search Removal

Files:

- Modify app views and app-owned display properties containing interface copy.
- Modify UI tests that assert translated labels.

Steps:

1. Translate category labels, tab labels, filter/sort controls, status and error states, episode controls, settings, collection actions, Cast text, and accessibility labels.
2. Keep provider title, episode, description, genre, region, language, year, quality, and other option strings unchanged.
3. Replace display-text-derived identifiers with stable enum raw values where necessary.
4. Remove `.searchable` from Latest while retaining non-text filters.
5. Rename filtered output to `Filtered Titles` and make its clear action reset the complete Latest filter.
6. Add a source scan and UI assertions proving no app-owned Chinese interface text or searchable field remains.

## Slice 5: Score Cards and Player Metrics

Files:

- Modify `Aiyifan/App/BrowserView.swift`.
- Modify `Aiyifan/App/NativeCategoryCatalogView.swift`.
- Modify `Aiyifan/App/NativePlayerView.swift`.
- Extend model and UI tests.

Steps:

1. Add a compact star score to Latest and catalog cards only when a valid score exists.
2. Add a tested compact-count formatter for English `K` and `M` output.
3. Publish playback metrics from the resolver through `NativePlayerViewModel`.
4. Render one stable metrics row between the player toolbar and video with SF Symbols and English labels.
5. Verify missing metrics collapse independently and do not block playback.
6. Check compact and large iPhone layouts for clipping and toolbar continuity.

## Slice 6: Major Regression and Delivery

1. Run all unit/integration tests on the warmed iPhone 17 Pro simulator.
2. Run the complete UI suite once, including the 50-action power-user scenario.
3. Run targeted filter persistence, English-interface, score, metrics, serial episode, fullscreen, Saved, and Played scenarios again if any related failure appears.
4. Run Release build, Xcode static analysis, plist and project-generation validation, dependency status, secret scan, and `git diff --check`.
5. Perform bounded live read-only probes for all four latest category score responses and one detail metrics response without logging signed URLs or certificates.
6. Update the feature verification report, review the complete diff, commit, push, build for the paired iPhone, install, and launch when the device is unlocked.

## Acceptance Gate

- Latest has no search field and all app-owned interface copy is English.
- Provider-supplied content remains unmodified.
- Latest and catalog cards display valid provider scores with no per-card detail requests.
- Native playback displays available Likes, Favorites, Score, and Views from its existing detail request.
- Each category restores only its last successful filter/sort selection across navigation and relaunches.
- Existing playback, Saved, Played, episode, fullscreen, background, AirPlay, Cast, and fallback behavior remains covered.
- All automated tests and release integrity checks pass before push and device installation.
