# Aiyifan Home, API Search, Media Cards, and Stream Quality Implementation Plan

## Objective

Rename Latest to Home, add collapsed global provider API search, consolidate Home/Search/Saved/Played/All cards, report real delivered stream quality, and restore compatibility with the provider's current playback request contract.

## Working Rules

- Write focused failing tests before each implementation slice.
- Keep provider content in its original language and app chrome in English.
- Preserve native playback, mini-player continuity, Saved updates, Played progress, PiP, background audio, AirPlay, Cast, filters, sorting, and explicit website fallback.
- Retain signed-request, HTTPS, redirect, identifier, host, and response-size validation.
- Never log or persist signed URLs, certificates, cookies, manifests, or media segments.
- Run affected tests during development and the complete regression only after the integrated refactor.

## Slice 1: Provider Playback Compatibility

Files:

- Modify `Aiyifan/App/ProviderRequestSigner.swift`.
- Modify `Aiyifan/App/NativePlaybackResolver.swift`.
- Modify `AiyifanTests/NativePlaybackResolverTests.swift`.
- Modify `AiyifanTests/CategoryCatalogTests.swift` if shared request context is covered there.

Steps:

1. Add failing tests for validated two-letter region selection, deterministic US fallback, `lang=none`, and matching detail/playback region parameters.
2. Add a failing resolver test in which the first provider response is invalid and a fresh certificate succeeds once.
3. Add terminal-error tests proving login, preview, unsupported host, invalid identifier, and cancellation are not retried.
4. Implement immutable provider request context and certificate invalidation without weakening request validation.
5. Add a provider-shaped `披荆斩棘2026` fixture covering detail, 30 episodes, latest selection, playback, and episode publication.
6. Run `NativePlaybackResolverTests` and relevant catalog request tests.

## Slice 2: Global Provider API Search

Files:

- Add `Aiyifan/App/ProviderSearchService.swift`.
- Add `Aiyifan/App/ProviderSearchViewModel.swift`.
- Add `AiyifanTests/ProviderSearchTests.swift`.
- Reuse or narrowly expose the catalog response decoder and provider certificate cache.

Steps:

1. Add failing tests for trimmed/encoded `tags`, root `cid=0,1`, relevance ordering, paging, page-size bounds, and existing visibility parameters.
2. Add decoder tests for playable keys, latest episode keys, category metadata, quality labels, scores, unsupported-category exclusion, and malformed results.
3. Add view-model tests for collapsed initial state, explicit submit, empty query rejection, loading, empty results, Retry, pagination, cancellation, and stale-result suppression.
4. Implement a signed API search service using the same ephemeral session, certificate cache, referer, redirect checks, artwork checks, and size limits as catalog loading.
5. Keep search result values immutable and keep all search text outside logs and persistence.
6. Run `ProviderSearchTests` plus catalog decoder/request tests.

## Slice 3: Shared Media Cards and Home UI

Files:

- Add `Aiyifan/App/MediaCard.swift`.
- Modify `Aiyifan/App/BrowserView.swift`.
- Modify `Aiyifan/App/NativeCategoryCatalogView.swift`.
- Modify `Aiyifan/App/SavedItemsView.swift`.
- Modify `Aiyifan/App/PlayedItemsView.swift`.
- Modify `Aiyifan/App/BrowserViewModel.swift` and tab state names.
- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.

Steps:

1. Update UI assertions to require Home as the first tab and Search collapsed by default; verify old Latest labels are absent.
2. Add fixture search launch behavior and UI tests for expand, submit, loading/result, pagination, Save, native Play, empty/error, Cancel, and keyboard dismissal.
3. Add UI assertions that Search uses the same poster-grid identifiers and visible metadata as All.
4. Extract compact poster, poster grid, and progress row variants from the current All card design.
5. Replace duplicated Home, Saved, Played, Continue Watching, New for You, and All markup with the shared component family while retaining existing action identifiers where tests and automation rely on them.
6. Add the collapsed Search and Settings icon controls to the Home header and present native API results inside the Home navigation stack.
7. Verify 44-point controls, stable aspect ratios, long titles, score/save badge separation, Dynamic Type, and VoiceOver labels.
8. Run the affected UI tests on the warmed simulator and capture Home, Search, Saved, Played, and All screenshots at large and compact iPhone sizes.

## Slice 4: Truthful Stream Quality

Files:

- Modify `Aiyifan/App/PlaybackQuality.swift`.
- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `AiyifanTests/PlaybackFeaturesTests.swift`.
- Modify `AiyifanTests/NativePlayerViewModelTests.swift`.
- Modify affected UI quality tests.

Steps:

1. Add failing tests for cinematic tier classification using width and height, including 3840x1608 to 2160p, 1920x804 to 1080p, 1280x536 to 720p, and 864x362 to 480p.
2. Add failing tests for AVAsset variant projection, single playable-track fallback, exact-dimension retention, deduplication, and stable ordering.
3. Add player-model tests for multiple real options, one-tier status, unknown-quality status, 1080p automatic preference, and remembered manual fallback.
4. Implement track presentation-size fallback when AVFoundation exposes no adaptive variants.
5. Keep manual choices only for multiple delivered tiers; expose the one measured tier as read-only status rather than hiding all quality information.
6. Add the `特立独行` regression fixture: catalog metadata `4K`, one 864x362 delivered representation, and a truthful `480p only` player state.
7. Run quality and player-model tests plus affected UI quality scenarios.

## Slice 5: Integration, Documentation, and Delivery

Files:

- Modify `README.md` and `DEVELOPMENT.md` to document Home, API search, shared cards, and catalog-versus-stream quality.
- Update `docs/releases/2026-09-07-daily-watching-verification.md` with verified results only.
- Regenerate `Aiyifan.xcodeproj` after new Swift/test files and run `pod install` if workspace references change.

Steps:

1. Run all unit and integration tests with code coverage on the warmed iPhone simulator.
2. Run the complete UI suite once, including the heavy-user flow.
3. Run static analysis, Release build, plist/project validation, dependency audit, secret scan, and `git diff --check`.
4. Run bounded live provider smoke tests for global search, `特立独行`, and `披荆斩棘2026` without retaining provider secrets or media bodies.
5. Perform correctness, concurrency, accessibility, and security review; resolve all critical/high findings.
6. Capture final simulator screenshots and confirm no badge/control overlap.
7. Commit the implementation. Push only under the user's existing approval boundary, then build the exact commit, install, and launch it on the paired iPhone 14 Pro Max and primary iPhone when available.

## Acceptance Gate

- Home replaces Latest everywhere visible and preserves the four requested category rails.
- Search is collapsed by default and queries the provider API across all supported categories.
- Search results use the identical poster-grid card component as All and remain playable/saveable.
- Home, Saved, Played, Search, and All retain every workflow-specific action with one coherent visual system.
- Multiple real renditions are selectable; one delivered rendition is reported as `<tier> only`; unknown resolution is explicit.
- Provider catalog quality never fabricates a playback option.
- `特立独行` reports its actual available stream tier.
- `披荆斩棘2026` plays natively and exposes its complete episode list.
- Complete tests, analysis, Release build, security review, and device deployment pass before delivery.
