# MyVideo Clean-Break Rename Design

**Date:** 2026-09-13
**Status:** Approved direction; pending written-spec review

## Goal

Rename the iOS application and repository from Aiyifan to MyVideo across every maintained project surface. The result must build, test, install, and present itself solely as MyVideo.

## Product Decision

This is a clean break, not a compatibility migration.

- The app, test targets, source folders, project, workspace, schemes, products, and repository use the MyVideo name.
- Bundle identifiers move from the `com.john.aiyifan` family to the `com.john.myvideo` family.
- The URL scheme becomes `myvideo`; the old `aiyifan` scheme is removed.
- Background-task identifiers move to the `com.john.myvideo` namespace.
- Existing Aiyifan application data, deep links, and installation identity are not migrated.
- The new MyVideo app may coexist with an existing Aiyifan installation until the old app is removed.

## Rename Scope

### Project structure

- Rename the resolved checkout folder from `Yfsp` to `MyVideo` as the final local action, and replace the convenience symlink `/Users/john/Documents/ChatGPT/Yfsp` with `/Users/john/Documents/ChatGPT/MyVideo`.
- Rename `Aiyifan/`, `AiyifanTests/`, and `AiyifanUITests/` to their MyVideo equivalents.
- Rename `Aiyifan.xcodeproj` and `Aiyifan.xcworkspace` to MyVideo equivalents.
- Rename app-specific source and test filenames and Swift symbols where they contain Aiyifan.
- Update all project references, schemes, build settings, test hosts, scripts, and CocoaPods target names.

### Application metadata and UI

- Set the bundle display name and bundle name to MyVideo.
- Replace user-facing Aiyifan copy, accessibility text, local-network permission copy, notifications, and settings labels with MyVideo.
- Preserve the existing icon artwork unless it visibly contains the old wordmark; if it does, replace only that branded artwork.
- Preserve all playback, catalog, saved-item, casting, and background-refresh behavior.

### Runtime identifiers

- Use `com.john.myvideo` for the app bundle identifier.
- Use `com.john.myvideo.tests` and `com.john.myvideo.uitests` for test bundles.
- Use `com.john.myvideo.refresh` for background refresh registration.
- Use `myvideo` for the application URL scheme and `com.john.myvideo` for its URL type name.
- Replace Aiyifan-prefixed launch arguments, persistent keys, logs, and internal identifiers with MyVideo-prefixed equivalents where present.

### Documentation and repository

- Update active README, development documentation, scripts, and current release guidance to the MyVideo name.
- Historical design and implementation records remain immutable when they describe the app at that earlier point in time, unless they contain commands or paths that are still presented as current.

## Repository Rename

- Rename the GitHub repository from `heshaojian/Aiyifan` to `heshaojian/MyVideo` only after local validation succeeds.
- Update the local `origin` URL to the renamed repository and verify remote access.
- Do not push unrelated local changes.

## Validation

1. Search maintained sources and project configuration for stale Aiyifan identifiers; any intentional historical references must be documented.
2. Regenerate CocoaPods integration for the renamed targets and workspace.
3. Build the app in Debug and Release configurations.
4. Run unit, integration, and UI suites and confirm at least 80% coverage for app sources.
5. Run static analysis and secret/dependency checks appropriate to the project.
6. Launch on a simulator and verify the home-screen name, in-app brand, settings copy, playback entry flow, and `myvideo://` handling.
7. After the local gate passes, rename GitHub, update `origin`, and verify fetch access.
8. After all commits and remote operations finish, rename the checkout folder and its convenience symlink, then verify the repository opens from the new path.

## Failure Handling

- If project or CocoaPods references break, stop the repository rename and repair local configuration first.
- If the clean-break bundle identity conflicts with signing or capabilities, report the exact identifier and entitlement mismatch rather than restoring old identifiers silently.
- If GitHub authentication or permissions block the repository rename, leave the fully validated local rename intact and report the remaining external action.
- Rename the checkout folder last because changing the active path can invalidate the current Codex workspace and shell working directory.

## Out of Scope

- Migrating data from an installed Aiyifan app.
- Supporting `aiyifan://` deep links.
- Redirecting third-party integrations that are not represented in this repository.
- Changing playback, catalog, provider, or casting behavior beyond name-dependent identifiers.
