# Aiyifan Native Player Controls Design

## Goal

Replace Aiyifan's persistent custom playback chrome with Apple's standard
`AVPlayerViewController` controls. Playback should feel like a professional iOS
video app, and entering or leaving fullscreen must keep the same player session.

## Product Behavior

- The inline video surface uses native AVPlayer controls for play, pause,
  seeking, elapsed and remaining time, volume, AirPlay, Picture in Picture, and
  fullscreen.
- Aiyifan keeps only app-specific navigation above the video: Back, Episodes,
  playback settings including quality, and Google Cast.
- The custom Previous Episode and Next Episode icons are removed. Users choose
  an episode from the Episodes sheet, while the existing autoplay-next behavior
  remains available through playback settings.
- Skip Intro, Skip Outro, Undo Skip, and the autoplay countdown remain
  contextual prompts. They appear only when actionable and do not recreate a
  persistent transport bar.
- Loading and playback-failure overlays remain because they communicate app
  state and provide Retry or explicit website fallback.
- While Google Cast owns playback, Aiyifan continues using its Cast controls;
  the paused local player must not present misleading active transport state.

## Architecture

`NativePlayerScreen` embeds one `AVPlayerViewController` wrapper with
`showsPlaybackControls` enabled for local playback. The controller retains the
same session-owned `AVQueuePlayer` while iOS presents and dismisses its native
fullscreen interface. Delegate callbacks continue updating fullscreen and
Picture in Picture state in `NativePlayerViewModel`.

The custom `PlaybackChromeOverlay`, manual tap-to-show state, custom fullscreen
cover, and duplicate fullscreen player view are removed. This avoids moving the
same player between two view-controller instances and makes Apple responsible
for transport layout, rotation, safe areas, and accessibility.

Episode ordering, episode selection, quality resolution, Saved synchronization,
Played progress, background audio, lock-screen controls, skip learning, and
Google Cast session ownership remain unchanged.

## Error And Lifecycle Handling

- A loading indicator may cover the video before an AVPlayer item is ready.
- A playback error may cover the video with Retry and Open Website actions.
- Native fullscreen and Picture in Picture transitions must not stop, replace,
  or restart the `AVQueuePlayer`.
- Back collapses the player into the existing mini-player and persists current
  media time as before.
- Scene deactivation, casting, and player teardown continue using the existing
  progress and activity-state paths.

## Test Contract

### Automated Tests

- Assert the native player exists and the custom playback timeline, play/pause,
  rewind, forward, previous-episode, next-episode, and custom fullscreen
  identifiers do not exist.
- Assert Back, Episodes, playback settings, and Google Cast remain available.
- Verify episode selection and autoplay-next behavior remain functional without
  previous/next buttons.
- Verify Saved playback, Played progress, background-state handling, and
  collapse/expand session reuse remain unchanged.
- Exercise native fullscreen entry and return without creating a second player
  session or resetting progress.

### Manual Device Checks

- On a paired iPhone, play a real supported stream and inspect Apple's inline
  controls in portrait and landscape.
- Enter and leave native fullscreen repeatedly and confirm uninterrupted
  playback.
- Confirm native AirPlay and Picture in Picture controls work, then lock the
  screen and verify background audio and Now Playing controls.
- Confirm Episodes, quality selection, Skip Intro/Outro, and Google Cast remain
  reachable without overlapping Apple's controls.

## Scope Boundary

This change replaces playback presentation controls only. It does not change
stream resolution, episode discovery, advertisement handling, Saved/Played
persistence, provider requests, or casting protocols.

## Success Criteria

- No custom transport bar or previous/next episode icons appear over local
  playback.
- Native AVPlayer controls are available inline and in fullscreen.
- A single session-owned player survives fullscreen, Picture in Picture, and
  navigation transitions.
- All app-specific playback features remain available without obscuring native
  controls.
