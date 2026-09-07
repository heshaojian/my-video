# Aiyifan Branding And Locked Playback Implementation Plan

Date: 2026-09-07

## Phase 1: Lock-Screen Playback Tests

1. Extract deterministic audio-interruption decisions from the application lifecycle into a small value model.
2. Add failing unit tests for configuration, interruption begin and end, conditional resume, and media-services reset.
3. Add failing tests for Now Playing metadata, command availability, and artwork fallback behavior.
4. Run the focused tests to record RED before implementation.

## Phase 2: Playback Hardening

1. Add an audio-session coordinator that configures `.playback` and `.moviePlayback`, observes interruption and media-services notifications, and reactivates safely.
2. Connect the active native player to the coordinator without pausing when the scene becomes inactive.
3. Extend Now Playing metadata with stable episode labels and bundled or remote artwork.
4. Keep all remote command handlers scoped to the active player and clear them on close.
5. Run focused tests to GREEN, refactor, and rerun the full unit suite.

## Phase 3: Professional Branding

1. Produce a 1024 by 1024 opaque master icon that faithfully preserves the established folded Aiyifan `1` mark and midnight background.
2. Add `Assets.xcassets`, `AppIcon.appiconset`, and a reusable brand image set with valid `Contents.json` metadata.
3. Add a dark system launch screen using the brand image and configure both the checked-in Xcode project and its Ruby generator.
4. Validate alpha, dimensions, asset compilation, small-size legibility, and launch rendering.

## Phase 4: Full Verification

1. Run all unit and UI tests on the iPhone 17 Pro simulator with code coverage.
2. Confirm app-source coverage remains at least 80 percent.
3. Run the Release build and Xcode static analyzer.
4. Review dependencies, secrets, whitespace, and the complete diff.
5. Build and sign against Personal Team `GM4SSCNNUK` for John's iPhone 17 Pro Max.

## Phase 5: Publish And Device Validation

1. Commit the implementation and verification record using conventional commit messages.
2. Push `master` to `origin`.
3. Install and launch the final signed app on John's iPhone.
4. Verify the installed bundle and running process from the Mac.
5. Perform the reachable lock-screen checks and record any actions that require John to lock the phone or use external receivers.
