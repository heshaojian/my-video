# Aiyifan Player Controls and Catalog Discovery Design

## Goal

Make native playback easier to operate with one consolidated trailing action area, and make every native `全部` catalog filterable and sortable across the provider's complete result set. Fix the missing episode-number experience when a serial title is opened from a native catalog.

## Research Findings

The live Aiyifan catalog exposes server-side discovery through its signed APIs:

- `/v3/list/GetSearchCondition` returns region, language, year, quality, and serial-status options plus the dimensions supported by each top-level category.
- `/api/list/FilmType`, `TvType`, `VarietyType`, and `AnimeType` return category-specific genre identifiers.
- `/api/list/Search` accepts category or genre CID, region, language, year, quality, serial status, sort field, direction, page, and page size. It returns a result count, page metadata, and catalog items.
- Sort identifiers are added time `0`, updated time `1`, popularity `2`, and rating `3`; descending direction is `desc=1`.
- Movies do not expose serial status. Drama, variety, and anime expose `全集` and `连载中`.

Live probes confirmed that language and serial-status filters change the server result count, and that descending sort order returns the newest, most popular, and highest-rated results for the respective sort field.

Apple's toolbar guidance treats toolbars as access to frequently used controls, while menus are a space-efficient home for secondary commands. The design therefore keeps frequent episode and route controls visible and moves infrequent playback preferences into one overflow menu.

## Player Behavior

The player retains the standard Back control at the leading edge. All other app-specific controls occupy one trailing action cluster in a single top toolbar:

1. A labeled episode control for serial content, such as `第 12/24 集`.
2. AirPlay.
3. Google Cast.
4. A More menu.

The More menu contains previous episode, next episode, playback speed, sleep timer, autoplay-next, and website fallback. Previous and next commands show disabled states at the ends of a series. The existing AVPlayer transport and fullscreen controls remain system-owned and are not duplicated.

The episode control opens the existing newest-first episode sheet. The selected episode is marked, and the player title area also shows the current episode. While episode metadata is loading, the episode control uses a disabled loading state. It is hidden only when the resolved title is confirmed to be non-serial.

The sleep-timer countdown appears as compact status text beside the trailing cluster and is not an interactive button.

## Episode Defect

Opening a serial title from `全部` must never leave the user with only an unlabeled episode-list glyph. Catalog decoding will preserve the provider's `key`, `isSerial`, `lastKey`, `lastName`, and `videoClassID` values when available, while the playback resolver remains authoritative for the complete episode list.

After resolution:

- `episodes` is populated for serial titles.
- The newest episode is selected unless a saved episode was requested.
- The toolbar exposes the current position and total episode count.
- The episode sheet lists every decoded episode newest-first.

If the provider marks a title as serial but its playlist cannot be loaded, the player shows an explicit retryable episode error rather than silently presenting it as a movie.

## Catalog Controls

Each native `全部` screen has two trailing toolbar controls:

- Filter button using `line.3.horizontal.decrease`, with an active-filter count badge.
- Sort menu using `arrow.up.arrow.down` and the active sort label.

The default sort is `更新时间` descending because Aiyifan is primarily used to find recent updates. Other choices are `添加时间`, `人气`, and `评分`, all descending. The sort selection applies immediately and reloads page one.

The filter button presents a native sheet with grouped single-selection rows:

- Category-specific genre.
- Region.
- Language.
- Year.
- Quality.
- Status for drama, variety, and anime only.

The sheet maintains a draft separate from the applied query. `重置` clears all draft filters. `应用` commits the draft, dismisses the sheet, and reloads page one. Dismissing without applying leaves the current catalog unchanged.

The catalog displays the server-reported result count near the top of the grid. Empty, loading, refresh, pagination, and retry states retain the current query and identify whether the failure occurred while loading filters or results.

Each category keeps its applied query for the current app session. Movie, drama, variety, and anime selections are isolated from one another. No filter preference is written to disk in this version.

## Data Model and Services

Introduce immutable discovery values:

- `CatalogQuery`: category, optional genre CID, region, language, year, quality, status, sort, and direction.
- `CatalogFilterOption`: validated provider title and request value.
- `CatalogFilterSet`: options supported for one top-level category.
- `CategoryCatalogPage`: items, current page, total count, and last-page state.

`CategoryCatalogService` will:

1. Fetch the category page and parse the existing short-lived signing certificate.
2. Fetch and cache filter metadata and category genres for the app session.
3. Build a signed `/api/list/Search` URL from a validated `CatalogQuery`.
4. Decode the nested search result envelope and map optional metadata into `AiyifanItem`.
5. Reject invalid query values, oversized responses, malformed identifiers, insecure artwork, and unsupported provider hosts.

Filtering and sorting occur on the server so the result applies to the complete catalog. The app will not pretend to filter only the pages already loaded.

`CategoryCatalogViewModel` owns applied, draft, and pending queries; filter loading; result loading; pagination; and a request generation. Applying a new query increments the generation and fetches page one without immediately replacing the applied query or visible items. Success atomically publishes the pending query and its first page. Failure discards the pending query, preserves the prior query and items, and exposes a retry action. This also prevents stale responses from replacing newer results.

## Error Handling

- If filters fail but results are available, show the unfiltered catalog and a retry affordance when Filter is opened.
- If a query returns no results, show an empty state with `重置筛选`.
- If a new query fails, preserve the previous visible items and query, and show a retry message.
- If loading another page fails, preserve all loaded items and retry only that page.
- If the provider removes an option, discard that invalid selection the next time filter metadata loads.

## Testing

Use TDD for the implementation and run focused tests while developing. Because this changes the catalog API contract and player navigation surface, run the complete major-change regression before deployment.

The release gate is at least 90% app-source line coverage and 100% feature traceability: every documented user-facing feature must map to at least one automated unit, integration, or UI test. Coverage percentage alone is not sufficient. Generated code, resource catalogs, third-party SDKs, and platform callbacks that cannot be triggered in the simulator are excluded from the percentage only when the release report names the exclusion and supplies an equivalent contract test or physical-device check.

Required automated coverage:

- Query validation and deterministic request signing for every filter and sort field.
- Filter-metadata and genre decoding for all four categories.
- Search result decoding, total counts, pagination, deduplication, and malformed-response rejection.
- Draft versus applied filters, reset, immediate sorting, per-category isolation, stale-response cancellation, refresh, and pagination retry.
- Serial metadata preservation from `全部` results.
- Visible current/total episode count, newest-first episode sheet, and previous/next boundaries.
- Player controls remain in one trailing cluster across supported iPhone sizes without overlap.
- UI flows for filter, apply, sort, clear, empty state, save, play, and episode selection.
- Existing Latest, Saved, Played, search, recommendations, notifications, settings, background refresh, persistence, playback, retry, progress, completion, fullscreen, Picture in Picture, sleep timer, playback speed, autoplay, AirPlay, Cast, and website-fallback behavior.
- Full unit, integration, and UI suite with at least 90% app-source line coverage and no untested documented feature.

The implementation will maintain a feature-to-test matrix in the release verification document. Each row identifies the feature, automated test case, simulator result, physical-device requirement, and final status. A feature is not marked covered merely because its source lines executed indirectly.

Live verification will probe one filtered result in each category and open at least one multi-episode title from `全部`. Physical-device acceptance will verify the compact player toolbar, episode sheet, locked-screen audio and controls, Picture in Picture, AirPlay and Google Cast on real receivers, fullscreen continuity, interruption recovery, and one-handed operation. Hardware-dependent rows remain explicitly pending until they are exercised on the corresponding device; simulator success cannot close them.

## Non-Goals

- Reproducing the provider's desktop filter matrix on iPhone.
- Client-side filtering of partially loaded pages.
- Persisting filter selections across app reinstalls.
- Provider account synchronization.
- Custom playback controls that replace AVPlayer's native transport UI.
- Proxies, downloads, DRM workarounds, or provider-control bypasses.

## Sources

- Aiyifan catalog: <https://www.yfsp.tv/list/anime>
- Apple Human Interface Guidelines, Toolbars: <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- Apple Human Interface Guidelines, Menus: <https://developer.apple.com/design/human-interface-guidelines/menus>
