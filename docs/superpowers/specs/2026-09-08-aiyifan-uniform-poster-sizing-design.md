# Aiyifan Uniform Poster Sizing Design

## Goal

Keep every poster card visually aligned even when the provider supplies landscape, unusually wide, or inconsistent artwork. The fix must apply through the shared card family used by Home, Search, Saved, Played, and All.

## Design

- Grid and compact poster containers retain their existing widths and use the shared `0.72` portrait aspect ratio.
- The container owns the final dimensions. Artwork cannot contribute an intrinsic width that expands its grid column.
- Artwork uses aspect-fill, remains centered, and is clipped to the poster boundary. Landscape artwork may be cropped; the grid must never stretch or overlap.
- Score, status, and saved-action overlays remain anchored inside the poster boundary.
- Card text and actions keep their current behavior and accessibility labels.

## Scope

The implementation changes the shared `PosterMediaCard` sizing behavior. It does not change provider artwork URLs, feed ordering, metadata, card actions, or the Saved grid definition.

## Verification

- Add a regression test that renders or inspects cards backed by portrait and landscape artwork and confirms equal poster width and height.
- Confirm adjacent cards do not overlap and action overlays remain within their poster frames.
- Run the focused card tests, the full unit test suite, and the relevant UI flow on a supported iPhone simulator.
- Review Home, Search, Saved, Played, and All because they share the component.

## Success Criteria

- `披荆斩棘 2026` has the same poster dimensions as the adjacent Saved card.
- No provider image can widen a card beyond its assigned grid column.
- Existing card navigation, save/remove actions, ratings, and labels continue to work.
