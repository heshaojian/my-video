# Aiyifan Home, API Search, Media Cards, and Stream Quality Design

Date: 2026-09-07

## Objective

Turn the current Latest tab into a polished Home surface, make search a real provider API workflow, unify the visual language of Home, Saved, and Played with the established All-catalog cards, and make playback quality controls report only resolutions the provider actually delivers.

This change also completes the pending provider-request compatibility correction identified while reproducing `披荆斩棘2026`.

## Decisions

- Rename the first tab and its navigation title from Latest to Home.
- Keep Home focused on Continue Watching, saved-title updates, and the four latest categories: Movies, Series, Variety, and Anime.
- Put a search icon in the Home header. Search is collapsed by default and expands inline when requested.
- Search all four supported categories with a server-side provider query. Do not filter the eight Home results in memory.
- Reuse one media-card component family across Home, Search, Saved, Played, and All while preserving workflow-specific information and actions.
- Treat provider catalog quality, such as `4K`, as provider metadata. Treat HLS/DASH rendition dimensions as the authoritative playback-quality source.
- Show selectable resolutions only when the delivered stream contains multiple renditions. Show the actual single available quality when only one rendition exists.
- Update provider request parameters to the current regional/playback contract and retry one invalid provider response with a fresh certificate.

## Considered Approaches

### Recommended: Shared Native Components and Provider API Search

Extract a reusable media-card family, add a dedicated search service over the provider's signed `/api/list/Search` endpoint with a `tags` query, and improve native stream inspection. This keeps search results fully playable and saveable because the API returns the same stable title and episode keys as the All catalog.

This approach has the best consistency, testability, and native behavior without scraping HTML or inventing unavailable resolutions.

### Reuse the Website Search Page

Open the provider's search page in `WKWebView` and intercept selected links. This is smaller, but search, saving, and playback would inherit website behavior and advertisements. It would also recreate the exact WebView limitation this app is intended to avoid.

### Local Search and Provider Quality Labels

Filter cached Home or All results and present `vipResource` values as resolution choices. This appears responsive but misses most of the provider catalog and can falsely claim 4K playback when the delivered stream is lower resolution. It is rejected.

## Navigation and Home

Rename the first library destination to Home in visible labels, accessibility labels, deep-link return behavior, and UI tests. Internal names should also migrate from `latest` to `home` where practical so future work does not preserve misleading terminology.

Home retains the existing dark content-first layout and four category rails. The header contains:

- Aiyifan brand mark and Home title on the leading side.
- Search and Settings icon buttons on the trailing side, each with a 44-point target and accessibility label.
- An inline search field after expansion. Cancel collapses and clears the search state.

Continue Watching remains the first personalized section. New for You remains visible only when saved titles have unseen episode updates. Category rails remain horizontally scrolling and lead to their native All catalogs.

## Shared Media Cards

Introduce a reusable `MediaCard` component family with shared tokens and content rules rather than copying four similar implementations.

All cards use:

- The provider poster at a stable 0.72 aspect ratio.
- A maximum 8-point corner radius.
- Two-line title text with consistent 15-point semibold typography.
- Cyan update or episode metadata, secondary year/region metadata, and the provider score badge when available.
- A top-right contextual action and a top-left score/status badge without overlap.
- A complete rectangular tap target, VoiceOver label/value, and a minimum 44-point action target.

The component has three layout variants:

- `compactPoster`: Home category rails and New for You, with a fixed width that does not shift while images load.
- `posterGrid`: All, Search, and Saved, using the existing adaptive catalog width and metadata density.
- `progressRow`: Played and Continue Watching, with poster, title, episode, progress, elapsed time, and a trailing menu.

Search cards use the All page's poster-grid presentation without visual exceptions. Saved cards use the same poster-grid presentation and add saved-specific alert/update actions through a context menu. Played cards keep their progress-first horizontal form but use the same poster, typography, spacing, corner, metadata, and action conventions. Destructive actions remain in menus or explicit confirmation flows.

## Provider API Search

Add an immutable `ProviderSearchQuery` and a dedicated `ProviderSearchService`. The request uses the existing signed provider transport and host validation with:

- Path `/api/list/Search`.
- `tags` set to the trimmed user query.
- Root catalog `cid=0,1` so results cover Movies, Series, Variety, and Anime.
- Provider relevance ordering, descending direction, and paginated page/size values.
- Existing cinema, visibility, free-status, and vertical-content bounds.

The service reuses the catalog response decoder because this endpoint returns stable `key`, `lastKey`, category, score, artwork, and quality metadata. Results outside the four supported category paths are excluded after decoding.

Search behavior:

1. Search is collapsed on first appearance.
2. Tapping Search expands and focuses the field.
3. Submitting a nonempty query starts a provider request; typing alone does not issue network traffic.
4. A new submission cancels the previous request and stale results cannot replace current results.
5. Results appear in a native adaptive grid and support Play, Save, score display, and pagination.
6. Cancel clears the query and results, dismisses the keyboard, and returns to Home.

Queries are trimmed, limited to 80 characters, and reject control characters. Empty queries never reach the network. Response sizes, page sizes, artwork hosts, identifiers, and redirects retain existing bounds.

## Stream Quality

The provider exposes two different concepts:

- Catalog quality metadata (`vipResource`), which may describe the source or editorial label.
- Delivered playback renditions, which determine what AVPlayer can actually select.

The player must never turn catalog metadata into a synthetic rendition. For `特立独行`, the provider currently labels the title 4K while delivering one 864x362 video representation. That is a single approximately 480p-class cinematic rendition, not a selectable 4K stream.

Extend quality inspection as follows:

1. Read adaptive variants from `AVURLAsset.variants`.
2. If variants are empty, inspect the playable video track presentation size as a single-rendition fallback.
3. Normalize cinematic dimensions by both width and height so 1920x804 is labeled 1080p-class and 864x362 is labeled 480p-class.
4. Deduplicate tiers and sort highest first.
5. Preserve exact width, height, and bitrate internally for AVPlayer preferences.

Quality menu behavior:

- Multiple delivered tiers: show Automatic plus every real selectable tier.
- One delivered tier: show Automatic and a nonselectable `<tier> only` status.
- Unknown dimensions: show Automatic and `Stream quality unavailable`.
- Catalog cards may continue to display the provider's `4K` label as metadata, but the player shows the measured stream tier and does not claim the label is being delivered.

Default behavior remains Automatic preferring exact 1080p, otherwise the highest delivered tier. A remembered manual preference applies only when a compatible tier exists and never restarts playback.

## Provider Playback Compatibility

Introduce a small validated request context for the provider region and playback language:

- Use the device's two-letter region when valid, with `US` as the deterministic fallback.
- Include `lang=none` in playback requests, matching the provider's current native request contract.
- Use the same validated region for detail and playback requests.
- Preserve all current HTTPS, signed-request, redirect, host, identifier, and response-size validation.

If a request returns a structurally invalid provider response, invalidate the cached provider certificate and retry the complete resolution once. Do not retry login-required, preview-only, unsupported-host, malformed-identifier, or cancellation failures. Playlist recovery retains its existing four bounded attempts.

## State and Error Handling

- Home content remains visible while search is merely expanded but not submitted.
- A search loading indicator belongs to the result surface and does not block tab navigation or active playback.
- Empty search results say `No titles found` and retain the submitted query for editing.
- Network failure offers Retry without discarding the query.
- Search cancellation and tab changes cancel obsolete work.
- Quality-inspection failure is nonterminal and never stops an otherwise playable video.
- A single-rendition stream remains playable even though manual switching is unavailable.
- Provider metadata disagreements are presented truthfully and never resolved by fabricating options.

## Security and Privacy

- Never log or persist signed URLs, provider certificates, cookies, HLS/DASH manifests, or media segments.
- Search requests use the same provider allowlist, ephemeral session, safe redirects, response limits, and artwork validation as catalog requests.
- Search text is treated as untrusted input and encoded through `URLQueryItem`.
- Media quality inspection does not download or rewrite manifests manually in production.
- No third-party analytics or new external dependencies are introduced.

## Test Strategy

Use TDD for each implementation slice, followed by one complete major-change regression.

Required unit and integration coverage:

- Search request parameters, input bounds, signature inputs, paging, cancellation, stale-result rejection, supported-category filtering, decoding, empty results, and retry behavior.
- Home rename and library-tab routing.
- Shared card variants expose the expected score, update, metadata, progress, Save, alert, and Played actions.
- Catalog, Home, Saved, and Played cards preserve stable dimensions and accessibility identifiers.
- Adaptive variants, single-track fallback, cinematic tier normalization, deduplication, automatic 1080p preference, single-tier status, and unknown-quality status.
- `特立独行` fixture: provider catalog says 4K while one 864x362 stream produces a truthful 480p-only state.
- Current provider region and playback-language parameters.
- One fresh-certificate recovery after an invalid response, with forbidden errors never retried.
- `披荆斩棘2026` fixture: current detail, 30-episode playlist, latest-episode selection, playback response, and populated episode control.

Required UI flows:

- Home is the first tab and contains only the intended four latest category rails plus personalized sections when applicable.
- Search is initially collapsed, expands from the icon, submits to the stubbed API, paginates, plays and saves a result, handles empty/error states, and collapses on Cancel.
- Home, Search, Saved, Played, and All render the shared card language without overlapping badges or controls on iPhone 14 Pro Max and a smaller iPhone viewport.
- Played filtering, progress, resume, restart, mark watched, removal, and clear confirmation remain functional.
- Single-quality and multi-quality player menus report correct states.

The major regression includes all unit tests, all UI tests, static analysis, a Release build, provider contract smoke tests, and simulator screenshots. Physical-device verification covers the corrected live titles, quality presentation, background/lock-screen playback, Picture in Picture, AirPlay, and mini-player continuity. Google Cast receiver quality remains separately hardware-verified.

## Acceptance Criteria

- The first tab is named Home everywhere visible to the user.
- Home, Search, Saved, Played, and All share one coherent card system while preserving each workflow's necessary information and actions.
- Search is collapsed by default and returns paginated, playable, saveable results from the provider API across all four supported categories.
- Search never filters only the currently loaded Home rows.
- Every player exposes Automatic quality status; manual choices appear only for real delivered alternatives.
- A provider 4K catalog label never creates a false 4K playback option.
- `特立独行` reports its actual single delivered tier instead of an empty or misleading selection list.
- `披荆斩棘2026` resolves native playback and a populated 30-episode list under the current provider contract.
- Existing Saved updates, Played progress, mini-player continuity, fullscreen, Picture in Picture, lock-screen controls, AirPlay, Cast, filters, sorting, and explicit website fallback remain functional.
