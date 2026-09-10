# Aiyifan Card Metadata And Resolution Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every poster grid show a compact, trustworthy episode/language/year row and make every provider-exposed playback resolution visible and tappable without risking the current playback session.

**Architecture:** Keep card text normalization inside `PosterCardProjection`. Keep provider source discovery and security validation in the native resolver, combine those sources with AVFoundation variants in `PlaybackQualityMenuProjector`, and let `NativePlayerViewModel` switch direct sources transactionally while retaining the existing item until a replacement is ready.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, AVKit, XCTest, XCUITest, Xcode static analyzer

**Spec:** `docs/superpowers/specs/2026-09-09-aiyifan-card-metadata-resolution-inventory-design.md`

## Global Constraints

- Provider titles, episode labels, languages, and years remain in their original language.
- Never display a raw provider media key as episode metadata.
- Poster titles use exactly one line; the compact detail row directly follows the title.
- Resolution choices come only from secure provider playback sources or AVFoundation HLS variants.
- Every displayed resolution is enabled and tappable.
- A failed quality selection preserves the previous source, timestamp, episode, rate, and play/pause state.
- Automatic prefers exact 1080p, otherwise the highest working source.
- Do not parse or rewrite M3U8 manifests, proxy media, download media, or bypass DRM/provider controls.
- Continue to use one `AVPlayerViewController`; do not reintroduce custom transport or fullscreen controls.
- Run Xcode tests serially to avoid simulator contention.

---

### Task 1: Normalize Poster Metadata And Compact The Shared Card

**Files:**
- Modify: `Aiyifan/App/MediaCard.swift:8-27,125-152`
- Test: `AiyifanTests/SavedLibrarySynchronizationTests.swift:4-52`
- Test: `AiyifanUITests/AiyifanLatestTapTests.swift`

**Interfaces:**
- Consumes: `AiyifanItem`, `SavedEpisodeUpdateState`, `EpisodeNumberParser`
- Produces: `PosterCardProjection.detailText: String?` and stable `-title` / `-detail` accessibility identifiers derived from each card's `itemIdentifier`

- [ ] **Step 1: Add failing projection tests**

Add focused cases that encode the approved precedence and sanitization:

```swift
func testPosterProjectionHidesOpaqueEpisodeKeyAndUsesLanguageAndYear() {
    let key = "fz4AxompbuT"
    let item = AiyifanItem(
        listPath: "series",
        title: "Series",
        subTitle: key,
        year: "2025",
        isSerial: true,
        latestEpisodeKey: key,
        latestEpisodeTitle: key,
        language: "国语"
    )

    XCTAssertEqual(PosterCardProjection(item: item).detailText, "国语 · 2025")
}

func testPosterProjectionUsesResolvedEpisodeThenLanguageAndYear() {
    let item = AiyifanItem(
        listPath: "series",
        title: "Series",
        subTitle: "09",
        year: "2026",
        isSerial: true,
        latestEpisodeKey: "episode-9",
        latestEpisodeTitle: "09",
        language: "粤语"
    )
    let state = SavedEpisodeUpdateState(
        episodes: [EpisodeSelection(mediaKey: "episode-10", title: "10")],
        latestEpisodeKey: "episode-10",
        seenEpisodeKey: "episode-9",
        detectedAt: nil,
        lastObservedAt: nil
    )

    XCTAssertEqual(
        PosterCardProjection(item: item, episodeState: state).detailText,
        "10 · 粤语 · 2026"
    )
}
```

Also cover numeric labels, `Episode 10`, `第10集`, `第10期`, a meaningful special title, missing fields, and movie metadata that must not treat `subTitle` as an episode.

- [ ] **Step 2: Run the projection tests and confirm RED**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/SavedLibrarySynchronizationTests
```

Expected: failures because `detailText` and opaque-key rejection do not exist.

- [ ] **Step 3: Implement the pure projection**

Replace `updateText` and `metadataText` with one optional detail value. Keep helpers private to the projection:

```swift
struct PosterCardProjection: Equatable, Sendable {
    let title: String
    let detailText: String?

    init(item: AiyifanItem, episodeState: SavedEpisodeUpdateState? = nil) {
        title = item.title
        let episode = Self.episodeLabel(item: item, episodeState: episodeState)
        let details = [episode, Self.normalized(item.language), Self.normalized(item.year)]
            .compactMap { $0 }
        detailText = details.isEmpty ? nil : details.joined(separator: " · ")
    }
}
```

`episodeLabel` must evaluate synchronized title, `latestEpisodeTitle`, then `subTitle`; skip values equal to `listPath` or `latestEpisodeKey`; accept recognized numeric/localized episode forms before applying the opaque-key heuristic. The heuristic rejects a whitespace-free 8-128 character token containing both letters and digits when it has no recognized episode form.

- [ ] **Step 4: Implement the compact shared layout**

Use an inner text stack so poster-to-title and title-to-detail spacing are independent:

```swift
VStack(alignment: .leading, spacing: 7) {
    poster
    VStack(alignment: .leading, spacing: 3) {
        Text(projection.title)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityIdentifier("\(itemIdentifier)-title")
        if let detailText = projection.detailText {
            Text(detailText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("\(itemIdentifier)-detail")
        }
    }
}
```

Keep poster ratio, badges, action frames, and 44-point hit targets unchanged.

- [ ] **Step 5: Run projection tests and the shared-card UI scenarios**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/SavedLibrarySynchronizationTests \
  -only-testing:AiyifanUITests/AiyifanLatestTapTests/testCatalogGridKeepsRightColumnSaveActionInsideItsCard \
  -only-testing:AiyifanUITests/AiyifanLatestTapTests/testSavedGridKeepsAdjacentCardsInUniformNonOverlappingColumns
```

Expected: PASS, with a new XCUITest assertion that title frames are one line and each detail frame begins within 4 points of the title's bottom edge on Home, Search, Saved, Played, and All fixture cards.

- [ ] **Step 6: Commit the card change**

```bash
git add Aiyifan/App/MediaCard.swift AiyifanTests/SavedLibrarySynchronizationTests.swift AiyifanUITests/AiyifanLatestTapTests.swift
git commit -m "fix: normalize compact poster metadata"
```

---

### Task 2: Retain Every Secure Provider Resolution Source

**Files:**
- Modify: `Aiyifan/App/PlaybackQuality.swift:18-168`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift:8-39,537-599,711-732`
- Test: `AiyifanTests/NativePlaybackResolverTests.swift:935-1083`
- Test: `AiyifanTests/PlaybackFeaturesTests.swift:10-135`

**Interfaces:**
- Produces: `ProviderPlaybackSource(url:tierHeight:)`, `NativePlayback.qualitySources`, and `PlaybackQualityProjector.normalizedTier(from:)`
- Consumes: existing provider media-host validation and API response size/preview/login checks

- [ ] **Step 1: Add failing provider-source decoder tests**

Use a response containing an ad plus secure 2160p, 1080p, 720p, and duplicate 1080p HLS rows. Assert that playback still has one default program entry while `qualitySources` contains deduplicated `[2160, 1080, 720]` tiers in provider order. Add cases proving an insecure host and an unsupported numeric value never become a quality source.

```swift
XCTAssertEqual(playback.entries.count, 1)
XCTAssertEqual(playback.qualitySources.map(\.tierHeight), [2_160, 1_080, 720])
XCTAssertTrue(playback.qualitySources.allSatisfy { $0.url.scheme == "https" })
```

- [ ] **Step 2: Run resolver and quality tests and confirm RED**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/NativePlaybackResolverTests \
  -only-testing:AiyifanTests/PlaybackFeaturesTests
```

Expected: failures because `qualitySources` and source-tier normalization do not exist.

- [ ] **Step 3: Add the immutable source model and tier normalization**

In `PlaybackQuality.swift`:

```swift
struct ProviderPlaybackSource: Equatable, Identifiable, Sendable {
    let url: URL
    let tierHeight: Int

    var id: Int { tierHeight }
    var title: String { "\(tierHeight)p" }
}
```

Normalize only the explicit provider values `144`, `240`, `360`, `480`, `576`, `720`, `1080`, `1440`, and `2160`; do not reinterpret arbitrary bitrates as dimensions. Extend dimension projection to preserve 1440p rather than folding it into 1080p.

- [ ] **Step 4: Decode all secure program sources without queueing duplicates**

Add `qualitySources: [ProviderPlaybackSource]` to `NativePlayback` with an empty default for source compatibility. In `NativePlaybackResponseDecoder`, collect all secure HLS rows whose provider resolution value normalizes to a supported tier, deduplicate by tier, and retain one default source in `entries`. Keep the current login, preview, HTTPS, host, credentials, private-network, and response-size defenses.

Propagate `playback.qualitySources` through `NativePlaybackResolver.resolveOnce` when combining detail, episode, metrics, and playback results.

- [ ] **Step 5: Run decoder tests and confirm GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit provider source retention**

```bash
git add Aiyifan/App/PlaybackQuality.swift Aiyifan/App/NativePlaybackResolver.swift AiyifanTests/NativePlaybackResolverTests.swift AiyifanTests/PlaybackFeaturesTests.swift
git commit -m "feat: retain provider resolution sources"
```

---

### Task 3: Build A Source-Faithful Tappable Quality Inventory

**Files:**
- Modify: `Aiyifan/App/PlaybackQuality.swift:129-185`
- Modify: `Aiyifan/App/NativePlayerView.swift:113-133,419-445`
- Test: `AiyifanTests/PlaybackFeaturesTests.swift`
- Test: `AiyifanTests/NativePlayerViewModelTests.swift:8-230`

**Interfaces:**
- Consumes: `[PlaybackQualityOption]` from AVFoundation and `[ProviderPlaybackSource]` from Task 2
- Produces: `PlaybackQualityMenuOption(tierHeight:adaptiveOption:providerSource:)` with no disabled/playability flag

- [ ] **Step 1: Replace synthesized-tier tests with failing source-inventory tests**

Assert that the projector unions only actual adaptive and provider sources, deduplicates by tier, preserves both source references when they share a tier, includes 1440p, and sorts descending:

```swift
let menu = PlaybackQualityMenuProjector.options(
    adaptiveOptions: adaptive,
    providerSources: provider
)
XCTAssertEqual(menu.map(\.tierHeight), [2_160, 1_440, 1_080, 720])
XCTAssertTrue(menu.allSatisfy(\.isSelectable))
```

Add a regression proving `catalogQuality: "4K"` alone produces no manual choices.

- [ ] **Step 2: Run quality tests and confirm RED**

Use the Task 2 test command. Expected: failures against the old advertised-tier union.

- [ ] **Step 3: Implement one enabled menu model per real tier**

Replace `isPlayable` with optional backing sources:

```swift
struct PlaybackQualityMenuOption: Equatable, Identifiable, Sendable {
    let tierHeight: Int
    let adaptiveOption: PlaybackQualityOption?
    let providerSource: ProviderPlaybackSource?

    var id: Int { tierHeight }
    var title: String { "\(tierHeight)p" }
    var isSelectable: Bool { adaptiveOption != nil || providerSource != nil }
}
```

Group by tier and choose one adaptive option and one provider source for each tier. Remove catalog quality from the menu projector. Keep `advertisedQuality` only as non-actionable provider metadata if another view needs it.

- [ ] **Step 4: Publish the combined inventory from the player model**

Store `providerQualitySources` from resolved playback and return:

```swift
PlaybackQualityMenuProjector.options(
    adaptiveOptions: qualityOptions,
    providerSources: providerQualitySources
)
```

Update old tests that expected disabled synthetic 1080p/720p choices. Confirm a single real source remains visible and selectable rather than becoming only status text.

- [ ] **Step 5: Run quality and player-model tests and confirm GREEN**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/PlaybackFeaturesTests \
  -only-testing:AiyifanTests/NativePlayerViewModelTests
```

- [ ] **Step 6: Commit the inventory change**

```bash
git add Aiyifan/App/PlaybackQuality.swift Aiyifan/App/NativePlayerView.swift AiyifanTests/PlaybackFeaturesTests.swift AiyifanTests/NativePlayerViewModelTests.swift
git commit -m "fix: list only provider playback resolutions"
```

---

### Task 4: Switch Direct Quality Sources Transactionally

**Files:**
- Modify: `Aiyifan/App/PlaybackQuality.swift`
- Modify: `Aiyifan/App/NativePlayerView.swift:40-99,419-445,529-695,1285-1332`
- Test: `AiyifanTests/NativePlayerViewModelTests.swift`

**Interfaces:**
- Produces: `PlaybackItemPreparing.prepare(url:)`, `NativePlayerViewModel.qualitySelectionMessage`, and asynchronous quality-source selection
- Consumes: `PlaybackQualityMenuOption` from Task 3 and existing Played/progress/player state
- Test observability: read-only `selectedQualityTier` and `activeProgramURL` properties derived from the active player state; neither property persists signed URLs

- [ ] **Step 1: Add failing success and rollback tests**

Inject a preparation stub. The success test starts on 720p at 42 seconds, selects a 1080p direct source, and asserts the replacement source, selected tier, timestamp, playback rate, episode key, and Played identity are retained. The failure test throws during 2160p preparation and asserts object identity of the existing `AVPlayerItem`, timestamp, selected tier, and playing/paused state remain unchanged.

```swift
viewModel.setQuality(target1080)
try await waitUntil { viewModel.selectedQualityTier == 1_080 }
XCTAssertEqual(viewModel.activeProgramURL, source1080.url)
XCTAssertEqual(viewModel.selectedEpisode?.mediaKey, "episode-10")

viewModel.setQuality(failing2160)
try await waitUntil { viewModel.qualitySelectionMessage != nil }
XCTAssertTrue(viewModel.preparedPlayerItems.first === originalItem)
```

- [ ] **Step 2: Run player-model tests and confirm RED**

Use the Task 3 Step 5 command. Expected: failures because preparation injection and transactional switching do not exist.

- [ ] **Step 3: Add a testable item-preparation boundary**

```swift
@MainActor
protocol PlaybackItemPreparing {
    func prepare(url: URL) async throws -> AVPlayerItem
}

struct AVPlaybackItemPreparer: PlaybackItemPreparing {
    func prepare(url: URL) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw NativePlaybackError.unsupportedMedia
        }
        return AVPlayerItem(asset: asset)
    }
}
```

Inject this dependency into `NativePlayerViewModel`, defaulting to `AVPlaybackItemPreparer`.

- [ ] **Step 4: Implement prepare-before-replace selection**

For an adaptive option on the active source, retain the current item and apply its size/bitrate preference. For a distinct provider source:

1. Capture current time, rate, play/pause state, episode, and current item.
2. Await item preparation without pausing or removing the current item.
3. On success, apply the selected tier, replace the item, seek to the captured time, and restore play/pause and rate.
4. Update `playbackItems`, `playbackEntries`, future Cast preparation, preference storage, and quality inspection only after successful replacement. Do not claim receiver-side resolution control for an already-running Cast session.
5. On failure, leave all playback state unchanged and publish `<tier> could not be played. Continuing with <current tier>.`

Cancel a stale selection task when a newer resolution, episode, retry, stop, or teardown action begins. Auto-dismiss the nonterminal message after four seconds, while allowing a later failure to replace it immutably.

- [ ] **Step 5: Run player-model tests and confirm GREEN**

Use the Task 3 Step 5 command. Expected: PASS.

- [ ] **Step 6: Commit transactional switching**

```bash
git add Aiyifan/App/PlaybackQuality.swift Aiyifan/App/NativePlayerView.swift AiyifanTests/NativePlayerViewModelTests.swift
git commit -m "feat: switch playback quality without losing progress"
```

---

### Task 5: Expose Every Resolution As An Enabled Native Menu Action

**Files:**
- Modify: `Aiyifan/App/NativePlayerView.swift:1070-1084,1185-1230,1285-1332`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift` fixture resolver
- Test: `AiyifanUITests/AiyifanLatestTapTests.swift:750-770`

**Interfaces:**
- Consumes: `qualityMenuOptions` and `qualitySelectionMessage` from Tasks 3-4
- Produces: enabled `playbackQuality-<tier>` controls and nonterminal `qualitySelectionMessage` feedback

- [ ] **Step 1: Add failing UI tests for enabled quality choices**

Extend the deterministic fixture playback to expose 2160p, 1080p, 720p, and 480p sources. Open the Quality menu and assert every fixture tier exists, is enabled, and is hittable. Add the launch argument `-AiyifanFailQualityTier 2160`; when the existing `-AiyifanUseFixtureFeed` mode is active, inject a `PlaybackItemPreparing` fixture that throws only for the matching tier URL. Assert the quality message appears while the native player and its current-time session remain present. Production builds continue to use `AVPlaybackItemPreparer` and never read this test argument.

- [ ] **Step 2: Run focused UI tests and confirm RED**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanUITests/AiyifanLatestTapTests/testPlayerAlwaysOffersAutomaticQualityControl \
  -only-testing:AiyifanUITests/AiyifanLatestTapTests/testEveryProviderResolutionIsEnabledAndTappable \
  -only-testing:AiyifanUITests/AiyifanLatestTapTests/testFailedResolutionKeepsNativePlaybackActive
```

Expected: new fixture options are absent or disabled.

- [ ] **Step 3: Replace disabled menu rows with commands**

Render every projected choice through the same `Button` path and remove the lock icon, unavailable suffix, empty action, and `.disabled(true)` branch. Keep the checkmark on the successful manual selection.

Show `qualitySelectionMessage` inside `PlaybackPromptOverlay` as compact playback feedback. Give it a stable `qualitySelectionMessage` accessibility identifier and do not replace the terminal playback error overlay.

- [ ] **Step 4: Run focused UI tests and confirm GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the player UI change**

```bash
git add Aiyifan/App/NativePlayerView.swift Aiyifan/App/NativePlaybackResolver.swift AiyifanUITests/AiyifanLatestTapTests.swift
git commit -m "fix: enable every provider quality choice"
```

---

### Task 6: Update Developer Guidance And Run The Major-Change Gate

**Files:**
- Modify: `README.md`
- Modify: `DEVELOPMENT.md:170-186`
- Review: every file changed in Tasks 1-5

**Interfaces:**
- Consumes: completed card and quality behavior
- Produces: durable development guidance and a verified release candidate

- [ ] **Step 1: Update documentation**

Replace the obsolete rule that only proven multi-rendition choices appear. Document:

- compact one-line poster titles and episode/language/year projection;
- rejection of opaque episode identifiers;
- provider/HLS sources as the only resolution inventory;
- every listed resolution is tappable;
- catalog quality does not synthesize choices;
- failed selection preserves playback and progress.

- [ ] **Step 2: Run the native UI quality checklist**

Read `.agents/skills/ui-ux-pro-max/references/pro-rules.md` and `.agents/skills/web-design-guidelines/SKILL.md`. Check one-line truncation, no overlap, compact spacing, dark-mode contrast, 44-point actions, VoiceOver labels, safe-area clearance, and stable card geometry at iPhone 17 Pro and iPhone SE-sized simulator viewports.

- [ ] **Step 3: Run the complete unit suite with coverage**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -enableCodeCoverage YES \
  -resultBundlePath /tmp/Aiyifan-card-quality-unit.xcresult \
  -only-testing:AiyifanTests
xcrun xccov view --report --json /tmp/Aiyifan-card-quality-unit.xcresult
```

Expected: all tests pass and the `xccov` report shows app-source coverage remains at least 80 percent. Before running, move any pre-existing bundle at that exact temporary path aside with a timestamp so `xcodebuild` can create a fresh result bundle without deleting evidence.

- [ ] **Step 4: Run the complete serial UI suite**

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanUITests
```

Expected: all UI tests pass, including both power-user scenarios and native fullscreen round-trip.

- [ ] **Step 5: Run build and static analysis**

```bash
xcodebuild analyze -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `ANALYZE SUCCEEDED`.

- [ ] **Step 6: Review security and the final diff**

Confirm all provider media URLs still pass `RemoteResourceHostValidator`, no signed query URLs are logged or persisted, no new secrets exist, selection tasks cancel safely, and no unrelated `.agents/` or `skills-lock.json` files enter the commit.

```bash
git diff --check
git status --short
git diff --stat 48fa6db..HEAD
```

- [ ] **Step 7: Commit documentation and verification adjustments**

```bash
git add README.md DEVELOPMENT.md
git commit -m "docs: record card and quality selection rules"
```

- [ ] **Step 8: Run correctness and security review before delivery**

Use the code-reviewer and security-reviewer agents on the final diff. Resolve every Critical or High finding, rerun the affected focused tests, and repeat the full gate only when the fix changes shared playback or card behavior.
