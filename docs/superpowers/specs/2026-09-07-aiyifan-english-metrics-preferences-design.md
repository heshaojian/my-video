# Aiyifan English Interface, Viewer Metrics, and Catalog Preferences Design

Date: 2026-09-07

## Objective

Make Aiyifan's application interface English, remove the Latest search field, surface trustworthy provider scores while browsing, show viewer metrics during native playback, and preserve each category's manually applied filter and sort choices.

Provider-supplied titles, episode names, descriptions, genres, and filter option values remain in their original language. Only app-owned navigation, controls, labels, messages, and accessibility text are translated.

## Provider Data

Live provider probes confirm these fields:

- `/api/list/Search` returns `score`, `rating`, and `hot` for catalog results.
- `/v3/video/detail` returns `good`, `favoriteCount`, `score`, and `view`.

The app interprets them as Likes, Favorites, Score, and Views. Values are display-only. This change does not add like, favorite, or rating submission because those actions require provider account behavior outside the app's current authenticated API contract.

## Latest Data Source

Replace the injected `slide-list` Latest source with the existing signed catalog search endpoint using:

- The matching top-level category.
- Updated-time sorting.
- Descending direction.
- Page one with eight items.

This provides score metadata without one detail request per card. The four category requests continue to run concurrently, retain independent cache fallback, and preserve the current four-section homepage.

The shared provider certificate should be cached for the refresh operation so Latest does not fetch and parse the same configuration page four times. Failed categories continue to use their own cached results.

## Interface Language

Translate all app-owned text to English, including:

- Movies, Series, Variety, Anime, Latest Updates, and All.
- Latest, Saved, and Played tab text.
- Catalog filter and sort names, result counts, loading, empty, failure, retry, reset, apply, and cancel states.
- Player episode loading, episode selection, and episode number formatting.
- Settings, notifications, Saved/Played actions, Cast controls, and accessibility labels.

Do not translate provider-supplied content or filter-option labels. Stable internal identifiers use enum raw values or explicit identifiers rather than translated display text.

## Search Removal

Remove the navigation search field from Latest. Keep the existing category, language, year, and watch-state filter control.

When a Latest filter is active, the result section is labeled `Filtered Titles`. Its clear action resets the complete filter instead of clearing only a hidden query value. The underlying search engine may remain available for a future search restoration, but no search control is visible or focusable.

## Scores and Viewer Metrics

Add a validated optional `score` field to `AiyifanItem`. Keep provider `rating` separate because the provider exposes both values and uses rating for catalog ordering. Scores must be finite values from 0 through 10. Counts must be nonnegative integers within the accepted response bounds.

Latest and catalog cards show a compact star plus score when a valid score exists. Missing values take no space and never display a fabricated zero.

Extend the existing playback detail response with an immutable metrics value containing:

- Likes from `good`.
- Favorites from `favoriteCount`.
- Score from `score`.
- Views from `view`.

The native player shows a slim metrics row between the app toolbar and video surface after detail metadata resolves. Use SF Symbols and English labels. Counts use compact English formatting such as `9.8K`, `170K`, and `1.2M`. Missing metrics are omitted independently.

No additional network request is made for player metrics because native playback already requests `/v3/video/detail`.

## Filter and Sort Persistence

Add a small versioned preference store backed by `UserDefaults`. Store one successfully applied `CatalogQuery` snapshot per `AiyifanCategory` using category raw values, never translated display names.

- Restore the saved query before the first catalog request so the opening page matches the visible selection.
- Persist sort field and direction immediately after a successful sort request.
- Persist filter values only after Apply succeeds.
- Cancel discards draft edits and retains the previous applied values.
- Clear Filters removes saved filters but retains the category's selected sort and direction.
- Each category has independent preferences.
- Validate restored values against request rules. After filter metadata loads, discard provider options that no longer exist and reload only when the effective query changed.
- Corrupt or unsupported stored versions are ignored without affecting catalog loading.

## Failure and Security Behavior

- Reject malformed, negative, non-finite, oversized, or out-of-range metric values.
- Keep HTTPS, supported-host, redirect, response-size, and identifier validation unchanged.
- A metrics decoding failure must not prevent playback when the playback-critical detail fields are valid; invalid individual metrics are omitted.
- A Latest category failure falls back only to that category's cache.
- Preference decoding or validation failure falls back to the default latest-updated query.

## Test Strategy

Use focused tests during implementation and the full release suite after this major change.

Required automated scenarios:

- Latest uses updated-descending catalog queries and receives score metadata.
- Latest and catalog cards show valid scores and omit invalid or missing scores.
- Detail decoding maps all four metrics and independently omits malformed optional values.
- Player metrics use correct icons, labels, compact counts, and no extra detail request.
- Search is absent and no longer focusable; Latest filtering still works and clears completely.
- All app-owned visible and accessibility strings are English.
- Provider titles, episodes, descriptions, genres, and filter values remain unchanged.
- Applied filter/sort values survive catalog dismissal and app relaunch independently per category.
- Cancel, Apply, Clear Filters, stale options, corrupt storage, request failure, and concurrent query behavior preserve the correct committed values.
- Existing native playback, Saved, Played, episode, fullscreen, Picture in Picture, background audio, AirPlay, Cast, and website fallback scenarios remain green.

## Acceptance Criteria

- No search field appears on Latest.
- No app-owned Chinese text remains in the interface or accessibility labels.
- Provider content remains unmodified.
- Latest and All cards display provider scores when available.
- The native player displays available Likes, Favorites, Score, and Views from the existing detail request.
- Every category restores its last successfully applied filters, sort field, and sort direction after navigation and relaunch.
- Focused tests and the complete major-change regression pass before push or device deployment.
