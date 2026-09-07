# Aiyifan Developer Guide Design

Date: 2026-09-07

## Goal

Create one durable, developer-friendly source of truth for extending Aiyifan safely. The guide must help a human developer or coding agent understand the product contract, architectural boundaries, mistakes already encountered, and required verification without reconstructing the project's conversation history.

## Documentation Shape

Add `DEVELOPMENT.md` at the repository root and link it near the top of `README.md`. Keep the README as the short product, build, and run overview. Keep detailed historical designs and release evidence under `docs/`; the new guide should link to those records when useful instead of copying them wholesale.

The guide will be organized for task execution rather than chronology:

1. Non-negotiable product and provider constraints.
2. Repository and architecture map.
3. Feature-specific engineering decisions.
4. Known failure modes and their corrections.
5. Change workflow for developers and coding agents.
6. Test, live-provider, physical-device, and release checklists.
7. Build, signing, installation, and troubleshooting commands.

## Content Contract

### Product Invariants

Document the four native discovery categories, English app interface with original provider content, native-first navigation and playback, persistent Saved and Played behavior, truthful playback progress, newest-first episodes, retained playback while browsing, background audio, Picture in Picture, AirPlay, Google Cast, resolution preferences, and best-effort saved-title updates.

Explicitly state that `WKWebView` is an intentional fallback, not the primary item-detail or playback path. App-owned interfaces must preserve save, episode, quality, and playback controls.

### Architecture Boundaries

Name the source files that own feed/catalog access, request signing and validation, playback resolution, player/session state, Saved and Played persistence, notifications/background refresh, casting, and UI routing. Explain the data flow from a selected item to native playback and from a saved title to an update notification.

Describe ownership rules that prevent lifecycle regressions: one retained playback session owns one player view model; full player and mini-player are presentations of that session; fullscreen and Picture in Picture must not destroy it.

### Provider and Security Rules

Preserve HTTPS and provider-host allowlists, bounded response parsing, redirect validation, validated identifiers, and signed-request construction. Never persist or log provider certificates, signed URLs, cookies, or media URLs. Do not add download, proxy, DRM bypass, custom receiver, or provider-control bypass behavior.

Advertisement handling must remain limited to excluding separately supplied advertisement entries. The app must not claim it can remove advertising embedded in the program stream.

### Failure Knowledge

Record symptoms, causes, and correct patterns for the expensive bugs already encountered:

- Opening native cards in a web page removes app-owned save and episode controls.
- Publishing `selectedItem` before its episode key creates a SwiftUI selection race.
- View-owned players stop during back, fullscreen, or Picture in Picture transitions.
- Inferring Played progress from a timer advances timestamps while media is not playing.
- Trusting an incomplete episode response can silently start episode 1.
- Tying episode-list loading to stream startup makes a playable latest episode wait unnecessarily.
- A single failed playlist response needs bounded retries and a visible retry state.
- Fake remote media URLs make AVFoundation lifecycle tests timing-dependent.
- Rechecking only the short Latest feed misses updates to older saved titles.
- Treating `BGAppRefreshTask` as an exact scheduler creates a false notification promise.
- Opening the `.xcodeproj` omits CocoaPods integration; development uses the workspace.
- Regenerating the Xcode project can create large identifier churn and should be reserved for actual target/source-membership changes.

### Verification Policy

Preserve the agreed development-speed policy:

- Run focused unit or UI tests while iterating.
- Run the complete unit and UI suites after a major refactor and before push or device deployment.
- Treat the deterministic 50-plus-action UI scenario as a major release gate, not a per-edit check.
- Run a Release build, static analysis, plist validation, dependency review, secret scan, and diff review before delivery.
- Use bounded read-only live checks for current provider contracts without recording signing material.
- Keep simulator, live-provider, and physical-device evidence separate. Do not mark receiver discovery, lock-screen playback, Picture in Picture, notification delivery, or background timing as verified without observing them on hardware.

The guide will include commands using `Aiyifan.xcworkspace` and placeholders for device IDs and team IDs so it is reusable beyond one machine.

## Maintenance Rules

`DEVELOPMENT.md` is the durable engineering contract. Update it in the same change whenever an architectural boundary, invariant, required test gate, dependency, or deployment procedure changes. Do not add release-specific test counts or volatile provider titles to it; those belong in dated release verification records.

Every statement in the guide must be checked against the current source, project configuration, or dated release evidence. Avoid aspirational claims and distinguish automated, live, and hardware verification.

## Acceptance Criteria

- A new contributor can identify the correct workspace, key source owners, and safe change workflow without reading historical chats.
- A coding agent can determine what behavior must be preserved and which tests to run for a change.
- The guide explains the known regressions well enough to prevent repeating them.
- Security and provider boundaries are explicit.
- Build, test, signing, install, and launch commands are usable and avoid machine-specific assumptions where possible.
- README links to the guide without duplicating it.
