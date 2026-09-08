# Aiyifan Skip Intro And Outro Implementation Plan

## Objective

Add conservative visual intro/outro learning and reversible player actions for
serial content. Detection observes normal playback, never gates resolution or
startup, never stores frames, and preserves the current transport-control work.

## Working Rules

- Write tests before each implementation slice.
- Use visual fingerprints only; audio fingerprinting is out of scope.
- Analyze program entries only, never separately supplied advertisements.
- Never create a second player, download media, inspect signed playlists, or
  request a higher rendition for detection.
- Require two episodes and high confidence for learned markers.
- Keep automatic detection out of `NativePlaybackResolver`.
- Manual correction is always available for serial titles.

## Slice 1: Domain Model And Opportunity Projection

Files:

- Add `Aiyifan/App/SkipIntroOutroModels.swift`.
- Add `Aiyifan/App/SkipOpportunityProjector.swift`.
- Add `AiyifanTests/SkipOpportunityProjectorTests.swift`.

Steps:

1. Add failing tests for intro and outro boundaries, seconds-remaining math,
   movies, advertisements, loading, seekability, disabled profiles, correction
   precedence, and target clamping.
2. Add immutable detection policy, fingerprint, profile, marker source,
   tombstone, and skip-opportunity values.
3. Implement one pure projector from profile and playback state to contextual
   action.
4. Run opportunity tests.

## Slice 2: Versioned Marker And Fingerprint Storage

Files:

- Add `Aiyifan/App/SkipMarkerStore.swift`.
- Add `AiyifanTests/SkipMarkerStoreTests.swift`.

Steps:

1. Add failing tests for round trips, corrupt and future versions, correction,
   disable, reset tombstones, duration outliers, three-episode and 500-hash
   bounds, pruning, and deterministic cloud merges.
2. Persist compact profiles and operations in a versioned local envelope.
3. Persist bounded fingerprints separately in Application Support so large
   sample sets never enter iCloud key-value storage.
4. Keep in-memory playback behavior available after persistence failures and
   expose only sanitized diagnostics.

## Slice 3: Perceptual Frame Hashing

Files:

- Add `Aiyifan/App/PerceptualFrameHasher.swift`.
- Add `AiyifanTests/PerceptualFrameHasherTests.swift`.

Steps:

1. Add in-memory pixel-buffer fixtures for deterministic patterns, brightness
   changes, dissimilar frames, odd row strides, and orientation transforms.
2. Downscale to 32-by-32 luminance and produce a 64-bit block-average hash.
3. Implement and test Hamming distance without retaining image data.
4. Run hashing tests and measure bounded allocations.

## Slice 4: Cross-Episode Marker Detection

Files:

- Add `Aiyifan/App/SkipMarkerDetector.swift`.
- Add `AiyifanTests/SkipMarkerDetectorTests.swift`.

Steps:

1. Add failing tests for two-second samples, 30-second sequence minimum, 85
   percent agreement, 10-bit frame distance, two-episode minimum, 10-second
   timing tolerance, first-eight/final-six-minute windows, and duration outliers.
2. Implement sliding alignment for intro absolute time and outro seconds
   remaining.
3. Add tests for changing openings, specials, short episodes, missing endings,
   and additional episodes raising or lowering confidence.
4. Publish only markers with confidence of at least 0.85.

## Slice 5: AVFoundation Sampling And Metadata

Files:

- Add `Aiyifan/App/SkipFingerprintSampler.swift`.
- Add `Aiyifan/App/SkipMetadataInspector.swift`.
- Add `AiyifanTests/SkipFingerprintSamplerTests.swift`.
- Add `AiyifanTests/SkipMetadataInspectorTests.swift`.

Steps:

1. Add protocol-backed tests for sampling windows, two-second throttling,
   cancellation generation, duplicate frames, and one outstanding hash.
2. Attach `AVPlayerItemVideoOutput` only after a program item is ready.
3. Pause sampling during seeks, buffering, suspension, PiP transitions, Cast,
   Low Power Mode, and memory pressure; release each pixel buffer immediately.
4. Inspect recognized, internally consistent navigation/timed markers at the
   player-item boundary and ignore unknown metadata.
5. Keep `AVAssetImageGenerator` optional and restricted to readable assets or
   HLS with supported I-frame extraction.

## Slice 6: Player Orchestration And UI

Files:

- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify `AiyifanTests/NativePlayerViewModelTests.swift`.
- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.

Steps:

1. Add failing model tests for perform skip, eight-second Undo, correction,
   disable, reset, progress and Now Playing consistency, stale cancellation,
   and outro-to-autoplay without duplicate records.
2. Inject store, detector, sampler, clock, and generation dependencies.
3. Refactor the current ten-second seek path through one absolute program seek.
4. Add one contextual Skip Intro or Skip Outro button to the existing bottom
   transport zone, plus an eight-second Undo.
5. Add Set Intro End Here, Set Outro Start Here, Disable for This Series, and
   Reset Learned Timing to the existing More menu for serial content only.
6. Add deterministic launch fixtures for learned, corrected, disabled, and
   low-confidence profiles and run player UI tests.

## Slice 7: AirPlay And Seekable Google Cast

Files:

- Modify `Aiyifan/App/Casting.swift`.
- Modify `Aiyifan/App/CastControlsView.swift`.
- Modify `AiyifanTests/CastingTests.swift`.

Steps:

1. Add failing tests for local/AirPlay seek, seekable and nonseekable Cast
   snapshots, clamping, pending remote confirmation, advertisements, and
   disconnects.
2. Add explicit seekability to the Cast snapshot and protocol.
3. Derive Google Cast seek support from confirmed receiver media commands.
4. Show accepted skip actions in expanded Cast controls only when the receiver
   confirms seeking; Cast playback never collects fingerprints.

## Slice 8: Optional iCloud Marker Migration

Files:

- Modify `Aiyifan/App/LibraryServices.swift`.
- Modify `Aiyifan/App/AppSettingsView.swift`.
- Modify `AiyifanTests/LibraryServicesTests.swift`.

Steps:

1. Add failing tests for current payload decoding, empty marker defaults,
   corrected-over-learned precedence, newest reset or disable, and proof that
   fingerprints never encode into cloud data.
2. Extend the backward-compatible cloud envelope with compact profiles and
   tombstones only.
3. Keep local profiles functional when iCloud is disabled or unavailable.

## Slice 9: Synthetic Integration, Documentation, And Review

Files:

- Add generated synthetic-media integration fixtures and tests.
- Modify `README.md`.
- Modify `DEVELOPMENT.md`.
- Modify the dated release verification record with verified facts only.

Steps:

1. Generate local, original test media with repeated and nonrepeated opening and
   ending patterns; never commit provider video.
2. Test two episodes to marker to Skip and Undo, program-only sampling, outro
   autoplay, stale item replacement, PiP, background audio, and fake Cast.
3. Exercise long series, specials, quality changes, interrupted sampling, Low
   Power Mode, memory pressure, rotation, fullscreen, and repeated seeking.
4. Update README and DEVELOPMENT with HLS constraints, privacy, precedence,
   correction, storage bounds, testing, and the player-intelligence checklist.
5. Run the project generator once after all new files exist and inspect the
   generated diff before accepting it.
6. Run focused tests, full coverage, Release build, static analysis, plist and
   script validation, dependency review, secret/privacy scan, and code review.
7. Resolve every critical and high finding before commit.

## Focused Verification

```sh
xcodebuild test \
  -workspace Aiyifan.xcworkspace -scheme Aiyifan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:AiyifanTests/SkipOpportunityProjectorTests \
  -only-testing:AiyifanTests/SkipMarkerStoreTests \
  -only-testing:AiyifanTests/PerceptualFrameHasherTests \
  -only-testing:AiyifanTests/SkipMarkerDetectorTests \
  -only-testing:AiyifanTests/SkipFingerprintSamplerTests \
  -only-testing:AiyifanTests/NativePlayerViewModelTests \
  -only-testing:AiyifanTests/CastingTests \
  CODE_SIGNING_ALLOWED=NO
```

## Acceptance Gate

- High-confidence serial profiles show reversible Skip Intro or Skip Outro.
- Unsupported and low-confidence content plays normally without skip controls.
- User correction, disable, reset, AirPlay, and seekable Cast follow the design.
- Detection never stores frames, samples ads, gates playback, or leaks media
  request data.
- Existing transport, fullscreen, mini-player, PiP, background, quality,
  episode, and progress behavior remains green.
- README and DEVELOPMENT enable a new coding agent to extend the subsystem.
- Full stabilized regression passes at 80 percent or greater coverage.
