# Aiyifan Native Category Catalog Design

## Goal

Replace the WebView opened by each `全部` action with a native, paginated catalog where every title can be played with the native player or saved to the existing local library.

## Product Behavior

- `全部` opens a native category screen for `电影`, `电视剧`, `综艺`, or `动漫`.
- The screen initially loads 24 titles and automatically requests the next page near the end of the grid.
- Pull to refresh clears the current pagination session and reloads page one.
- Each card shows available provider metadata: poster, title, update label, year, and region.
- Tapping a card opens the existing native player.
- The bookmark control uses the shared `SavedItemsStore`, so changes appear immediately on Latest, the category screen, and Saved.
- Back returns to Latest without replacing the three-tab navigation or losing its current state.
- Loading, empty, retry, refreshing, and end-of-list states are explicit.
- WebView remains available only through the existing playback fallback.

## Provider Integration

Add a focused `CategoryCatalogService` rather than parsing or modifying WebView content.

1. Fetch the selected public category page and parse its existing playback certificate with `PlaybackCertificateParser`.
2. Map the category to the provider CID already used by its feed:
   - `电影`: `0,1,3`
   - `电视剧`: `0,1,4`
   - `综艺`: `0,1,5`
   - `动漫`: `0,1,6`
3. Sign the provider's `/api/list/index` request with the existing signature algorithm and request `page`, `size`, `isn`, and `isfree` parameters.
4. Validate HTTP status, response size, response envelope, item identifiers, and HTTPS media-page/artwork URLs.
5. Convert the provider response into existing `AiyifanItem` values. Do not persist the certificate, signed request URL, cookies, or stream URLs.

The catalog treats a page containing fewer than 24 valid items as the end. It de-duplicates item IDs across pages and ignores stale responses from an earlier refresh.

## Components

- `CategoryCatalogServing`: async protocol for one validated page request.
- `CategoryCatalogService`: production certificate bootstrap, signing, network validation, and decoding.
- `CategoryCatalogPage`: immutable page result with items and end state.
- `CategoryCatalogViewModel`: owns category, page number, loading state, retry state, refresh generation, and de-duplication.
- `NativeCategoryCatalogView`: adaptive native grid and shared Save/play actions.
- `BrowserViewModel`: replaces category WebView selection with a native selected-category destination.

The new files stay below the repository's 800-line limit and follow the existing local-first SwiftUI patterns.

## Failure Handling

- Page-one failure shows a retryable unavailable state without entering WebView.
- Later-page failure keeps already loaded items visible and offers a retry row.
- Refresh failure keeps the current successful list visible and shows a concise error.
- Repeated load-more triggers for the same page are ignored.
- Cancellation or a new refresh prevents obsolete responses from updating the grid.
- Native playback failures continue to offer the existing explicit website fallback.

## Testing

Tests are written before implementation.

### Unit

- Category-to-CID mapping and deterministic signed-list URL construction.
- Valid response decoding and metadata mapping.
- Invalid envelope, oversized response, malformed item, and insecure URL rejection.
- Initial load, pagination, de-duplication, end detection, retry, refresh reset, and stale-response suppression.

### UI

- Every `全部` action opens the matching native screen and no WebView.
- A category card opens native playback.
- Saving and removing a category card updates Saved and survives relaunch.
- Scrolling loads another page without duplicating existing cards.
- Initial and subsequent page failures expose working retry controls.

### Regression

- Run the full unit and UI suite with coverage after implementation.
- Run native category open, save, playback, and pagination three consecutive times.
- Re-run the 50-plus-action heavy-user scenario on iPhone 17 Pro and iPhone 16e.
- Confirm app-source coverage remains at least 80 percent.
- Run Release build, Xcode static analysis, live category API smoke checks, dependency review, secret scan, and diff review before device deployment.

## Acceptance Criteria

- `全部` never opens WebView.
- The user can browse beyond the eight homepage titles without leaving the native app.
- Every valid catalog title supports native play and Save/Favorite.
- Saved state remains consistent across Latest, category catalog, and Saved after relaunch.
- Pagination is stable under repeated scrolling, refresh, failure, and retry.
- Existing playback, ad muting, history, notifications, AirPlay, Google Cast, and explicit website fallback remain unchanged.
