# Aiyifan Provider Playback Truth Correction Implementation Plan

**Goal:** Make every website quality choice visible and tappable, and make
playlist data authoritative for episodic labels and default playback.

**Baseline:** `31c4611` on `feat/card-metadata-resolution-inventory`. The prior
major-change run passed 370 tests with 88.44 percent app-target coverage, but its
quality and episode assumptions were disproved by live provider inspection.

**Spec:**
`docs/superpowers/specs/2026-09-09-aiyifan-card-metadata-resolution-inventory-design.md`

**Architecture:** Decode provider semantics once at the network boundary. A
shared episodic classifier replaces boolean `isSerial` checks. The native
resolver uses the validated playlist for newest-episode selection. A new
immutable quality-choice model retains every safe `clarity` row while playable
sources remain separate. The player merges provider choices with AVFoundation
renditions and handles every tap transactionally.

**Tech stack:** Swift 6, SwiftUI, AVFoundation, AVKit, XCTest, XCUITest.

## Global Constraints

- Write failing tests before each production behavior change.
- Do not persist or print signed URLs, provider certificates, or response
  secrets.
- Keep HTTPS and approved-host validation for every media source.
- Keep native `AVPlayerViewController` transport, fullscreen, Picture in
  Picture, background audio, and AirPlay controls.
- Do not add membership, VIP, sign-in, lock, or automatic website-fallback UI to
  quality choices.
- Keep every validated provider quality choice enabled and tappable.
- Never use catalog `lastKey` as proof of the newest episode.
- Preserve provider titles and episode labels in their original language.
- Run focused tests while implementing and one complete regression after the
  combined major change.

## Task 1: Lock Down Episodic Semantics And Card Labels

**Files:**

- Modify: `AiyifanTests/NativePlaybackResolverTests.swift`
- Modify: `AiyifanTests/SavedLibrarySynchronizationTests.swift`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift`
- Modify: `Aiyifan/App/MediaCard.swift`

### RED

Add tests proving:

1. Series, Variety, and Anime category paths are episodic even when
   `isSerial == false`.
2. Movies remain non-episodic even when unrelated metadata includes a numeric
   quality label.
3. `EpisodeNumberParser` recognizes bare numbers, `Episode 10`, `第10集`,
   `第10期`, `更新至10集`, and `10集全` without treating a date prefix as an
   episode number.
4. `PosterCardProjection` displays completed-series labels and long Chinese
   Variety labels while suppressing actual ASCII provider keys.
5. The same projection still emits one compact episode/language/year row.

Run:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/NativePlaybackResolverTests \
  -only-testing:AiyifanTests/SavedLibrarySynchronizationTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected RED: completed episodic cards are currently hidden by
`item.isSerial == true`, and provider label forms are not fully parsed.

### GREEN

- Introduce `EpisodicContentClassifier` near the existing playback intent
  model. It uses the category prefix, resolved/saved episode state, explicit
  episode key, and positive provider signal. A false provider flag does not
  override an episodic category.
- Route `SerialPlaybackIntent` and `PosterCardProjection` through the shared
  classifier.
- Expand `EpisodeNumberParser` with anchored, bounded provider forms. Avoid a
  broad "first digits anywhere" rule that would turn Variety dates into episode
  numbers.
- Restrict opaque-key detection to safe ASCII provider-key syntax instead of all
  Unicode letters plus digits.

Re-run the focused command and keep all tests green.

## Task 2: Make The Playlist Authoritative

**Files:**

- Modify: `AiyifanTests/NativePlaybackResolverTests.swift`
- Modify: `AiyifanTests/LibraryServicesTests.swift`
- Modify: `AiyifanTests/SavedLibrarySynchronizationTests.swift`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift`
- Modify: `Aiyifan/App/SavedUpdateService.swift`
- Modify: `Aiyifan/App/SavedLibrarySynchronization.swift`

### RED

Add contract tests with provider-shaped fixtures proving:

1. Detail decoding retains validated `cid` and `taxis`; the playlist request
   signs both values.
2. A catalog item whose `lastKey` is episode 1 selects playlist episode 10 when
   no explicit episode was requested.
3. A 286-episode playlist is returned newest-first and selects episode 286.
4. An explicit episode key selects exactly that episode and never substitutes
   episode 1.
5. Equal or absent dates use numeric ordering, then reverse provider position as
   a stable final fallback.
6. Initial empty or partial playlists retry up to four attempts and remain
   cancellation-aware.
7. Saved synchronization can accept a valid replacement playlist after bounded
   stale-key retries, advances 9 to 10, and cannot regress 10 to 9.

Run the same resolver-focused command plus:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/LibraryServicesTests \
  -only-testing:AiyifanTests/SavedLibrarySynchronizationTests \
  CODE_SIGNING_ALLOWED=NO
```

### GREEN

- Add validated `taxis` to `VideoPlaybackContext` and
  `NativePlaybackRequestBuilder.makePlaylistURL`.
- Decode playlist envelope metadata only where it improves validation; retain
  the existing response and item-count limits.
- Replace `preferredEpisodeKey ?? item.latestEpisodeKey` with explicit-key-only
  selection. With no explicit key, select the first newest-sorted playlist row.
- Fetch the playlist for every episodic default selection instead of creating a
  synthetic episode from catalog metadata.
- Keep the existing exact-episode fast fallback only after all playlist attempts
  fail and only when the caller supplied that exact key.
- Separate strict explicit-selection validation from Saved synchronization's
  stale-key retry hint. After final retry, reconcile a valid nonempty Saved
  playlist monotonically.

Re-run focused tests and commit the episode vertical slice:

```sh
git add Aiyifan/App AiyifanTests
git commit -m "fix: make playlists authoritative for episodes"
```

## Task 3: Decode The Website Quality Inventory

**Files:**

- Modify: `AiyifanTests/NativePlaybackResolverTests.swift`
- Modify: `AiyifanTests/PlaybackFeaturesTests.swift`
- Modify: `Aiyifan/App/PlaybackQuality.swift`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift`

### RED

Add a sanitized fixture matching the live `/v3/video/play` shape:

- `clarity`: source-less 2160p, 1080p, and 720p rows plus a path-backed 576p row
- `flvPathList`: advertisement rows plus the current 576p program
- `playingMedia`: current provider key and tier

Assert:

1. All four `clarity` choices survive decoding and sort highest-first.
2. All four are selectable even though only 576p has a path.
3. The playable-source collection remains separate and excludes ads.
4. `auto`, malformed keys, control-character labels, unsupported tiers, HTTP
   URLs, embedded credentials, unapproved hosts, and oversized data are safely
   rejected without discarding valid sibling choices.
5. Distinct provider lines retain stable identity while exact duplicates are
   deterministic.

Run:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/NativePlaybackResolverTests \
  -only-testing:AiyifanTests/PlaybackFeaturesTests \
  CODE_SIGNING_ALLOWED=NO
```

### GREEN

- Add immutable `ProviderQualityChoice` with safe identity, tier, optional
  provider description, optional validated HLS source, and internal provider
  flags.
- Add `qualityChoices` to `NativePlayback` with a source-compatible empty
  default.
- Decode `clarity` independently from `flvPathList`; do not require a path for a
  valid visible choice.
- Keep the current delivered program as the sole playback entry and retain all
  safe delivered sources for automatic selection.
- Propagate choices through resolver composition and cast-plan snapshots without
  persisting signed URLs.

Re-run the focused tests.

## Task 4: Project And Handle Every Quality Tap

**Files:**

- Modify: `AiyifanTests/PlaybackFeaturesTests.swift`
- Modify: `AiyifanTests/NativePlayerViewModelTests.swift`
- Modify: `Aiyifan/App/PlaybackQuality.swift`
- Modify: `Aiyifan/App/NativePlayerView.swift`
- Modify: `Aiyifan/App/PlaybackSessionController.swift`

### RED

Add tests proving:

1. The menu contains Automatic followed by all provider choices and additional
   real AVFoundation tiers, without duplicate tier/line rows.
2. Source-less choices report `isSelectable == true`.
3. A matching adaptive tier changes preference on the current item.
4. A path-backed tier stages and promotes a new item at the retained timestamp,
   rate, episode, and play/pause state.
5. A source-less tier publishes only the neutral failure result and keeps the
   current item and stored preference unchanged.
6. A failed staged source behaves the same way.
7. A newer quality tap cancels an older pending preparation and wins.
8. Automatic prefers playable 1080p and otherwise the highest playable source,
   never a source-less inventory row.

Run:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/PlaybackFeaturesTests \
  -only-testing:AiyifanTests/NativePlayerViewModelTests \
  CODE_SIGNING_ALLOWED=NO
```

### GREEN

- Extend `PlaybackQualityMenuOption` to carry a provider choice, adaptive option,
  and delivered provider source without conflating visibility with playability.
- Match choices to adaptive or delivered sources by normalized tier and line.
- Keep every SwiftUI quality action enabled and give it a stable accessibility
  identifier.
- On tap, use adaptive rendition, then validated row path, then neutral
  nonterminal failure.
- Publish `Switching to <tier>...` during asynchronous preparation and announce
  the final result accessibly.
- Preserve the current transactional source-staging and rollback behavior.
- Persist a manual preference only after successful application.

Re-run focused tests and commit the quality vertical slice:

```sh
git add Aiyifan/App AiyifanTests
git commit -m "fix: expose provider clarity choices"
```

## Task 5: Exercise The Native UI End To End

**Files:**

- Modify: `AiyifanUITests/AiyifanLatestTapTests.swift`
- Modify fixture code in `Aiyifan/App/NativePlaybackResolver.swift` and related
  fixture helpers only as required

### RED And GREEN

Add deterministic UI coverage for:

1. A completed episodic card with `isSerial == false` still shows `10集全`.
2. A long Chinese Variety update label is visible and never mistaken for an
   opaque key.
3. Home, Search, Saved, Played, and All retain one-line title plus compact detail
   geometry.
4. A misleading catalog episode-1 key opens a newest-first list with episode 10
   selected.
5. Quality shows 2160p, 1080p, 720p, and 576p as enabled actions.
6. Tapping a source-less tier leaves playback active and shows only the neutral
   result.
7. Tapping a working tier preserves progress.

Run only these focused UI methods while iterating, serially on iPhone 17 Pro.
Do not run the complete UI suite after each fixture edit.

## Task 6: Update Durable Guidance

**Files:**

- Modify: `README.md`
- Modify: `DEVELOPMENT.md`
- Modify: the existing implementation plan only if execution reveals a material
  architectural deviation

Record these durable rules:

- `clarity` is visible quality inventory; `flvPathList` is delivered media.
- Visibility and playability are separate states.
- `isSerial` represents ongoing/completed status and must not classify content.
- Playlist order and keys are authoritative; catalog `lastKey` is only routing
  metadata.
- Provider-shaped fixtures must represent source-less quality choices and
  misleading catalog episode keys.
- Live verification must compare catalog metadata with the playlist rather than
  checking only that requests return 200.

Commit UI tests and guidance together after focused verification:

```sh
git add Aiyifan AiyifanTests AiyifanUITests README.md DEVELOPMENT.md docs
git commit -m "test: cover provider playback truth"
```

## Task 7: Major-Change Verification

Run once after the combined implementation is stable:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild analyze \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

plutil -lint Aiyifan/Resources/Info.plist Aiyifan/Aiyifan.entitlements
git diff --check
git status --short
```

Verify the result bundle reports at least 80 percent app-target line coverage.
Run a bounded live-provider smoke check without logging signed URLs or response
bodies:

- All four latest categories decode.
- Completed and ongoing episodic catalog rows expose labels.
- One episodic playlist returns multiple newest-first episodes and its newest
  key differs safely from a misleading catalog key when applicable.
- One playback response exposes all `clarity` choices while preserving its
  playable program.

Review the complete branch diff for correctness, secrets, accidental fixture
behavior in Release, and unrelated churn. Do not push or deploy until the user
requests those external actions.
