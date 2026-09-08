# Aiyifan Skip Intro And Outro Design

## Goal

Provide reliable, user-controlled `Skip Intro` and `Skip Outro` actions for
serial content without requiring provider markers, uploading viewing data, or
interrupting playback. Detection is local-first, conservative, reversible, and
independent of Ready to Watch.

## Product Scope

When a high-confidence marker exists, the player shows one contextual button in
the existing lower control zone:

- `Skip Intro` seeks to the detected intro end.
- `Skip Outro` seeks to program completion and preserves existing autoplay-next
  behavior.

The action never runs automatically. After a skip, a short `Undo` action seeks
back to the pre-skip position. The existing More menu adds:

- `Set Intro End Here`
- `Set Outro Start Here`
- `Disable for This Series`
- `Reset Learned Timing`

These controls apply to serial titles. Movies retain ordinary seek controls.

## Technical Constraints

The provider currently supplies episodes and playback streams but no dependable
intro or outro markers. Aiyifan must not assume arbitrary extraction works for
every stream.

Apple documents that `AVAssetImageGenerator` can extract from remote file media,
but HLS image generation requires an I-frame-only rendition. The primary path
therefore collects sparse frames from active playback with
`AVPlayerItemVideoOutput`. Off-playback image generation is an optimization used
only when the asset reports that it is readable or the HLS stream exposes the
required I-frame support.

References:

- https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset
- https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput
- https://developer.apple.com/documentation/avfoundation/avasset

## Detection Pipeline

### 1. Provider And Asset Markers

Inspect validated navigation markers and timed metadata first. Accept a marker
only when its type, time range, and program duration are internally consistent.
Unknown metadata is ignored; it is never treated as a skip instruction.

### 2. Sparse Playback Sampling

Attach a `SkipFingerprintSampler` to program entries only. Separately supplied
advertisement entries are excluded.

- Downscale sampled frames to 32-by-32 luminance before hashing.
- Sample every two seconds during the first eight minutes and final six minutes.
- Process on a utility-priority task and retain no pixel buffers after hashing.
- Pause sampling during seeks, buffering, PiP transitions, app suspension, and
  remote Cast playback.
- Resume opportunistically when normal local playback supplies frames again.
- Use any active network connection, as selected, but never request a higher
  rendition or delay playback for analysis.

The store retains only timestamped 64-bit perceptual hashes and duration, capped
at three recent episodes per series and 500 hashes per episode. Older samples
are removed atomically.

### 3. Cross-Episode Matching

`SkipMarkerDetector` compares episodes from the same stable title ID with a
sliding alignment:

- A frame matches when perceptual-hash Hamming distance is at most 10 bits.
- A candidate sequence spans at least 30 seconds with at least 85 percent
  matching samples.
- Intro candidates must lie within the first eight minutes.
- Outro candidates must lie within the final six minutes and are aligned by
  seconds remaining, not absolute playback time.
- At least two distinct episodes must agree within 10 seconds.
- The published marker confidence must be at least 0.85.

Agreement from additional episodes raises confidence. A conflicting episode is
an outlier and receives no automatic marker until the remaining evidence still
passes policy. All constants live in immutable `SkipDetectionPolicy` values so
tests can exercise boundaries without duplicating magic numbers.

### 4. Marker Publication

`SkipMarkerStore` keeps one `SeriesSkipProfile` per title:

- Optional intro start and end.
- Optional outro start as seconds remaining.
- Confidence and agreeing episode count.
- Source: provider, learned, or user corrected.
- Updated date, disabled state, and schema version.

User-corrected values override provider and learned values until Reset. Reset
removes user correction and collected samples, then restarts learning from new
playback. Disable hides skip controls and stops sampling for that title.

## Player Behavior

The view model derives an immutable `SkipOpportunity` from the current program
position, duration, and series profile.

- Learned `Skip Intro` appears from five seconds after program start until the
  intro end. If a learned intro start is later, it appears at that start.
- A user-set intro end may show from five seconds because no intro start is
  required; the user remains in control of whether to tap it.
- `Skip Outro` appears at the accepted outro start and remains until completion.
- Buttons disappear while loading, seeking, on advertisements, after the target,
  or when the current playback endpoint cannot seek.
- Undo remains available for eight seconds and returns to the exact valid
  pre-skip program position.

Skipping uses the existing program seek path so progress, Now Playing, and
autoplay stay consistent. Undo does not weaken a marker automatically; incorrect
timing is corrected or reset explicitly.

## AirPlay, Cast, And Background Playback

AirPlay continues to use the local AVPlayer, so accepted markers seek through
the normal local path. During Google Cast, existing profiles may show in the
expanded Cast controller only when the receiver reports a seekable stream.
Cast seeks use confirmed remote-media callbacks. Cast playback does not collect
new fingerprints because decoded frames are on the receiver.

Background audio and Lock Screen playback remain unaffected. Custom skip buttons
are not added to system Now Playing controls; existing 15-second and position
commands remain. Sampling may pause when rendered frames are unavailable and
resume later without affecting audio, PiP, or saved progress.

## Persistence And Optional Sync

Use separate versioned stores for `EpisodeFingerprint` and
`SeriesSkipProfile`:

- Fingerprints remain local and never sync.
- Confirmed marker timestamps, source, confidence, correction, and disabled
  state may join the existing iCloud library payload when Sync Library is
  enabled.
- Signed stream URLs, certificates, cookies, frames, and provider responses are
  never stored.

Existing cloud payloads decode with empty marker fields. Conflicts prefer a user
correction over learned data, then the newest update date. A newer explicit
Reset or Disable operation wins over older markers.

## Failure Handling And Safeguards

- Unsupported, unreadable, live, indefinite-duration, audio-only, or protected
  assets skip analysis without affecting playback.
- Insufficient or low-confidence evidence shows no skip button.
- Episode duration differing by more than 20 percent from the profile median is
  treated as an outlier for automatic application.
- Frame extraction and hashing errors are sanitized, bounded, and retryable on
  later playback; they never enter the playback error state.
- Sampling tasks are cancelable and tied to the current player item generation.
- Memory-pressure and Low Power Mode stop sampling immediately while playback
  continues.
- Marker targets are clamped to valid program duration before every local or
  remote seek.

## Component Boundaries

- `SkipFingerprintSampler`: obtains sparse program frames and returns hashes.
- `PerceptualFrameHasher`: pure low-resolution hash implementation.
- `SkipMarkerDetector`: pure alignment, candidate, and confidence logic.
- `SkipMarkerStore`: versioned profiles, samples, corrections, reset, and bounds.
- `SkipOpportunityProjector`: pure position-to-button state.
- Player and Cast view models consume these protocols and own only orchestration.

No detector code belongs in `NativePlaybackResolver`, SwiftUI card views, or the
provider request signer.

## Test Strategy

Write failing tests before each implementation slice. Test fixtures use locally
generated synthetic media and contain no provider video.

### Unit Tests

- Perceptual hash stability, distance thresholds, and downscaling.
- Intro and outro alignment, seconds-remaining conversion, minimum sequence,
  confidence, outliers, and duration sanity checks.
- Provider, learned, corrected, disabled, reset, and conflict precedence.
- Skip opportunity visibility at every boundary and target clamping.
- Store bounds, corruption recovery, migration, and iCloud merge behavior.

### Integration Tests

- Two synthetic episodes with repeated opening and ending sequences produce
  accepted markers; dissimilar episodes do not.
- Program-only sampling excludes advertisement queue entries.
- Local Skip and Undo preserve Played progress and Now Playing state.
- Outro skip reaches existing autoplay-next without creating duplicate records.
- Player-item replacement cancels stale sampling and cannot publish old markers.
- AirPlay-style local routing and fake Cast seekability produce correct controls.

### UI And Heavy-User Tests

- Skip Intro, Skip Outro, Undo, correction, disable, and reset controls.
- No control for movies, low confidence, unsupported streams, advertisements, or
  nonseekable Cast sessions.
- Rotation, fullscreen, mini-player return, PiP, background audio, episode
  switching, quality changes, and repeated seeking.
- Long series, short episodes, specials, changing intros, missing endings,
  interrupted sampling, Low Power Mode, and storage pressure.
- CPU, memory, and playback-stall measurements with sampling enabled and
  disabled.
- Full regression after the phase stabilizes, with repository coverage at or
  above 80 percent.

## Documentation Requirement

The implementation is incomplete until `README.md` and `DEVELOPMENT.md` explain:

- The conservative local-first detection model and provider limitations.
- Why active-playback sampling is primary for typical HLS.
- Marker precedence, correction, privacy, storage bounds, and Cast limitations.
- The test-fixture strategy and checklist for extending player intelligence.

## Non-Goals

- No automatic skipping.
- No shared public marker database or hosted detection service.
- No upload of frames, fingerprints, viewing history, or stream URLs.
- No DRM bypass, stream rewriting, media download, or provider countermeasure.
- No promise that every series exposes a marker after its first episode.
- No custom Lock Screen button or Cast receiver.

## Acceptance Criteria

- High-confidence serial markers show reversible Skip Intro or Skip Outro
  actions in the existing player control zone.
- Low-confidence and unsupported content play normally without a nonfunctional
  control or analysis error.
- User correction, disable, and reset behavior follow the exact precedence and
  persistence rules in this specification.
- Sampling never stores frames, blocks playback, analyzes advertisements, or
  leaks signed playback data.
- Local, AirPlay, PiP, background, and seekable Cast behavior remain consistent
  with existing playback ownership and progress rules.
- Automated tests cover all marker, player, persistence, and failure behavior;
  the stabilized full regression passes with at least 80 percent coverage.
- README and developer guidance are updated in the same feature commit series.
