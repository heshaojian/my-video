# Aiyifan Development Guide

This is the durable engineering contract for Aiyifan. Read it before changing
navigation, playback, provider requests, persistence, notifications, or casting.
The goal is to preserve the behavior users rely on and avoid repeating failures
already found during development.

## Start Here

- The app targets iOS 17 or later and uses Swift 6, SwiftUI, AVFoundation, AVKit,
  MediaPlayer, BackgroundTasks, UserNotifications, and Google Cast.
- Install dependencies with `pod install`.
- Open and build `Aiyifan.xcworkspace`. Do not develop from
  `Aiyifan.xcodeproj`; that omits CocoaPods integration.
- Treat `README.md` as the quick start, this file as the engineering contract,
  and `docs/releases/` as dated verification evidence.
- Preserve unrelated working-tree changes. Inspect `git status` and the relevant
  source before editing.

```sh
pod install
open Aiyifan.xcworkspace
```

## Product Contract

These are product invariants, not incidental implementation details.

### Discovery

- Home contains exactly Movies, Series, Variety, and Anime.
- Home is a fast, unfiltered discovery surface. Filtering and sorting do not
  belong on the small recent sample.
- Home trusts the provider's last-updated descending order. A cold launch uses
  the app-open coordinator to force Home and Saved together; later foreground
  returns use a 15-minute successful-refresh window. Re-entering Home still uses
  feed freshness, and pull-to-refresh always forces a request while keeping
  existing cards visible.
- Global search is collapsed by default and runs only after explicit submit.
  It queries the signed provider API; it never filters the loaded Home sample.
- Search results reuse the exact All poster-grid card component and remain
  playable and saveable without opening a web page.
- Every All action opens a native full-category catalog, never an implicit web
  page.
- Filtering, sorting, result counts, pagination, and persistent per-category
  choices belong to the native All catalogs.
- App-owned interface text is English. Provider titles, episode names, genres,
  regions, languages, descriptions, and filter values remain unchanged.
- Provider scores appear in Home, Search, Saved, and All when valid. Likes,
  Favorites, Score, and Views appear in native playback details when supplied.
- Home, Search, Saved, and All share the poster-card component family. Played
  and Continue Watching use its progress-row variant so workflow-specific
  information remains visible without visual drift.
- Every poster card projects its display through `PosterCardProjection`: reserve
  two title lines, then show the latest update in cyan and available year/region
  in one muted compact row. Saved prefers the reconciled latest episode title.
- Poster score/status and contextual actions are anchored to a deterministic
  poster surface. Card text and provider artwork dimensions must never move a
  Save or Remove control outside its grid cell.
- Let a layout-owned aspect-ratio container determine poster dimensions, then
  render provider artwork as a centered, aspect-fill overlay clipped to that
  container. Do not let the image's intrinsic size participate in grid sizing.

### Saved And Played

- Saving is available from native discovery surfaces and persists locally.
- Saved serial titles receive direct checks on cold launch, after a 15-minute
  foreground freshness window, and on forced pull-to-refresh. Daily background
  work remains the notification safety net; the short Home feed is not
  sufficient for episode detection.
- The first successful direct check establishes a baseline without notifying.
  Later episode changes are deduplicated and respect global and per-title alert
  settings.
- Feed, direct-check, and player observations enter one main-actor reconciliation
  path. Merge by validated media key, retain bounded newest-first snapshots, and
  never downgrade a known latest episode because a delayed response is partial.
- Native playback publishes resolved and recovered episode lists through a
  callback. It must not depend directly on `SavedItemsStore`.
- iOS decides when background refresh runs; never promise an exact notification
  time.
- Played records are per episode for serial content and per title for movies.
- Progress advances only while AVPlayer reports actual playback. A loading,
  paused, failed, backgrounded, or visually stale player must not advance time.
- Incomplete records resume from their saved media time. Completed records start
  from the beginning. The Played label is fixed media time, not elapsed wall time.

### Ready To Watch

- Ready to Watch exists only on Saved, above the unchanged All Saved grid. Do not
  add it to Home or turn it into a calendar/release forecast.
- Project the queue from Saved items, retained episode snapshots, Played records,
  and sparse user overrides. Never persist a materialized queue snapshot.
- Keep at most one entry per Saved title. Manual pins come first; then new exact
  episodes; then unfinished playback. An unfinished episode wins over a new
  episode for the same title until it is completed or dismissed.
- Exact episode keys are mandatory for serial queue actions. Never guess episode
  1. Movies may use a title-level entry with no episode key.
- Persist pins, ordering, dismissals, and tombstones. Prune them when a title is
  unsaved. Provider failures retain the last valid episode snapshot and queue.
- Queue actions must update immediately: Play uses `selectItem(_:episodeKey:)`,
  Mark Watched records an explicit completion override, and Not Now suppresses
  only the matching episode so a later update can reappear.

### Skip Intro And Outro

- Skip is local-first, serial-only, button-only, and advisory. Never seek without
  a user tap, and always expose a short Undo after a skip.
- Marker precedence is user-corrected, trusted provider metadata, then learned
  visual fingerprints. Low-confidence or duration-outlier profiles stay hidden.
- Sample frames only from the active program `AVPlayerItem`; never create a second
  player, fetch a second rendition, inspect signed playlists, or delay playback.
- Use bounded visual hashes from the first eight and final six minutes. Keep at
  most three episodes and 500 hashes per episode. Frames and hashes remain local;
  signed URLs, cookies, provider responses, and media bytes are never persisted.
- Detection and sampling are optional side work. Cancel stale work on episode
  changes, casting, memory pressure, or teardown. Any failure must leave ordinary
  playback, fullscreen, Picture in Picture, and background audio unchanged.
- Learned markers require at least two agreeing episodes. Manual corrections are
  the fallback and must survive relaunch. A reset tombstone must defeat an older
  learned profile.

### Native Playback

- Selecting a native card routes to `NativePlayerViewModel`. `WKWebView` is only
  the explicit Open Website fallback.
- One app-owned playback session survives expanded and collapsed presentation.
  Back collapses to the mini-player; it does not stop or recreate playback.
- Home, Saved, Played, and All remain navigable while the mini-player is active.
- Fullscreen and Picture in Picture transitions must preserve the same player,
  item, timestamp, and playback state.
- Close and Open Website are terminal actions that persist progress and stop the
  local native session.
- Background audio and lock-screen Now Playing controls remain enabled.

### Episodes

- Series, Variety, and Anime expose an episode control, including when a native
  catalog response is temporarily incomplete.
- Episodes display newest first. Ordering uses update date, then numeric episode
  labels, then stable source order.
- A trusted latest or requested episode key may start immediately while the full
  episode list loads independently.
- Playlist loading makes four total attempts, with bounded delays of 0, 0.5, 1.5,
  and 3 seconds.
- A partial response that omits the expected episode is a retryable failure.
- Never silently substitute episode 1 when the expected episode is unavailable.
  Keep trusted playback active and expose Retry Episodes, or show a recoverable
  error if no trustworthy episode can start.

### Resolution

- Quality is always present in the playback menu.
- The default is Automatic, preferring exact 1080p. If exact 1080p is absent,
  select the highest valid rendition exposed by AVFoundation.
- Show manual rendition choices only when the delivered asset exposes multiple
  trustworthy tiers. Inspect a playable video track when AVFoundation exposes
  no adaptive variants; a single rendition shows `<tier> only`, while unknown
  dimensions show `Stream quality unavailable`.
- Catalog quality is provider metadata, not proof of a delivered rendition.
  Never synthesize a 4K option from `vipResource` or another catalog label.
- A manual choice persists across videos. Automatic resets the target to 1080p.
- Apply quality preferences to existing `AVPlayerItem` objects. Do not replace
  the item, restart playback, seek to zero, or create a new Played record.
- Resolution is an adaptive-streaming preference, not a guarantee. AVFoundation
  may temporarily use a lower rendition. Google Cast receives the validated HLS
  master URL and makes its own adaptive decision.

### Ads And Casting

- Exclude only separately supplied advertisement entries from local and Cast
  program queues.
- Do not claim to remove an advertisement embedded inside the program stream.
- AirPlay uses the system route picker and the local AVPlayer pipeline.
- Google Cast uses the official Sender SDK and Default Media Receiver.
- Do not introduce a custom receiver, streaming proxy, download path, DRM bypass,
  authentication workaround, or provider-control bypass.

## Architecture Map

| Responsibility | Primary owner |
| --- | --- |
| App lifecycle, audio session, interruptions | `Aiyifan/App/AiyifanApp.swift` |
| Root routing and Home UI | `Aiyifan/App/BrowserView.swift` |
| Selection ordering and website fallback state | `Aiyifan/App/BrowserViewModel.swift` |
| Four-category Home loading | `Aiyifan/App/AiyifanFeedService.swift` |
| Feed cache and partial-failure behavior | `Aiyifan/App/FeedRepository.swift` |
| All catalog queries, filters, decoding, signing | `Aiyifan/App/CategoryCatalogService.swift` |
| Catalog pagination and query state | `Aiyifan/App/CategoryCatalogViewModel.swift` |
| Persistent category queries | `Aiyifan/App/CatalogPreferenceStore.swift` |
| Native catalog presentation | `Aiyifan/App/NativeCategoryCatalogView.swift` |
| Shared poster and progress cards | `Aiyifan/App/MediaCard.swift` |
| Global API search transport and decoding | `Aiyifan/App/ProviderSearchService.swift` |
| Global search cancellation, paging, and UI state | `Aiyifan/App/ProviderSearchViewModel.swift` |
| Provider sessions, redirects, hosts, certificate cache | `Aiyifan/App/ProviderRequestSigner.swift` |
| Playback API, episodes, metrics, program/ad decoding | `Aiyifan/App/NativePlaybackResolver.swift` |
| Player state, progress, episode and quality controls | `Aiyifan/App/NativePlayerView.swift` |
| Retained full/mini playback ownership | `Aiyifan/App/PlaybackSessionController.swift` |
| Mini-player presentation | `Aiyifan/App/NativeMiniPlayer.swift` |
| HLS quality projection and preferences | `Aiyifan/App/PlaybackQuality.swift` |
| Playback rate, sleep timer, recovery policy | `Aiyifan/App/PlaybackFeatures.swift` |
| Lock-screen metadata and controls | `Aiyifan/App/NowPlayingCoordinator.swift` |
| Saved persistence and update baselines | `Aiyifan/App/SavedItemsStore.swift` |
| App-open policy and monotonic Saved reconciliation | `Aiyifan/App/SavedLibrarySynchronization.swift` |
| Direct saved-title checking | `Aiyifan/App/SavedUpdateService.swift` |
| Ready queue projection and sparse intent | `Aiyifan/App/ReadyToWatch.swift`, `Aiyifan/App/ReadyToWatchOverridesStore.swift` |
| Ready queue presentation | `Aiyifan/App/ReadyToWatchView.swift`, `Aiyifan/App/SavedItemsView.swift` |
| Skip models, projection, and persistence | `Aiyifan/App/SkipIntroOutroModels.swift`, `Aiyifan/App/SkipOpportunityProjector.swift`, `Aiyifan/App/SkipMarkerStore.swift` |
| Visual skip hashing, detection, and sampling | `Aiyifan/App/PerceptualFrameHasher.swift`, `Aiyifan/App/SkipMarkerDetector.swift`, `Aiyifan/App/SkipFingerprintSampler.swift` |
| Background refresh scheduling | `Aiyifan/App/BackgroundRefresh.swift` |
| Notifications, deep links, optional iCloud | `Aiyifan/App/LibraryServices.swift` |
| Played persistence and completion semantics | `Aiyifan/App/PlayedItemsStore.swift` |
| AirPlay and Google Cast | `Aiyifan/App/Casting.swift` |
| Explicit website fallback | `Aiyifan/App/WebView.swift` |

## Critical Data Flows

### Card To Playback

1. A native card calls `BrowserViewModel.selectItem` or `selectPlayed`.
2. Set `selectedEpisodeKey` before publishing `selectedItem`. SwiftUI observers
   can react immediately to the item publication.
3. `BrowserView` transfers the selection to `PlaybackSessionController` and
   clears the transient browser selection.
4. The controller creates or reuses one `NativePlayerViewModel`.
5. `NativePlaybackResolver` validates and resolves program media. Episode-list
   recovery may continue independently.
6. Resolved or recovered episode lists publish through the session callback;
   `BrowserView` applies them only when the title is Saved.
7. Expanded and mini-player views observe the same view model and AVQueuePlayer.

### Saved Title To Notification

1. `AppOpenLibraryRefreshCoordinator` forces Home and Saved on cold launch,
   coalesces overlap, and applies a 15-minute foreground freshness window.
   Manual Saved refresh also forces a direct run. The daily monitor policy is
   retained for background and settings-triggered notification work.
2. `SavedUpdateChecker` checks saved titles directly with bounded concurrency.
3. `NativePlaybackResolver` returns the newest validated serial episode.
4. `SavedItemsStore` compares it with the per-title baseline and deduplicates it.
5. `NotificationBatch` includes an app deep link to the exact episode.
6. Partial batches keep successful baselines but do not advance the global
   completed-check time, allowing foreground catch-up.

### Saved Title To Ready Playback

1. The daily checker retains a bounded, newest-first episode snapshot from its
   existing provider request; it does not make a second queue-specific request.
2. `SavedItemsStore` exposes unseen exact episodes with their detection dates.
3. `ReadyToWatchProjector` combines those updates with incomplete Played records
   and `ReadyToWatchOverridesStore` intent.
4. SwiftUI renders the pure result and sends exact commands back to the stores.
5. Playback selection writes the episode key before publishing the item.

### Episode To Learned Skip Marker

1. The current program item supplies throttled video frames during bounded
   sampling windows; ads and remote playback are excluded.
2. `PerceptualFrameHasher` converts frames to compact visual hashes.
3. `SkipMarkerStore` atomically retains bounded per-episode fingerprints.
4. `SkipMarkerDetector` compares at least two episodes and emits a profile only
   when agreement, duration, and confidence thresholds pass.
5. `SkipOpportunityProjector` decides whether a Skip button is currently valid.
   The player seeks only after the user taps it and offers Undo.

## Provider And Security Boundaries

Treat every provider value and URL as untrusted input.

- Require HTTPS and approved provider/media hosts.
- Reject credential-bearing URLs, private-network media URLs, unsupported final
  redirect hosts, malformed identifiers, invalid envelopes, and oversized data.
- Build signed requests only through the existing request builders and signer.
- Provider detail and playback requests use one validated two-letter device
  region with `US` fallback; playback also sends `lang=none`.
- A structurally invalid playback response may invalidate the cached provider
  certificate and retry the complete resolution exactly once. Terminal access,
  preview, host, identifier, media, and cancellation errors are not retried.
- Keep response-size limits and bounded collection counts in every decoder.
- Never persist or log certificates, signatures, signed request URLs, cookies,
  HLS URLs, playlists, or response bodies containing short-lived access data.
- Do not weaken validation to make one provider response pass. Capture a bounded,
  sanitized fixture and update the contract deliberately.
- Deep links accept only the `aiyifan://play` contract and bounded item payloads.
- Do not hardcode credentials, signing identities, device IDs, or developer-team
  values in source code or documentation examples.

## Failure Patterns To Avoid

| Symptom | Root cause | Correct pattern |
| --- | --- | --- |
| Card opens an HTML page and loses Save/Episodes | Web view used as primary routing | Route cards to native catalog/player; keep web explicit |
| A poster widens, overlaps its neighbor, or hides a card action | Provider artwork participates in grid sizing | Size a layout-owned ratio container first; aspect-fill and clip artwork inside its overlay |
| Home keeps yesterday's updates | Nonempty in-memory feed treated as permanently fresh | Refresh stale data on Home return/foreground and support forced pull-to-refresh |
| Saved still shows episode 9 after playback found 10 | Player and Saved keep separate episode state | Publish player observations and project Saved cards from reconciled state |
| Saved regresses from episode 10 to 9 | Delayed partial response replaces the retained snapshot | Merge observations monotonically; missing keys never prove a newer episode disappeared |
| Launch causes duplicate Home/Saved requests | View and tab lifecycle hooks each start work | Use one app-open coordinator and coalesce its in-flight task |
| Wrong episode starts from Played or notification | Item published before episode key | Assign episode key first, item second |
| Back or fullscreen stops playback | Player owned by a transient view | Retain one session-owned view model and player |
| Played time advances while nothing plays | Wall-clock timer treated as progress | Persist AVPlayer media time only while `.playing` |
| Episode list shows one item or starts episode 1 | Partial response trusted as complete | Require expected key, retry, and surface failure |
| Video waits for episode metadata | Stream and playlist loading coupled | Start trusted episode and recover list independently |
| One network hiccup permanently hides episodes | No bounded retry state | Use four cancelable attempts and Retry Episodes |
| Quality control disappears | UI conditioned on two or more variants | Always show Automatic; add manual options when known |
| Quality change restarts playback | Player item replaced | Update preferences on current and queued items in place |
| Saved older show never notifies | Only Home sample checked | Check every saved serial title directly |
| Search misses most titles | Home cards filtered in memory | Submit to the signed provider search API |
| Search cards drift from All | Similar markup copied into another view | Reuse `PosterMediaCard(.grid)` directly |
| Catalog says 4K but player cannot select it | Metadata treated as a rendition | Report only measured AVFoundation tiers |
| Current title returns an invalid response | Stale certificate or provider request context | Use validated region/language and one fresh-certificate retry |
| Daily notification claimed at an exact hour | `earliestBeginDate` treated as a timer | Describe background refresh as best effort; catch up on launch |
| Ready queue starts the wrong episode | Queue stores only a title or guesses episode 1 | Retain exact episode keys and publish them before the selected item |
| Ready entries disappear after one failed check | Latest provider attempt replaces valid state | Retain the last valid bounded snapshot on partial failure |
| Ready queue actions persist but rows stay visible | Destination captured a static entry snapshot | Observe Saved, Played, and override stores in the destination and project entries live |
| Skip timing breaks playback | Detection owns or blocks the player | Observe the active item as cancelable side work; playback remains authoritative |
| Skip learns from ads or leaks stream data | Unbounded samples or provider payloads persisted | Hash bounded program frames locally and persist no URLs/media/provider bodies |
| All filters unexpectedly reset | One shared or transient query | Persist only successful queries per stable category ID |
| CocoaPods symbols are missing | `.xcodeproj` opened directly | Build and test `Aiyifan.xcworkspace` |
| Huge unrelated project-file diff | Generator run for an ordinary source edit | Regenerate only for source membership, targets, or build settings |
| AVFoundation lifecycle test is flaky | Fake remote media item is discarded asynchronously | Assert durable session state or use playable local media |

## Change Workflow

1. Read this guide, `README.md`, the relevant source owner, and the latest release
   record.
2. Inspect `git status`. Never revert unrelated user changes.
3. State the product invariant and failure path affected by the change.
4. Add or update the smallest failing unit, integration, or UI test first.
5. Implement within the existing ownership boundary. Add a new abstraction only
   when it removes real duplication or isolates a meaningful state machine.
6. Run focused tests while iterating.
7. For a major playback, navigation, provider, persistence, or casting change,
   run the complete regression and release gates once after the code stabilizes.
8. Review the diff for generated churn, secrets, unsafe URL handling, stale tasks,
   and unsupported claims.
9. Update this file when an invariant, architecture boundary, or required gate
   changes. Put volatile test counts and live titles in a dated release record.
10. Commit with a conventional message and push only after verification.

### Project Generation

`scripts/create_xcode_project.rb` creates the project and includes all Swift files
currently present in the app and test directories. It also regenerates project
object identifiers, so running it can produce a large `project.pbxproj` diff.

Run it when adding/removing source files, changing targets, or changing generated
build settings. Do not run it for an ordinary edit to an existing Swift file.

```sh
ruby scripts/create_xcode_project.rb
pod install
```

After generation, inspect the project diff and build the workspace immediately.

## Verification

### Focused Tests

Prefer affected tests during development:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/NativePlayerViewModelTests \
  CODE_SIGNING_ALLOWED=NO
```

Use the same form with a test class or test method under `AiyifanUITests` for a
focused UI scenario.

### Major Regression

Run after major changes and before push or device deployment:

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO
```

The UI suite uses deterministic fixtures. Keep the 50-plus-action power-user
scenario as a release gate rather than running it after every small edit.

### Release Gates

```sh
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
pod outdated
git diff --check
git status --short
```

Also inspect tracked app, test, and documentation files for credentials or private
keys before committing. Review `git diff` rather than trusting a pattern scan
alone.

### Live Provider Checks

Fixtures prove deterministic contracts; they do not prove the provider still
serves the same current shape. Before a provider-facing release, use bounded,
read-only checks to verify:

- All four Home categories return valid native items.
- All catalog filter metadata and page requests still decode.
- One current movie resolves to a reachable HTTPS HLS program.
- One serial title returns multiple newest-first episodes.
- Its newest and one older episode resolve without substituting another episode.
- A saved serial title can establish or compare a direct update baseline.
- A multi-variant stream exposes manual quality choices when available.

Do not print or retain signed URLs, certificates, cookies, or playlist bodies in
test logs or release notes.

### Hardware Checks

The simulator cannot validate these claims. Keep them pending until observed on
physical devices:

- Lock the iPhone while playing and confirm audio and Now Playing controls.
- Collapse and expand the player without a timestamp reset.
- Enter and leave fullscreen and Picture in Picture without stopping playback.
- Route to Apple TV/AirPlay and verify continuity.
- Cast to Android TV/Chromecast and verify handoff and remote controls.
- Deliver a local update notification and open its exact episode deep link.
- Observe a background refresh opportunity; do not infer exact scheduling from a
  successful foreground Check Now.

## Device Build And Install

Use placeholders instead of committing machine-specific identifiers:

```sh
xcrun devicectl list devices

xcodebuild build \
  -workspace Aiyifan.xcworkspace \
  -scheme Aiyifan \
  -configuration Debug \
  -destination 'id=<xcode-device-udid>' \
  DEVELOPMENT_TEAM=<apple-team-id> \
  -allowProvisioningUpdates

xcrun devicectl device install app \
  --device <coredevice-id> \
  <derived-data-path>/Build/Products/Debug-iphoneos/Aiyifan.app

xcrun devicectl device process launch \
  --device <coredevice-id> \
  --terminate-existing \
  com.john.aiyifan
```

The Xcode destination UDID and CoreDevice ID are different identifiers. Obtain
both from current tooling instead of copying an old release record. The phone
must be connected, unlocked, trusted, and supported by the installed Xcode.

Personal Team builds keep local Saved, Played, progress, and settings but cannot
use the iCloud entitlement. Generate an eligible iCloud build explicitly:

```sh
AIYIFAN_DEVELOPMENT_TEAM=<apple-team-id> \
AIYIFAN_ICLOUD_ENABLED=1 \
ruby scripts/create_xcode_project.rb
pod install
```

## Definition Of Done

A change is complete only when:

- The requested behavior works through the native user flow.
- Existing product invariants remain intact.
- Focused tests pass, and major changes pass the complete regression.
- Release build and static analysis pass when required.
- Provider checks and hardware checks are reported separately and honestly.
- No sensitive or short-lived provider data is persisted or logged.
- Documentation reflects changed decisions without embedding volatile evidence.
- The committed revision matches the pushed revision and, when requested, the
  revision installed on the device.
