# Aiyifan Native Category Catalog Implementation Plan

## Objective

Replace every Latest `全部` WebView route with a native, paginated category catalog that supports shared Save/Favorite state and the existing native player.

## Constraints

- Preserve the three-tab Latest, Saved, and Played structure.
- Keep WebView available only as the explicit playback fallback.
- Reuse the provider certificate parser and signing rules without persisting or logging credentials or signed URLs.
- Keep production URLs HTTPS-only and validate provider response sizes and envelopes.
- Write failing tests before each implementation slice and retain at least 80 percent app-source coverage.

## Slice 1: Contract And Request Validation

1. Add unit tests for the four category CID mappings.
2. Add unit tests for deterministic `/api/list/index` signing and unsupported-host rejection.
3. Add decoder tests for metadata mapping, invalid envelopes, malformed items, insecure artwork, and oversized payloads.
4. Implement `CategoryCatalogPage`, `CategoryCatalogServing`, request construction, response decoding, and the production service.
5. Run the new unit tests, then the complete unit suite.

## Slice 2: Pagination State

1. Add unit tests for initial load, next-page loading, de-duplication, end detection, retry, refresh reset, and stale response suppression.
2. Implement `CategoryCatalogViewModel` with immutable result replacement, request generation tracking, and duplicate-load guards.
3. Add deterministic fixture pages for UI testing.
4. Run pagination tests, then the complete unit suite.

## Slice 3: Native Catalog UI

1. Replace the existing UI assertion that `全部` opens WebView with failing native-navigation assertions.
2. Add UI tests for all four category destinations, native playback, Save/Remove propagation, relaunch persistence, pagination, and retry states.
3. Add `NativeCategoryCatalogView` with an adaptive poster grid, pull-to-refresh, loading, empty, retry, load-more failure, and end states.
4. Route `LatestHomeView` category actions through native navigation while preserving Latest state on Back.
5. Remove the obsolete category-to-WebView transition from `BrowserViewModel`.
6. Run each new UI flow three consecutive times on the primary simulator.

## Slice 4: Power-User Regression

1. Extend the existing heavy-user scenario to browse a category, paginate, save, play, return, and verify Saved state.
2. Run the full unit and UI suite on iPhone 17 Pro with code coverage.
3. Run the heavy-user scenario on iPhone 16e.
4. Confirm app-source line coverage is at least 80 percent.
5. Run Release build, Xcode static analysis, dependency audit, secret scan, and diff review.
6. Smoke-test signed page-one and page-two catalog requests for all four live categories without recording certificate or signed URL values.

## Slice 5: Delivery

1. Update the release verification record with test counts, coverage, simulator results, live API checks, and any hardware limitations.
2. Commit focused implementation, test, and documentation changes with Conventional Commit messages.
3. Push `master` to the existing GitHub remote.
4. Build, install, and launch on John's paired iPhone.
5. If iOS Developer Mode remains disabled, report that exact device-side blocker while leaving the tested build ready to install.

## Acceptance Gate

- `全部` opens no WebView in any category.
- Page one contains 24 valid items when the provider supplies them, and scrolling can load later pages without duplicates.
- Catalog items can be saved, removed, reopened after relaunch, and played natively.
- Latest, Saved, Played, playback, muted provider ads, episode ordering, AirPlay, Google Cast, and explicit website fallback all retain their tested behavior.
- All automated tests pass and app-source coverage remains at or above 80 percent.
