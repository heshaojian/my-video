# Aiyifan Card Metadata And Provider Playback Truth Design

**Status:** Revised and approved on 2026-09-10 after live provider inspection.

## Goal

Make episode metadata and resolution controls reflect the data Aiyifan actually
publishes, while keeping native playback stable and the shared poster cards
compact.

The change has three user-visible outcomes:

1. Home, Search, Saved, Played, and All cards show trustworthy provider episode
   labels for both ongoing and completed episodic titles.
2. Opening an episodic title selects the newest real playlist entry instead of
   trusting an inconsistent catalog key.
3. The player shows every resolution in the provider's quality inventory as an
   enabled, tappable option, whether or not the current anonymous playback
   response contains a usable source for it.

## Live Provider Findings

The provider was inspected through the same public, signed endpoints used by its
website. No signed media URL, certificate value, or credential belongs in source
control.

### Resolution Data

`/v3/video/play` exposes two different collections with different meanings:

- `info.clarity` is the website's complete quality selector inventory. A row can
  include `title`, `description`, `bitrate`, `key`, `line`, `isVIP`, `isBought`,
  `isEnabled`, and an optional `path`.
- `info.flvPathList` contains advertisements plus the program sources delivered
  for the current session. It is not the complete quality inventory.

For a current anonymous session, a title can list 2160p, 1080p, 720p, and 576p
in `clarity` while providing a playable HLS path only for 576p. The website still
renders every `clarity` row as a clickable quality choice. The previous app
implementation decoded only `flvPathList`, so the other website choices could
never appear.

### Episode Data

`/api/list/Search` uses `isSerial` as an ongoing/completed state, not as a
reliable "has episodes" discriminator. In a live sample of the newest 100 items
per episodic category, valid `lastName` values existed on every row, including
rows where `isSerial` was false:

- Series: 16 completed rows
- Variety: 43 completed rows
- Anime: 10 completed rows

The previous card projection required `isSerial == true`, hiding valid episode
metadata for those completed titles.

Catalog `lastKey` is also not a reliable newest-episode key. Live examples
included an ongoing anime whose catalog `lastKey` pointed to episode 1 while
`lastName` and `/v3/video/languagesplaylist` showed 286 episodes. A completed
10-episode series had the same mismatch. The playlist itself returned all
episodes with valid keys, names, and update dates.

## Decisions

### Episodic Content Classification

Use one shared classifier wherever the app needs to know whether a title can
have episodes.

A title is episodic when any of these trusted signals applies:

1. Its category path belongs to Series (`0,1,4`), Variety (`0,1,5`), or Anime
   (`0,1,6`).
2. A resolved or saved episode snapshot exists for the title.
3. An explicit episode key was supplied by a user action, Played record,
   notification, or deep link.
4. Provider detail says `isSerial == true` when stronger category information is
   absent.

`isSerial == false` never overrides an episodic category. It means completed for
catalog filtering and must not suppress episode UI or playlist loading.

### Episode Source Of Truth

For episodic content, `/v3/video/languagesplaylist` is the source of truth for
episode identity, order, selection, Saved synchronization, and player episode
controls.

- Decode the detail response's validated `cid` and `taxis`, then pass both to the
  playlist request as the website does.
- Make up to four cancelable playlist attempts using the existing bounded retry
  schedule.
- Validate each key, title, optional date, response size, and maximum item count.
- Deduplicate by media key.
- Sort newest-first by update date, then recognized episode number, then reverse
  provider position as the final fallback because observed playlists are
  oldest-first.
- Select an explicit requested episode only when its exact key exists.
- With no explicit selection, select the first newest-sorted playlist episode.
- Never use `AiyifanItem.latestEpisodeKey` as the default playback selection.
- Never guess episode 1.

If all playlist attempts fail and an explicit episode key came from a direct
user selection or existing Played record, that exact episode may still start
while the episode control exposes Retry Episodes. Without an explicit key, the
app reports that episodes could not be loaded instead of starting an
unverified catalog key.

### Episode Label Projection

`PosterCardProjection` remains the single card-facing projection used by every
poster grid.

For episodic content, evaluate labels in this order:

1. Latest title from a synchronized `SavedEpisodeUpdateState`.
2. `AiyifanItem.latestEpisodeTitle`.
3. `AiyifanItem.subTitle`.

Reject empty values and values equal to known title or episode media keys. Treat
only ASCII key-shaped tokens matching the provider's identifier alphabet as
opaque. Do not reject meaningful Chinese labels merely because they contain
digits and letters.

Accepted provider forms include bare numbers, `Episode 10`, `第10集`, `第10期`,
`更新至10集`, `10集全`, date-prefixed Variety labels, and meaningful named
specials. Provider text remains in its original language.

The compact card text remains:

1. One-line title with tail truncation.
2. One immediately adjacent line containing available episode, language, and
   year values in that order, separated by ` · `.

The shared projection applies to Home, Search, Saved, Played, and All poster
grids. Horizontal progress cards keep their workflow-specific progress layout.

### Saved And Home Freshness

Home continues to reload the latest provider catalog when the app opens or
becomes active. The shared classifier and label sanitizer make the valid
`lastName` values visible without adding a detail-and-playlist request for every
Home card.

Saved continues its direct playlist synchronization at app open, on pull to
refresh, and during the daily background check:

- Limit concurrent title checks to three.
- Retry a response that temporarily omits the previously observed episode.
- After bounded retries, a valid nonempty playlist can be reconciled even if an
  obsolete old key disappeared.
- Reconciliation may advance to a newer dated or numbered episode but never
  regress a retained latest episode because of a delayed or partial response.
- Player-observed episode lists update Saved immediately.

All and Search use fresh catalog metadata and the same correct card projection,
but do not eagerly request a playlist for every visible result. Opening any
result resolves its playlist before choosing the default episode.

## Resolution Inventory

### Provider Quality Choice

Add an immutable provider quality model representing one validated `clarity`
row. It retains only the fields needed for identity, display, matching, and
safe selection:

- Stable provider key and line
- Normalized display tier such as 2160p, 1080p, 720p, or 576p
- Provider description when safe and useful
- Optional validated secure HLS source
- Provider availability flags for internal decision-making only

Rows with invalid keys, unsupported tiers, control characters, or unsafe URLs
are rejected. Exclude the provider's synthetic `auto` row because the app owns
its Automatic choice. Preserve distinct provider rows when line identity makes
them different; otherwise deduplicate identical choices deterministically.

### Menu Projection

The Quality menu contains:

1. `Automatic (prefers 1080p)`
2. Every validated website `clarity` choice, highest tier first
3. Any additional real HLS rendition exposed by AVFoundation that is not already
   represented by a provider choice

Every displayed manual choice is enabled and tappable. The interface does not
show a lock icon, disabled state, VIP label, membership explanation, sign-in
prompt, or automatic website redirect.

Catalog metadata such as `vipResource` can annotate a card or detail view but
does not create menu choices. `flvPathList` and AVFoundation renditions provide
playable sources; `clarity` provides the complete visible inventory.

### Selection Behavior

Selecting a manual quality follows this order:

1. Use a matching rendition in the current adaptive HLS asset.
2. Otherwise prepare the quality row's validated secure HLS path.
3. If neither source exists, leave playback unchanged and publish a neutral
   result: `<tier> could not be played. Continuing with <current tier>.`

All source changes are transactional. Capture the current program timestamp,
play/pause state, rate, episode, and Played identity. Promote a replacement only
after AVFoundation marks it ready, seek to the captured position, and restore
the prior state. A failed attempt keeps the previous player item and preference
unchanged, while the quality choice remains visible and tappable for retry.

An asynchronous source preparation publishes `Switching to <tier>...` through
the existing player status surface and accessibility announcements. A newer
quality tap cancels the older pending attempt so the latest user intent wins;
choices are not disabled while preparation is pending.

Automatic considers only actually playable sources. It selects exact 1080p when
available and otherwise the highest playable tier. A successful manual tier is
remembered across episodes; if that tier is absent or not playable on a later
episode, playback remains on the best working source without selecting an
unusable inventory row.

## Components

- `EpisodicContentClassifier` owns category-based episodic inference.
- `EpisodeNumberParser` recognizes provider numbering forms used for ordering.
- `PosterCardProjection` owns safe card labels and compact metadata composition.
- `VideoDetailResponseDecoder` retains validated playlist request context.
- `EpisodePlaylistResponseDecoder` validates and orders the complete playlist.
- `NativePlaybackResponseDecoder` decodes both the full `clarity` inventory and
  the currently delivered program sources.
- `PlaybackQualityMenuProjector` combines provider choices with real
  AVFoundation variants without inventing tiers.
- `NativePlayerViewModel` owns exact episode selection, quality attempts,
  transactional switching, rollback, persistence, and neutral failure state.
- `SavedUpdateMonitor` and `SavedEpisodeSnapshotReconciler` own bounded direct
  refresh and monotonic Saved state.

## Security And Privacy

- Keep HTTPS-only provider, artwork, and media host validation.
- Reject embedded credentials, unexpected ports, malformed keys, oversized
  responses, and unapproved redirect hosts.
- Never persist or log signed media URLs, certificate material, or provider
  response secrets.
- Do not parse or rewrite manifests, proxy media, download media, bypass access
  controls, or manufacture a source for a provider row without one.
- Provider availability flags can guide safe behavior internally but are not
  exposed as membership messaging in the app.

## Testing

Use TDD for each behavior change and keep the full app target above the existing
80 percent coverage gate.

### Unit And Integration Tests

- Completed Series, Variety, and Anime items remain episodic when
  `isSerial == false`.
- Movie metadata is never interpreted as an episode label.
- Chinese date-prefixed labels remain visible while ASCII provider keys do not.
- `10集全`, `更新至10集`, `第10期`, and English episode forms parse safely.
- A misleading catalog `lastKey` for episode 1 cannot override playlist episode
  10 or 286.
- Playlist retries, exact requested selection, newest default selection,
  fallback ordering, deduplication, and cancellation are covered.
- Saved synchronization advances from 9 to 10, accepts a valid replacement
  playlist after bounded stale-key retries, and never regresses.
- `clarity` rows produce all website quality choices even when only one row has
  a path.
- Invalid quality rows and unsafe sources are rejected without discarding valid
  choices.
- Every quality menu row is selectable.
- A path-backed or adaptive quality switch preserves playback state and
  progress.
- A source-less or failed choice leaves the current player untouched and emits
  only the neutral result.

### UI And Regression Tests

- Home, Search, Saved, Played, and All share the same one-line title and compact
  detail geometry.
- Completed and ongoing fixture cards both show episode labels.
- The fixture player exposes 2160p, 1080p, 720p, and 576p as enabled buttons,
  including source-less choices.
- Selecting a working tier preserves progress; selecting a source-less or
  failing tier keeps playback active.
- Episode controls show the full newest-first list and select the real newest
  episode from a misleading catalog fixture.
- Existing fullscreen, Picture in Picture, background audio, AirPlay, Google
  Cast, Saved, Played, Ready to Watch, skip controls, and secure website fallback
  remain passing.

After focused tests pass, run the full unit suite, serial UI suite, static
analysis, coverage gate, and the existing heavy-user scenario once for the
combined major change.

## Acceptance Criteria

- Every valid website `clarity` resolution appears as an enabled, tappable menu
  choice without lock or membership messaging.
- A quality choice with no usable source cannot interrupt current playback.
- Automatic prefers playable 1080p and otherwise uses the highest playable
  source.
- All episodic poster cards can show valid provider episode labels regardless of
  ongoing/completed status.
- No card displays an opaque media key as episode metadata.
- Default episodic playback uses the newest validated playlist entry, never an
  unverified catalog `lastKey` or guessed episode 1.
- Saved updates from episode 9 to 10 after app-open or manual synchronization and
  never regresses on partial data.
- Existing app workflows and native AVPlayer controls remain intact.
