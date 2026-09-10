# Aiyifan Card Metadata And Resolution Inventory Design

## Goal

Make poster grids compact and trustworthy, and make the playback quality menu
match the resolution choices Aiyifan actually exposes.

The change has two user-visible outcomes:

1. Home, Search, Saved, Played, and All cards use one text layout: a one-line
   title followed immediately by one compact episode/language/year row.
2. The player lists every resolution discovered from the provider playback
   response or delivered HLS asset. Every listed resolution is tappable, even
   when AVFoundation cannot confirm in advance that it will play.

## Current Problems

- A provider episode media key can leak into a card as if it were an episode
  label, for example `fz4AxompbuT`.
- Poster titles reserve two lines even when a title uses only one line. This
  creates an empty visual row before the metadata.
- Card metadata currently prioritizes year and region instead of the requested
  episode, language, and year sequence.
- The quality menu mixes measured stream tiers with tiers synthesized from a
  catalog maximum such as `4K`. Synthesized choices are disabled, while some
  website-exposed sources can be discarded before the user can try them.

## Decisions

### Shared Poster Projection

`PosterCardProjection` remains the single card-facing projection used by all
poster grids. It will expose a title and one optional compact detail string.

The detail string is assembled in this order:

1. Trustworthy episode label for serial content.
2. Provider-supplied language.
3. Provider-supplied year.

Missing fields are omitted, including their separators. Region is not included
in this compact row. Provider content remains in its original language.

### Episode Label Validation

Episode label candidates are evaluated in this order:

1. The title of the synchronized latest episode in `SavedEpisodeUpdateState`.
2. `AiyifanItem.latestEpisodeTitle`.
3. `AiyifanItem.subTitle`.

A candidate is rejected when it is empty, equals a known media key, or has the
shape of an opaque provider identifier. Numeric labels and familiar provider
forms such as `Episode 10`, `10`, `第10集`, `第10期`, and `更新至10集` are
accepted. Meaningful nonnumeric episode names are retained when they are not
key-like.

If no trustworthy candidate exists, the episode field is omitted. The app does
not display a raw key and does not invent an episode number. When Saved
synchronization later resolves the episode list, the live projection updates
with the resolved title.

### Card Typography And Spacing

- The title uses one line with tail truncation.
- The title does not reserve an unused second line.
- The compact detail row follows the title with 3 to 4 points of spacing.
- The detail row uses one line with tail truncation.
- Poster dimensions, score/status badges, action placement, and 44-point action
  hit targets remain unchanged.
- The same layout applies to the poster-card family on Home, Search, Saved,
  Played, and All. Horizontal progress cards keep their workflow-specific
  progress layout.

## Resolution Inventory

### Source Of Truth

The resolution menu is built only from playback choices exposed by the current
provider response or by AVFoundation's view of the delivered HLS asset.

Trusted inventory sources are:

1. Secure, non-advertisement media rows returned by the provider playback API,
   when they contain a recognizable resolution label or dimensions.
2. HLS variants returned by `AVURLAsset`, including variants that have valid
   dimensions but cannot be proven playable before selection.

Catalog metadata such as `vipResource` or a detail-page `4K` label may annotate
the title but does not create 1080p, 720p, or other intermediate choices. The
app does not parse or rewrite raw HLS manifests.

Resolution choices are deduplicated by normalized display tier and sorted from
highest to lowest. `Automatic` remains first and prefers exact 1080p, otherwise
the highest working tier.

### Tappable Choices

Every displayed provider resolution is enabled. The UI does not add a lock icon
or an `Unavailable` suffix merely because AVFoundation has not validated it.

Selecting a choice follows one of two paths:

- For a variant in the current adaptive asset, apply its resolution and bitrate
  preference to the existing player item.
- For a distinct provider media source, prepare that secure source and switch
  only after it becomes ready.

For a source switch, capture the current program timestamp, playback state,
rate, episode, and selected quality. On success, seek to the captured timestamp
and restore the prior playing or paused state. Do not create a new Played record
or reset progress.

### Selection Failure

An attempted resolution can fail even though the website advertised it. A
failure is nonterminal:

- Keep the previous playable source, timestamp, episode, and playback state.
- Keep the failed option visible and tappable so the user can retry later.
- Show a concise message: `<resolution> could not be played. Continuing with
  <current resolution>.`
- Never fall back to the website automatically and never stop an otherwise
  playable session.

Security validation remains unchanged: HTTPS only, approved provider/media
hosts, no embedded credentials, and bounded response sizes.

## Components

- `PosterCardProjection` owns episode-label sanitization and compact detail-row
  composition.
- `PosterMediaCard` owns one-line typography and vertical spacing.
- `NativePlaybackResponseDecoder` retains all secure program sources instead of
  selecting and discarding all but the first source.
- `PlaybackQualityProjector` normalizes and deduplicates provider and HLS choices.
- `NativePlayerViewModel` owns selection attempts, transactional source
  switching, rollback, persistence, and user-facing failure state.
- The SwiftUI quality menu renders every projected choice as an enabled button.

## Testing

### Unit Tests

- Opaque episode keys never appear in `PosterCardProjection`.
- Numeric, localized, and meaningful special labels remain visible.
- Episode/language/year ordering and missing-field separators are correct.
- Synchronized Saved episode titles override stale item metadata.
- Provider playback decoding retains every secure resolution source and rejects
  insecure or malformed sources.
- Resolution inventory deduplicates tiers, sorts highest first, and never
  synthesizes tiers from a catalog maximum.
- Every inventory choice is selectable.
- Failed source switching preserves the previous source, timestamp, state,
  episode, and Played identity.

### UI Tests

- Poster-grid titles are one line and the detail row has no reserved blank line.
- Home, Search, Saved, Played, and All use the same card text geometry.
- The player menu exposes all fixture provider resolutions as enabled buttons.
- Selecting a working resolution preserves progress.
- Selecting a failing fixture resolution reports the failure and keeps playback
  active on the previous source.

Run the focused unit and UI tests during implementation. After the combined
change is complete, run the full unit suite, full serial UI suite, static
analysis, and the existing heavy-user scenario once.

## Out Of Scope

- Fabricating resolution choices from catalog badges.
- Guaranteeing that an advertised resolution will play.
- Manual M3U8 parsing, media proxying, downloading, or DRM bypass.
- Changing poster artwork ratios, badge styling, navigation, Saved semantics,
  Played semantics, casting, or native AVPlayer transport controls.

## Acceptance Criteria

- No poster card displays an opaque episode/media key.
- Every poster-grid title is one line with no reserved blank line below it.
- The next row contains only available episode, language, and year values in
  that order.
- The quality menu contains all and only provider/HLS-exposed resolution tiers.
- Every displayed resolution is tappable.
- A failed resolution attempt leaves existing playback and progress intact.
- Existing Home, Search, Saved, Played, All, episodes, fullscreen, Picture in
  Picture, background audio, AirPlay, Google Cast, and website fallback behavior
  remains passing.
