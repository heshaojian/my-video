# Aiyifan Branding And Locked Playback Design

Date: 2026-09-07
Status: Approved

## Goal

Ship Aiyifan as a polished iPhone application with a recognizable Aiyifan identity and dependable audio playback while the screen is locked. The change must preserve the existing native catalog, Saved, Played, episode, casting, advertisement-muting, Picture in Picture, and website-fallback behavior.

## Brand Identity

- Use the established folded Aiyifan `1` mark: pink left plane, violet center plane, cyan upper plane, and blue lower plane on midnight navy.
- Use the mark alone in the app icon. Do not place small text, a play badge, or an additional rounded rectangle inside the icon.
- Produce a 1024 by 1024 opaque source image with enough optical margin for iOS masks and smaller system presentations.
- Add an Xcode app-icon asset catalog and configure both generated and checked-in project settings to use `AppIcon`.
- Use the same mark on the system launch screen with a restrained midnight background and centered brand image. The first interactive screen remains the native latest-updates experience.
- Keep Aiyifan's existing dark, content-first interface; this change does not introduce decorative marketing screens.

## Locked-Screen Playback

- Native playback uses an `AVAudioSession` configured as `.playback` with `.moviePlayback`, allowing program audio to continue when iOS locks the display.
- Audio-session setup is isolated behind a small coordinator so activation, interruption, media-services reset, and route recovery can be tested independently.
- Locking or backgrounding the app persists watch progress but does not pause the player.
- After an interruption ends, the session is reactivated. Playback resumes only when iOS indicates resumption is appropriate and the program had been playing before the interruption.
- Now Playing publishes title, episode or Aiyifan subtitle, duration, elapsed time, playback rate, and poster artwork when available. A branded fallback artwork is used when a poster cannot be loaded.
- Lock Screen and Control Center expose play, pause, toggle, seek backward 15 seconds, seek forward 15 seconds, scrub, previous episode, and next episode. Unavailable episode commands are disabled.
- Closing the native player clears Now Playing metadata and command handlers. Casting continues to use its own sender controls and pauses local playback on handoff.

## Failure Behavior

- Audio-session activation failures are logged without crashing or exposing private playback data.
- Artwork download failures fall back to the bundled Aiyifan artwork and never block playback.
- Interruption and route events never discard Saved, Played, or progress data.
- Website fallback behavior remains unchanged and cannot claim native Lock Screen support.

## Verification

- Unit tests cover session configuration intent, interruption state transitions, resume decisions, route recovery, Now Playing metadata construction, fallback artwork, and command availability.
- UI tests continue to cover native player entry, repeated open and close, episode controls, Save and Played persistence, muted advertisements, and casting controls.
- The complete unit and UI suite runs with at least 80 percent app-source line coverage after every source change.
- Release build, static analysis, diff review, and secret scan pass before deployment.
- The signed app is installed on John's iPhone 17 Pro Max. Physical checks cover lock while playing, continued audio, Lock Screen metadata and commands, unlock continuity, interruption recovery, headphone or route changes, and Picture in Picture.
- Apple TV AirPlay and Android TV or Chromecast playback remain separate hardware checks requiring reachable receivers on the same network.

## Out Of Scope

- No custom streaming proxy, download path, DRM bypass, provider-control bypass, or custom Cast receiver.
- No account system, public App Store submission, or new backend.
- No claim of affiliation beyond using the Aiyifan identity for this personal client.
