# Aiyifan Uniform Poster Sizing Implementation Plan

## Objective

Prevent provider artwork with unusual dimensions from widening or overlapping shared media cards while preserving the current card actions, metadata, and navigation.

## Task 1: Add the layout regression

Files:

- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.
- Modify `Aiyifan/App/MediaCard.swift` only as needed to expose a stable poster accessibility frame.

Steps:

1. Add a UI assertion that adjacent Saved posters have equal width and height and do not overlap.
2. Use existing fixture content with different source artwork dimensions.
3. Run the focused test and confirm it fails against the current layout.

## Task 2: Constrain the shared poster container

Files:

- Modify `Aiyifan/App/MediaCard.swift`.

Steps:

1. Make the grid column determine the poster width.
2. Apply the existing `0.72` portrait ratio to that constrained container.
3. Center-crop and clip artwork inside the container so intrinsic image dimensions cannot affect layout.
4. Keep compact-card sizing and all overlays unchanged.
5. Re-run the focused regression and make it pass.

## Task 3: Verify shared-card consumers

Steps:

1. Run the full unit suite.
2. Run the relevant UI suite on an iPhone simulator, covering Home, Search, Saved, Played, and All.
3. Inspect screenshots for equal poster frames, non-overlapping columns, and correctly anchored score/action badges.
4. Run `git diff --check`, a device build, and a scoped code/security review.

## Task 4: Deliver

Steps:

1. Commit only the poster-layout fix and its tests, preserving unrelated local changes.
2. Push the verified commits to GitHub.
3. Install and launch the exact committed build on every available paired iPhone, reporting any unavailable device.
