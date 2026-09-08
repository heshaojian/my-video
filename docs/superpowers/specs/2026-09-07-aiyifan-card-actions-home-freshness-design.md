# Aiyifan Card Actions and Home Freshness Design

Date: 2026-09-07

## Objective

Ensure every poster card exposes its expected contextual action, keep Home aligned with the provider's latest-update ordering, and finish the approved expanded Search layout without disrupting playback or library state.

## Confirmed Defects

The catalog supplies a Save action for every item, including `披荆斩棘 2026`. The missing control is a layout defect: the shared grid card anchors overlays to a container whose width is capped but not deterministic. Poster content can therefore establish an inconsistent intrinsic width and place the trailing Save action outside the visible grid cell.

Home sends the correct provider query: page one, eight items, `Last Updated`, descending. The stale content comes from lifecycle behavior. Once `latestItems` is nonempty, the current view model skips subsequent refreshes. Returning to Home or bringing the app back to the foreground checks saved-title updates but does not refresh the Home feed. Cached fallback results can consequently remain visible long after they are fresh.

## Card Layout

`PosterMediaCard` remains the shared component for Home, Search, Saved, and All.

- Give compact and grid posters deterministic widths derived from their layout container.
- Attach score/status and contextual-action overlays directly to the poster surface.
- Keep the score at the poster's top-leading corner and the action at its top-trailing corner.
- Preserve a minimum 44-point action target even when score, year, region, or update metadata is absent.
- Keep title and metadata below the poster from influencing overlay geometry.
- Preserve current identifiers, Save behavior, Saved removal behavior, and VoiceOver labels.

The grid container continues to use adaptive columns, but each card fills exactly one assigned grid cell. Right-edge cards must not be clipped at supported iPhone widths.

## Home Freshness

The provider remains authoritative for ordering. Aiyifan will not locally reorder provider results by date-like subtitle strings because formats vary across movies, series, variety, and anime.

Home uses a 15-minute freshness interval:

1. Initial Home presentation refreshes when there is no in-memory feed.
2. Returning to Home refreshes when the most recent successful provider refresh is older than 15 minutes.
3. Bringing the app into the active foreground refreshes Home under the same stale-data rule.
4. Pull-to-refresh always forces a provider refresh.
5. A refresh keeps existing cards visible and shows a compact progress indicator instead of replacing the feed with a blank loading screen.
6. If one category fails, its cached results remain visible and are explicitly identified as saved results.
7. If every category fails and cached data exists, Home retains that data and exposes the failure state without discarding content.

The existing background task for saved-title notifications remains independent. Home freshness must not schedule duplicate notifications or interfere with an active native player, mini-player, Picture in Picture, AirPlay, or Cast session.

## Expanded Search Control

Complete the previously approved Search refinement:

- The expanded field fills available width and has a stable 50-point minimum height.
- Search submission sits inside the field at the trailing edge.
- Clear Text appears inside the field only when text exists.
- A compact close icon outside the field collapses and clears Search.
- Keyboard Search and the submit icon call the same provider API action.
- All controls retain at least 44-point targets and stable accessibility identifiers.

## Error Handling

- Home refresh cancellation is not presented as a network error.
- Failed refreshes retain usable existing content.
- The stale-data message appears near the Home feed rather than only after all category sections.
- Search validation and request failures retain the submitted text and existing retry behavior.
- Card action visibility never depends on provider metadata or artwork loading success.

## Test Strategy

Use test-first implementation, then run one major-change regression.

Unit and integration coverage:

- Fresh in-memory Home data does not issue an unnecessary request.
- Data older than 15 minutes refreshes on Home return and foreground activation.
- Forced pull-to-refresh bypasses the freshness interval.
- Successful refresh updates the freshness timestamp.
- Partial and total provider failures retain cached results and report staleness correctly.
- Home continues requesting eight items per category with last-updated descending ordering.
- Search submission, validation, and collapse behavior remain unchanged apart from layout.

UI coverage:

- Every visible All/Variety fixture card exposes an onscreen Save action, including cards without scores.
- Save actions remain inside poster bounds on iPhone 14 Pro Max, iPhone 17 Pro Max, and a smaller supported iPhone viewport.
- Home pull-to-refresh replaces stale fixture results while preserving visible content during loading.
- Foregrounding stale Home content triggers refresh; foregrounding fresh content does not.
- Expanded Search uses the available width, supports clear/submit/close, and does not overlap the header or results.
- Existing Home, Search, Saved, Played, All, native playback, mini-player, episode, quality, fullscreen, background playback, and casting flows remain passing.

## Acceptance Criteria

- `披荆斩棘 2026` and every other catalog item show an accessible Save control before being saved.
- Card actions remain visible regardless of poster dimensions or missing score metadata.
- Home displays the provider's current last-updated results after launch, a stale Home revisit, foreground activation, or manual refresh.
- Home does not repeatedly fetch while its data is less than 15 minutes old.
- Existing cards remain usable during refresh and cached fallback is clearly disclosed.
- Expanded Search is full-width, stable, and comfortable to use on both target iPhones.
- The complete automated regression passes before deployment.
