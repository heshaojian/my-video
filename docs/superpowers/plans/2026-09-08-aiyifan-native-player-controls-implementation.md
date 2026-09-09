# Aiyifan Native Player Controls Implementation Plan

## Objective

Use one embedded `AVPlayerViewController` for inline and fullscreen playback, let its native chrome own transport controls, and retain only Aiyifan-specific navigation, episode, quality/settings, Cast, skip, autoplay, loading, and recovery actions.

## Working Rules

- Update the UI contract before implementation and confirm it fails against the custom chrome.
- Keep the current `AVPlayer`, queue, progress identity, Now Playing integration, PiP state, and fullscreen callbacks alive across presentation changes.
- Preserve unrelated in-progress resolver changes without staging or rewriting them.
- Do not duplicate native play/pause, seeking, timeline, fullscreen, volume, PiP, or AirPlay controls.
- Run the complete regression after the presentation refactor.

## Slice 1: Native-Control UI Contract

Files:

- Modify `AiyifanUITests/AiyifanLatestTapTests.swift`.

Steps:

1. Replace custom-chrome assertions with a contract that the embedded native player exists and Aiyifan's Back, Episodes, quality/settings, and Google Cast controls remain available.
2. Assert the custom previous, next, timeline, seek, play/pause, fullscreen, and top-bar AirPlay controls are absent.
3. Retain the fullscreen round-trip test through the native AVPlayer fullscreen button.
4. Run the focused tests against the old implementation and record the expected failure.

## Slice 2: Single Native Player Presentation

Files:

- Modify `Aiyifan/App/NativePlayerView.swift`.

Steps:

1. Configure the embedded `NativePlayerController` with native playback controls for local playback.
2. Remove the custom playback-chrome state, tap gesture, transport overlay, custom fullscreen cover, and duplicate fullscreen player controller.
3. Remove the top-bar AirPlay picker because AVPlayer's native chrome owns AirPlay routing.
4. Continue forwarding native fullscreen and Picture in Picture transitions to the view model.
5. Hide local AVPlayer transport while Google Cast owns playback so the paused local session is not misleading.

## Slice 3: Contextual Aiyifan Prompts

Files:

- Modify `Aiyifan/App/NativePlayerView.swift`.
- Modify focused UI tests if placement-specific coverage is needed.

Steps:

1. Extract Skip Intro, Skip Outro, and Undo Skip into a small contextual overlay independent of persistent transport chrome.
2. Keep the autoplay-next cancellation prompt and arrange both prompts above the native bottom controls.
3. Preserve loading, retry, and website-fallback presentation.
4. Verify prompts remain actionable without obscuring native transport controls.

## Slice 4: Documentation And Regression

Files:

- Modify `README.md` and `DEVELOPMENT.md` only where they describe the former hybrid/custom control architecture.

Steps:

1. Document the single-controller ownership rule and the boundary between native playback controls and app-specific actions.
2. Run focused player unit and UI tests.
3. Run the full unit and UI suites, including repeated native fullscreen entry and return.
4. Run static analysis, `git diff --check`, secret scanning, and a signed device build.
5. Perform correctness, accessibility, concurrency, and security review; resolve critical and high findings.

## Delivery

1. Commit only the native-player feature and its documentation, leaving unrelated resolver edits unstaged.
2. Push `master` to `origin`.
3. Recheck paired-device availability, then install and launch the exact signed build on every available paired iPhone over USB or the local network.
4. Report unavailable, locked, failed, or unlaunchable devices separately.

## Acceptance Gate

- Inline playback shows AVPlayer's native transport controls.
- AVPlayer's native fullscreen control enters and exits fullscreen without replacing or restarting the playback session.
- No custom previous, next, seek, timeline, play/pause, fullscreen, or duplicate AirPlay control remains in the full player.
- Back, Episodes, quality/settings, Google Cast, Skip Intro/Outro/Undo, autoplay cancellation, retry, and website fallback remain available where applicable.
- PiP, background/Lock Screen playback, progress persistence, mini-player continuity, episode autoplay, quality selection, Saved, and Played behavior remain covered and green.
