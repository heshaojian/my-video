# Aiyifan Player Controls and Catalog Discovery Implementation Plan

## Objective

Consolidate app-specific player controls into one trailing toolbar, expose current and total episode numbers for serial titles opened from `全部`, and add provider-backed filtering and sorting to all four native catalogs. Raise app-source line coverage from the current 84.12% to at least 90% while mapping every documented feature to an explicit test.

## Working Rules

- Use TDD for every behavior change: add a failing test, run it to confirm RED, implement the smallest complete change, then refactor and rerun GREEN.
- Use focused tests during each slice and the complete unit/UI regression after the major source change is assembled.
- Keep provider requests signed, HTTPS-only, bounded by response-size limits, and free of persisted certificates, signed URLs, cookies, or media URLs.
- Preserve native playback, fullscreen continuity, background audio, Picture in Picture, Saved/Played data, newest-first episodes, AirPlay, Cast, and explicit website fallback.
- Do not claim hardware behavior verified from the simulator.

## Slice 1: Catalog Query Contract

Files:

- Modify `Aiyifan/App/CategoryCatalogService.swift`.
- Modify `Aiyifan/App/AiyifanItem.swift`.
- Modify `AiyifanTests/CategoryCatalogTests.swift`.

Steps:

1. Add failing tests for immutable `CatalogQuery`, four sort identifiers, descending direction, movie status exclusion, and query-value validation.
2. Add failing deterministic-signature tests covering genre CID, region, language, year, `vipResource`, `isserial`, sort, page, and page size.
3. Replace `/api/list/index` request construction with validated `/api/list/Search` construction and preserve stable parameter ordering.
4. Add failing decoder tests for the nested `recordcount`, `maxpage`, and `result` response; serial metadata; numeric/string metadata; malformed identifiers; insecure artwork; and oversized payloads.
5. Extend `AiyifanItem` with optional `isSerial`, `latestEpisodeKey`, `latestEpisodeTitle`, category path, genre, language, quality, popularity, and rating fields while keeping Codable defaults compatible with existing Saved/Played data.
6. Extend `CategoryCatalogPage` with total count and derive last-page state from provider metadata plus page size.
7. Run `CategoryCatalogContractTests` and existing Saved/Played migration tests.

## Slice 2: Provider Filter Metadata

Files:

- Modify `Aiyifan/App/CategoryCatalogService.swift`.
- Modify `Aiyifan/App/AiyifanCategory.swift`.
- Modify `AiyifanTests/CategoryCatalogTests.swift`.

Steps:

1. Add failing tests for `/v3/list/GetSearchCondition` decoding and the four category-specific genre endpoints.
2. Add `CatalogFilterOption` and `CatalogFilterSet` value types with strict title/value length and character validation.
3. Map movie, drama, variety, and anime to their live genre endpoints without exposing unsupported categories.
4. Fetch the category HTML once per metadata session, parse the existing certificate, load search conditions and genres, and cache the validated filter set in memory by category.
5. Keep status absent for movies and available as `全集` or `连载中` for drama, variety, and anime.
6. Add failure tests for missing condition groups, invalid genre paths, unsupported values, stale provider options, and independent category caches.
7. Run the catalog contract suite and a live read-only metadata smoke probe without logging signing material.

## Slice 3: Transactional Catalog State

Files:

- Modify `Aiyifan/App/CategoryCatalogViewModel.swift`.
- Modify `Aiyifan/App/CategoryCatalogService.swift` fixture support.
- Modify `AiyifanTests/CategoryCatalogTests.swift`.

Steps:

1. Add failing tests for filter loading, draft selection, reset, dismiss-without-apply, transactional Apply, immediate sorting, and active-filter count.
2. Add failing tests proving that a failed new query preserves the prior query and items, retry publishes atomically, and an older response cannot overwrite a newer query.
3. Update `CategoryCatalogServing` to accept `CatalogQuery` and expose filter metadata through a separate method.
4. Implement applied, draft, and pending query state; generation-based cancellation; result count; and per-category session state.
5. Reset pagination only after a successful first page, while preserving existing load-more retry and de-duplication behavior.
6. Expand fixtures to provide category-specific filters, deterministic result counts, filtered empty results, request failures, and serial catalog items.
7. Run all catalog view-model tests, including three repeated stale-response runs.

## Slice 4: Native Filter and Sort Interface

Files:

- Modify `Aiyifan/App/NativeCategoryCatalogView.swift`.
- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.

Steps:

1. Add failing UI tests for Filter and Sort buttons in each `全部` category.
2. Add failing flows for selecting a genre and language, resetting a draft, dismissing without applying, applying multiple filters, changing sort, showing active-filter count, reporting result count, and clearing an empty query.
3. Add top-bar Filter and Sort controls using SF Symbols, stable 44-point hit targets, labels, and accessibility identifiers.
4. Build a native filter sheet with grouped single-selection pickers, `重置`, `取消`, and `应用`; omit unsupported status controls for movies.
5. Show the server result count above the grid and retain explicit initial, empty, refresh, first-page failure, load-more failure, retry, and end states.
6. Keep cards directly playable and saveable with the current stores.
7. Run the new UI flows on iPhone 17 Pro and the compact iPhone 16e simulator; inspect screenshots for clipping, overlap, and dynamic-content layout.

## Slice 5: Episode Metadata and Resolver Correctness

Files:

- Modify `Aiyifan/App/NativePlaybackResolver.swift`.
- Modify `AiyifanTests/NativePlaybackResolverTests.swift`.
- Modify `AiyifanTests/NativePlayerViewModelTests.swift`.

Steps:

1. Add a failing catalog-to-resolver test using a serial search result with `key`, `isSerial`, `lastKey`, `lastName`, and `videoClassID`.
2. Add tests proving the complete playlist is decoded, sorted newest-first, and selects a saved episode or newest episode deterministically.
3. Add a serial hint to playback resolution so the player can represent a loading episode state before the playlist returns; keep provider detail as the final authority.
4. Distinguish retryable playlist failure from a confirmed non-serial title instead of silently returning an empty episode list.
5. Add failure coverage for invalid category IDs, empty playlists, malformed episode keys, duplicate episodes, and cancellation.
6. Run resolver and player-view-model tests, then a live read-only serial probe opened from the current `全部` result contract.

## Slice 6: Consolidated Player Toolbar

Files:

- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.

Steps:

1. Add failing UI assertions for one top toolbar, trailing episode count, AirPlay, Cast, More, and the absence of the old second app-control row.
2. Add failing tests for `第 current/total 集`, loading, single-episode, movie, previous/next boundary, retry, and episode-selection states.
3. Keep Back leading and move all other app-specific commands into one trailing cluster.
4. Keep the labeled episode control, AirPlay, Cast, and More visible; move previous, next, speed, sleep timer, autoplay, and website fallback into More.
5. Preserve the system AVPlayer transport, fullscreen, and Picture in Picture controls and the existing session-lifetime fix.
6. Verify layouts at compact and large widths with accessibility-frame assertions and screenshots; use menu grouping and concise labels to prevent overlap.
7. Run player unit/UI tests and repeat the fullscreen enter/exit test three times.

## Slice 7: Coverage Expansion and Feature Traceability

Files:

- Extend existing test files by owning feature; add a focused test file only when no current owner exists.
- Update `docs/releases/2026-09-07-daily-watching-verification.md`.

Current coverage priorities:

- `BackgroundRefresh.swift`: 11.90%.
- `AiyifanApp.swift`: 52.03%.
- `NowPlayingCoordinator.swift`: 53.41%.
- `Casting.swift`: 59.52%.
- `BrowserViewModel.swift`: 66.67%.
- `CategoryCatalogService.swift`: 71.79% before this feature.
- `LibraryServices.swift`: 72.46%.
- `NativePlaybackResolver.swift`: 72.65%.
- `NativePlayerView.swift`: 79.55%.

Steps:

1. Extract protocol-backed seams only where required to drive deterministic lifecycle, notification, command-center, network, timer, and SDK states.
2. Add direct tests for background refresh registration, success, expiration, rescheduling, and partial failure.
3. Add app-routing and scene-lifecycle tests for notification destinations, settings presentation, background transitions, and persistence handoff.
4. Add Now Playing tests for metadata, artwork fallback, play/pause, seek, rate, previous/next, interruptions, route changes, and clear/detach.
5. Add Cast tests for disconnected, connecting, connected, load, resume handoff, pause/play/seek, queue errors, retries, and local fallback.
6. Fill BrowserViewModel and LibraryServices gaps for all Latest, Saved, Played, search, recommendation, notification, cache, migration, and error states.
7. Add explicit test-matrix rows for every README feature and every requirement in the approved design.
8. Run coverage after each ownership group and continue until app-source line coverage is at least 90% without counting Pods, generated code, or test targets.
9. Review any file below 80% and document why remaining lines are platform-only or add tests until the gap is justified.

## Slice 8: Major Regression and Delivery

1. Run the complete unit and UI suite on iPhone 17 Pro with code coverage.
2. Run critical filter, sort, serial playback, fullscreen, progress, Saved, and Played workflows three consecutive times.
3. Run the deterministic 50-plus-action heavy-user flow on iPhone 17 Pro and iPhone 16e.
4. Run Release simulator build and `xcodebuild analyze`.
5. Run dependency status, secret scan, plist validation, project-generation validation, and `git diff --check`.
6. Perform read-only live smoke checks for filter metadata, all four category queries, each sort order, a multi-filter query, and a multi-episode title.
7. Publish the feature-to-test matrix with exact test counts, 90% or higher app-source coverage, exclusions, simulator results, and hardware-pending rows.
8. Review the complete diff for correctness, privacy, security, accessibility, and regression risk; address all critical and high findings.
9. Commit focused changes using Conventional Commit messages, push `master`, then build, install, and launch on John's paired iPhone.
10. Run reachable physical-device checks. Leave Apple TV and Android TV receiver rows pending until the corresponding hardware is available and tested.

## Acceptance Gate

- Every `全部` category has provider-backed Filter and Sort controls over the complete catalog.
- `更新时间` descending is the default, and every filter/sort change is transactional and pagination-safe.
- Serial titles opened from `全部` show a current/total episode label and a complete newest-first episode sheet.
- All app-specific player operations except Back are grouped in one trailing action cluster with no overlap on supported iPhone sizes.
- Existing Saved, Played, progress, fullscreen, background audio, Picture in Picture, AirPlay, Cast, notifications, search, settings, and website fallback behavior remains covered.
- All automated tests pass, every documented feature has a named test, and app-source line coverage is at least 90%.
- Signed provider data and media URLs are not persisted or logged.
- Hardware-dependent results are reported honestly and are not inferred from simulator tests.
