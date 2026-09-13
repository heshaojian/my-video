# MyVideo Clean-Break Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the iOS application and GitHub repository from Aiyifan to MyVideo across source code, runtime identifiers, Xcode/CocoaPods structure, tests, and active documentation.

**Architecture:** Preserve the existing playback and catalog architecture while mechanically replacing the app-owned namespace. Complete the work in three locally verifiable layers—Swift/runtime contracts, build graph/filesystem, then documentation and release gates—before changing the GitHub repository.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, Xcode 26, CocoaPods, Ruby `xcodeproj`, Bash, Git, GitHub CLI

**Spec:** `docs/superpowers/specs/2026-09-13-myvideo-clean-break-rename-design.md`

## Global Constraints

- This is a clean break; do not migrate installed Aiyifan data or support the `aiyifan://` scheme.
- Use `com.john.myvideo`, `com.john.myvideo.tests`, `com.john.myvideo.uitests`, and `com.john.myvideo.refresh` exactly.
- Use `myvideo://` as the only application deep-link scheme.
- Rename app-owned `Aiyifan`, `aiyifan`, and `AIYIFAN` identifiers to the matching MyVideo form.
- Keep `aiyifan.tv` only where it is an externally owned provider hostname in `ProviderRequestSigner.swift`; changing that host would break provider access.
- Preserve iOS 17.0, Swift 6.0, Google Cast SDK 4.8.6, playback behavior, catalog behavior, saved/played behavior, and background refresh behavior.
- Keep the current icon and brand-mark image files because visual inspection confirms they contain only an abstract folded mark and no Aiyifan wordmark.
- Historical files under `docs/superpowers/specs/` and `docs/superpowers/plans/` remain historical records and are excluded from the stale-name gate, except this implementation plan and its approved spec.
- Do not rename the GitHub repository until every local validation gate passes.
- Do not push commits until the user explicitly approves the push.
- Rename the resolved checkout folder and its convenience symlink only after all edits, commits, validation, GitHub operations, and approved pushes finish.

## File Structure

- Rename `Aiyifan/` to `MyVideo/`; it remains the application source/resource root.
- Rename `AiyifanTests/` to `MyVideoTests/`; it remains the unit and integration test root.
- Rename `AiyifanUITests/` to `MyVideoUITests/`; it remains the end-to-end UI test root.
- Rename `Aiyifan.xcodeproj` and `Aiyifan.xcworkspace` to MyVideo equivalents; target and scheme names become `MyVideo`, `MyVideoTests`, and `MyVideoUITests`.
- Rename `AiyifanApp.swift`, `AiyifanCategory.swift`, `AiyifanFeedService.swift`, `AiyifanItem.swift`, `AiyifanItemURLTests.swift`, `AiyifanLatestTapTests.swift`, and `Aiyifan.entitlements` to matching MyVideo filenames.
- Update `scripts/create_xcode_project.rb` as the single source for regenerated Xcode project names and settings.
- Add `scripts/verify_myvideo_rename.sh` as the deterministic stale-name and structure gate.
- Update `README.md` and `DEVELOPMENT.md` as the active documentation surfaces.
- Finally rename `/Users/john/Documents/Documents - BlackTiger/ChatGPT/Yfsp` to `/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo` and replace `/Users/john/Documents/ChatGPT/Yfsp` with `/Users/john/Documents/ChatGPT/MyVideo`.

---

### Task 1: Rename Swift-owned APIs, copy, and runtime identity

**Files:**
- Modify: `Aiyifan/App/AiyifanApp.swift`
- Modify: `Aiyifan/App/AiyifanCategory.swift`
- Modify: `Aiyifan/App/AiyifanFeedService.swift`
- Modify: `Aiyifan/App/AiyifanItem.swift`
- Modify: `Aiyifan/App/BackgroundRefresh.swift`
- Modify: `Aiyifan/App/BrowserView.swift`
- Modify: `Aiyifan/App/BrowserViewModel.swift`
- Modify: `Aiyifan/App/Casting.swift`
- Modify: `Aiyifan/App/CatalogPreferenceStore.swift`
- Modify: `Aiyifan/App/CategoryCatalogService.swift`
- Modify: `Aiyifan/App/CategoryCatalogViewModel.swift`
- Modify: `Aiyifan/App/FeedRepository.swift`
- Modify: `Aiyifan/App/LibraryScreenChrome.swift`
- Modify: `Aiyifan/App/LibraryServices.swift`
- Modify: `Aiyifan/App/MediaCard.swift`
- Modify: `Aiyifan/App/NativeCategoryCatalogView.swift`
- Modify: `Aiyifan/App/NativePlaybackResolver.swift`
- Modify: `Aiyifan/App/NativePlayerView.swift`
- Modify: `Aiyifan/App/NowPlayingCoordinator.swift`
- Modify: `Aiyifan/App/PlaybackFeatures.swift`
- Modify: `Aiyifan/App/PlaybackQuality.swift`
- Modify: `Aiyifan/App/PlaybackSessionController.swift`
- Modify: `Aiyifan/App/PlayedItemsStore.swift`
- Modify: `Aiyifan/App/PosterImage.swift`
- Modify: `Aiyifan/App/ProviderSearchService.swift`
- Modify: `Aiyifan/App/ProviderSearchView.swift`
- Modify: `Aiyifan/App/ProviderSearchViewModel.swift`
- Modify: `Aiyifan/App/ReadyToWatch.swift`
- Modify: `Aiyifan/App/ReadyToWatchOverridesStore.swift`
- Modify: `Aiyifan/App/SavedItemsStore.swift`
- Modify: `Aiyifan/App/SavedItemsView.swift`
- Modify: `Aiyifan/App/SavedLibrarySynchronization.swift`
- Modify: `Aiyifan/App/SavedUpdateService.swift`
- Modify: `Aiyifan/App/SkipMarkerStore.swift`
- Modify: every `AiyifanTests/*.swift` file containing `Aiyifan`, `aiyifan`, or `AIYIFAN`
- Modify: `AiyifanUITests/AiyifanLatestTapTests.swift`

**Interfaces:**
- Consumes: existing `AiyifanItem`, `AiyifanCategory`, `AiyifanDeepLink`, `AiyifanFeedServing`, and app launch-argument contracts.
- Produces: `MyVideoItem`, `MyVideoCategory`, `MyVideoDeepLink`, `MyVideoDeepLinkDestination`, `MyVideoFeedServing`, `MyVideoFeedService`, `MyVideoApp`, `-MyVideo…` launch arguments, and MyVideo-prefixed persistence keys.

- [ ] **Step 1: Change focused tests to the new runtime contract**

In `AiyifanTests/LibraryServicesTests.swift`, change the model/deep-link symbols to `MyVideoItem` and `MyVideoDeepLink`, assert the generated scheme is `myvideo`, reject the removed legacy scheme, and change the notification title expectation:

```swift
func testDeepLinkRoundTripAndRejectsUntrustedAndLegacySchemes() throws {
    let item = MyVideoItem(listPath: "series/42", title: "A Show")
    let url = try XCTUnwrap(MyVideoDeepLink.makeURL(item: item, episodeKey: "ep-4"))
    let destination = try XCTUnwrap(MyVideoDeepLink.parse(url))

    XCTAssertEqual(url.scheme, "myvideo")
    XCTAssertEqual(destination.item, item)
    XCTAssertEqual(destination.episodeKey, "ep-4")
    XCTAssertNil(MyVideoDeepLink.parse(URL(string: "https://example.com/play?id=42")!))
    XCTAssertNil(MyVideoDeepLink.parse(URL(string: "aiyifan://play?id=42")!))
}
```

```swift
XCTAssertEqual(batch.title, "MyVideo: 1 new update")
```

In `AiyifanUITests/AiyifanLatestTapTests.swift`, change the home-brand assertion to:

```swift
XCTAssertTrue(app.staticTexts["MyVideo"].exists)
```

- [ ] **Step 2: Run the focused tests and confirm the RED state**

Run:

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AiyifanTests/LibraryServicesTests
```

Expected: FAIL to compile because `MyVideoItem` and `MyVideoDeepLink` do not exist yet.

- [ ] **Step 3: Apply the app-owned Swift namespace replacement**

Across the files listed in this task, replace tokens with these exact mappings while preserving the external provider host `aiyifan.tv` in `ProviderRequestSigner.swift`:

```text
AiyifanApp                 -> MyVideoApp
AiyifanCategory            -> MyVideoCategory
AiyifanFeedError           -> MyVideoFeedError
AiyifanFeedServing         -> MyVideoFeedServing
AiyifanFeedService         -> MyVideoFeedService
AiyifanItem                -> MyVideoItem
AiyifanDeepLink            -> MyVideoDeepLink
AiyifanDeepLinkDestination -> MyVideoDeepLinkDestination
-Aiyifan                   -> -MyVideo
AIYIFAN_ICLOUD             -> MYVIDEO_ICLOUD
com.john.aiyifan.refresh   -> com.john.myvideo.refresh
aiyifan://                 -> myvideo://
scheme "aiyifan"          -> scheme "myvideo"
app-owned "Aiyifan" copy  -> "MyVideo"
app-owned aiyifan key text -> myvideo key text
aiyifanAdvertisement       -> myvideoAdvertisement
```

The clean-break key replacements include `aiyifanCatalogPreferencesV1`, `aiyifanFeedCacheV1`, `aiyifanUpdateAlertsEnabled`, `aiyifanCloudSyncEnabled`, `aiyifan-updates`, `aiyifanLibraryPayloadV1`, `aiyifanPlaybackRate`, `aiyifanAutoplayNext`, `aiyifanPlaybackQualityV1`, `playedAiyifanItems`, `savedAiyifanItems`, `savedAiyifanMetadata`, `aiyifanReadyToWatchOverrides`, `aiyifanSkipProfilesV1`, `AiyifanPosterImages`, and the app-owned cache directory component `Aiyifan`.

- [ ] **Step 4: Update every unit and UI test reference**

Keep `@testable import Aiyifan` temporarily because the build target is renamed in Task 2, but update all referenced Swift types, expected copy, persistence keys, custom-data keys, and launch arguments to MyVideo forms. Confirm immutability-oriented tests still assert original values are unchanged after replacement APIs are called.

- [ ] **Step 5: Run the old-named target as a temporary GREEN gate**

Run:

```bash
xcodebuild test -workspace Aiyifan.xcworkspace -scheme Aiyifan -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AiyifanTests
```

Expected: PASS for all unit and integration tests under the temporary old target name.

- [ ] **Step 6: Commit the Swift/runtime rename layer**

```bash
git add Aiyifan AiyifanTests AiyifanUITests
git commit -m "refactor: rename app runtime namespace to MyVideo"
```

---

### Task 2: Rename the filesystem, Xcode build graph, and CocoaPods targets

**Files:**
- Create: `scripts/verify_myvideo_rename.sh`
- Rename: `Aiyifan/` to `MyVideo/`
- Rename: `AiyifanTests/` to `MyVideoTests/`
- Rename: `AiyifanUITests/` to `MyVideoUITests/`
- Rename: `Aiyifan.xcodeproj/` to `MyVideo.xcodeproj/`
- Rename: `Aiyifan.xcworkspace/` to `MyVideo.xcworkspace/`
- Rename: `MyVideo/App/AiyifanApp.swift` to `MyVideo/App/MyVideoApp.swift`
- Rename: `MyVideo/App/AiyifanCategory.swift` to `MyVideo/App/MyVideoCategory.swift`
- Rename: `MyVideo/App/AiyifanFeedService.swift` to `MyVideo/App/MyVideoFeedService.swift`
- Rename: `MyVideo/App/AiyifanItem.swift` to `MyVideo/App/MyVideoItem.swift`
- Rename: `MyVideoTests/AiyifanItemURLTests.swift` to `MyVideoTests/MyVideoItemURLTests.swift`
- Rename: `MyVideoUITests/AiyifanLatestTapTests.swift` to `MyVideoUITests/MyVideoLatestTapTests.swift`
- Rename: `MyVideo/Aiyifan.entitlements` to `MyVideo/MyVideo.entitlements`
- Modify: `Podfile`
- Modify: `scripts/create_xcode_project.rb`
- Modify: `MyVideo.xcodeproj/project.pbxproj`
- Modify: `MyVideo.xcworkspace/contents.xcworkspacedata`

**Interfaces:**
- Consumes: Task 1's MyVideo Swift types, launch arguments, runtime IDs, and copy.
- Produces: Xcode modules `MyVideo`, `MyVideoTests`, and `MyVideoUITests`; workspace `MyVideo.xcworkspace`; app product `MyVideo.app`.

- [ ] **Step 1: Write the rename verification script**

Create `scripts/verify_myvideo_rename.sh` with executable mode and this contract:

```bash
#!/usr/bin/env bash
set -euo pipefail

required_paths=(
  MyVideo
  MyVideoTests
  MyVideoUITests
  MyVideo.xcodeproj/project.pbxproj
  MyVideo.xcworkspace/contents.xcworkspacedata
)

for required_path in "${required_paths[@]}"; do
  [[ -e "$required_path" ]] || { printf 'Missing required MyVideo path: %s\n' "$required_path" >&2; exit 1; }
done

legacy_paths=(Aiyifan AiyifanTests AiyifanUITests Aiyifan.xcodeproj Aiyifan.xcworkspace)
for legacy_path in "${legacy_paths[@]}"; do
  [[ ! -e "$legacy_path" ]] || { printf 'Legacy path remains: %s\n' "$legacy_path" >&2; exit 1; }
done

scan_targets=(MyVideo MyVideoTests MyVideoUITests MyVideo.xcodeproj MyVideo.xcworkspace Podfile README.md DEVELOPMENT.md scripts/create_xcode_project.rb)
legacy_hits="$(/usr/bin/grep -RInE 'Aiyifan|aiyifan|AIYIFAN' "${scan_targets[@]}" 2>/dev/null | /usr/bin/grep -vE 'ProviderRequestSigner\.swift:.*aiyifan\.tv' || true)"
[[ -z "$legacy_hits" ]] || { printf '%s\n' "$legacy_hits" >&2; exit 1; }

/usr/bin/grep -q 'com.john.myvideo' MyVideo/Resources/Info.plist
/usr/bin/grep -q '<string>myvideo</string>' MyVideo/Resources/Info.plist
printf 'MyVideo rename contract passed.\n'
```

- [ ] **Step 2: Run the structure contract and confirm the RED state**

Run:

```bash
chmod +x scripts/verify_myvideo_rename.sh
scripts/verify_myvideo_rename.sh
```

Expected: FAIL with `Missing required MyVideo path: MyVideo`.

- [ ] **Step 3: Rename the tracked paths and files**

Use `git mv` for every rename listed in this task so history remains traceable. Do not rename the checkout root; the approved scope renames the app/project roots and remote repository.

- [ ] **Step 4: Update the project generator and Podfile**

In `scripts/create_xcode_project.rb`, use these exact constants and environment names:

```ruby
project_path = "MyVideo.xcodeproj"
bundle_id = "com.john.myvideo"
team_id = ENV.fetch("MYVIDEO_DEVELOPMENT_TEAM", "GM4SSCNNUK")
icloud_enabled = ENV["MYVIDEO_ICLOUD_ENABLED"] == "1"
```

Change target/group/glob/path values to `MyVideo`, `MyVideoTests`, and `MyVideoUITests`, set the compilation condition to `MYVIDEO_ICLOUD`, set the entitlement path to `MyVideo/MyVideo.entitlements`, use `MyVideo.app/.../MyVideo` as `TEST_HOST`, and use `MyVideo` as `TEST_TARGET_NAME`.

In `Podfile`, use:

```ruby
target 'MyVideo' do
  pod 'google-cast-sdk', '4.8.6'

  target 'MyVideoTests' do
    inherit! :search_paths
  end

  target 'MyVideoUITests' do
    inherit! :search_paths
  end
end
```

- [ ] **Step 5: Update module imports and application metadata**

Change all unit-test imports to:

```swift
@testable import MyVideo
```

Set `CFBundleDisplayName` and `CFBundleName` to `MyVideo`, URL type name and bundle ID to `com.john.myvideo`, URL scheme to `myvideo`, local-network text to `MyVideo uses your local network to find Cast-enabled TVs and streaming devices.`, and permitted background identifier to `com.john.myvideo.refresh` in `MyVideo/Resources/Info.plist`.

Update `MyVideo.xcworkspace/contents.xcworkspacedata` so the application reference is `MyVideo.xcodeproj`; keep the CocoaPods reference as `Pods/Pods.xcodeproj`.

- [ ] **Step 6: Regenerate Xcode and CocoaPods integration**

Run:

```bash
ruby scripts/create_xcode_project.rb
pod install
```

Then verify the generated workspace:

```bash
xcodebuild -list -workspace MyVideo.xcworkspace
```

Expected: schemes/targets list `MyVideo`, `MyVideoTests`, and `MyVideoUITests`; no Aiyifan target remains.

- [ ] **Step 7: Run the renamed unit/integration suite**

Run:

```bash
xcodebuild test -workspace MyVideo.xcworkspace -scheme MyVideo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyVideoTests
```

Expected: PASS.

- [ ] **Step 8: Commit the build-graph rename**

```bash
git add MyVideo MyVideoTests MyVideoUITests MyVideo.xcodeproj MyVideo.xcworkspace Podfile Podfile.lock scripts/create_xcode_project.rb scripts/verify_myvideo_rename.sh
git commit -m "refactor: rename iOS project to MyVideo"
```

---

### Task 3: Update active documentation and close the stale-name contract

**Files:**
- Modify: `README.md`
- Modify: `DEVELOPMENT.md`
- Modify: `scripts/verify_myvideo_rename.sh`

**Interfaces:**
- Consumes: Task 2's paths, target names, environment variables, bundle IDs, launch flags, and deep-link scheme.
- Produces: accurate MyVideo setup/build/release instructions and a passing stale-name gate.

- [ ] **Step 1: Run the rename contract and confirm the documentation RED state**

Run:

```bash
scripts/verify_myvideo_rename.sh
```

Expected: FAIL and print Aiyifan references from `README.md` and `DEVELOPMENT.md`.

- [ ] **Step 2: Update active documentation**

Replace current product names, source paths, workspace/scheme/target names, test selectors, bundle IDs, app-product paths, deep-link examples, launch arguments, and environment variables with their MyVideo equivalents. Retain truthful statements about the external YFSP provider, including `https://m.yfsp.tv/`; do not relabel third-party infrastructure as MyVideo.

- [ ] **Step 3: Run documentation and plist validation**

Run:

```bash
scripts/verify_myvideo_rename.sh
plutil -lint MyVideo/Resources/Info.plist MyVideo/MyVideo.entitlements
```

Expected: `MyVideo rename contract passed.` followed by `OK` for both property lists.

- [ ] **Step 4: Verify Debug and Release builds**

Run:

```bash
xcodebuild -workspace MyVideo.xcworkspace -scheme MyVideo -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace MyVideo.xcworkspace -scheme MyVideo -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Expected: both commands end with `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the active documentation**

```bash
git add README.md DEVELOPMENT.md scripts/verify_myvideo_rename.sh
git commit -m "docs: update development guidance for MyVideo"
```

---

### Task 4: Run the full quality, coverage, and simulator gates

**Files:**
- Test: `MyVideoTests/*.swift`
- Test: `MyVideoUITests/MyVideoLatestTapTests.swift`
- Inspect: `MyVideo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Inspect: `MyVideo/Resources/Assets.xcassets/BrandMark.imageset/BrandMark@3x.png`

**Interfaces:**
- Consumes: complete local MyVideo app, workspace, tests, and rename contract.
- Produces: test result bundle, coverage evidence, static-analysis result, and simulator proof.

- [ ] **Step 1: Run the complete suite with coverage**

Run:

```bash
xcodebuild test -workspace MyVideo.xcworkspace -scheme MyVideo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableCodeCoverage YES -resultBundlePath artifacts/MyVideo-Rename.xcresult
```

Expected: unit, integration, and UI tests PASS, including the MyVideo home-brand assertion and `-MyVideo…` fixture flows.

- [ ] **Step 2: Verify app-source coverage remains at least 80%**

Run:

```bash
xcrun xccov view --report --json artifacts/MyVideo-Rename.xcresult > artifacts/MyVideo-Rename-coverage.json
```

Read the `MyVideo.app` executable's `lineCoverage` from the JSON and require a value of at least `0.80`. Do not substitute aggregate coverage that includes Pods or test bundles.

Run:

```bash
jq -er '[.targets[] | select(.name == "MyVideo.app") | .lineCoverage][0] as $coverage | select($coverage >= 0.80) | $coverage' artifacts/MyVideo-Rename-coverage.json
```

Expected: print a numeric value of `0.80` or greater and exit successfully.

- [ ] **Step 3: Run static analysis**

Run:

```bash
xcodebuild analyze -workspace MyVideo.xcworkspace -scheme MyVideo -configuration Debug -destination 'generic/platform=iOS Simulator'
```

Expected: `ANALYZE SUCCEEDED` with no new app-source warnings.

- [ ] **Step 4: Reproduce the renamed app in the simulator**

Boot or reuse an iPhone 17 Pro simulator, install the Debug product, and launch `com.john.myvideo`:

```bash
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/MyVideo.app
xcrun simctl launch booted com.john.myvideo -MyVideoUseFixtureFeed -MyVideoResetSavedItems -MyVideoResetPlayedItems -MyVideoResetCatalogPreferences
xcrun simctl openurl booted 'myvideo://play?item=eyJsaXN0UGF0aCI6ImZpeHR1cmUtbW92aWUiLCJ0aXRsZSI6IkZpeHR1cmUgTW92aWUifQ=='
```

Verify on the rendered simulator that the installed app and in-app header say MyVideo, the abstract icon remains intact, Home loads four fixture sections, and the deep link is handled by MyVideo. Capture a screenshot under ignored `artifacts/` for handoff evidence.

- [ ] **Step 5: Run final local safety checks**

Run:

```bash
scripts/verify_myvideo_rename.sh
git diff --check
/usr/bin/grep -RInE 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (RSA|EC|OPENSSH|DSA|PRIVATE) KEY-----' MyVideo MyVideoTests MyVideoUITests README.md DEVELOPMENT.md scripts || true
```

Expected: rename contract passes, `git diff --check` is silent, and the secret scan prints no matches.

- [ ] **Step 6: Run independent reviews and fix all critical/high findings**

Dispatch the project-required code reviewer and security reviewer against the full rename diff. Re-run the affected focused suite after each correction, then re-run Tasks 4.1–4.5 if any project, runtime identifier, or behavior file changes.

- [ ] **Step 7: Commit reviewer corrections if any**

```bash
git add MyVideo MyVideoTests MyVideoUITests MyVideo.xcodeproj MyVideo.xcworkspace Podfile Podfile.lock README.md DEVELOPMENT.md scripts
git commit -m "fix: address MyVideo rename review findings"
```

Skip this commit only when the review produces no file changes.

---

### Task 5: Rename the GitHub repository and verify the new remote

**Files:**
- Modify local Git metadata: `.git/config` through `git remote set-url`

**Interfaces:**
- Consumes: fully committed and locally validated MyVideo repository from Tasks 1–4.
- Produces: GitHub repository `heshaojian/MyVideo` and local `origin` URL `https://github.com/heshaojian/MyVideo.git`.

- [ ] **Step 1: Confirm the local repository is ready for the external rename**

Run:

```bash
git status --short
git log --oneline -5
gh auth status
gh repo view heshaojian/Aiyifan --json nameWithOwner,url,defaultBranchRef
```

Expected: no uncommitted rename files, authenticated GitHub access, source repository `heshaojian/Aiyifan`, and default branch `master`.

- [ ] **Step 2: Rename the GitHub repository**

Run:

```bash
gh repo rename MyVideo --repo heshaojian/Aiyifan --yes
```

Expected: GitHub reports the repository as `heshaojian/MyVideo`.

- [ ] **Step 3: Update and verify the local remote**

Run:

```bash
git remote set-url origin https://github.com/heshaojian/MyVideo.git
git remote get-url origin
git ls-remote --heads origin master
gh repo view heshaojian/MyVideo --json nameWithOwner,url,defaultBranchRef
```

Expected: both Git and GitHub resolve `heshaojian/MyVideo`, and `master` is readable.

- [ ] **Step 4: Pause for explicit push approval**

Show the user the commit list, full rename diff summary, local validation results, and new GitHub URL. Ask for explicit approval before running the push required to publish the rename commits.

- [ ] **Step 5: Push only after approval and verify published state**

Run after approval:

```bash
git push -u origin master
git status --short --branch
gh repo view heshaojian/MyVideo --json nameWithOwner,url,defaultBranchRef
```

Expected: `master` tracks `origin/master`, the worktree is clean, and GitHub identifies the repository as `heshaojian/MyVideo`.

---

### Task 6: Rename the resolved checkout folder and convenience symlink

**Files:**
- Rename directory: `/Users/john/Documents/Documents - BlackTiger/ChatGPT/Yfsp` to `/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo`
- Replace symlink: `/Users/john/Documents/ChatGPT/Yfsp` with `/Users/john/Documents/ChatGPT/MyVideo`

**Interfaces:**
- Consumes: completed MyVideo repository, verified remote, and clean tracked worktree from Task 5.
- Produces: canonical local checkout `/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo` and convenience path `/Users/john/Documents/ChatGPT/MyVideo`.

- [ ] **Step 1: Resolve and record both current paths**

Run:

```bash
pwd -P
ls -ld /Users/john/Documents/ChatGPT/Yfsp '/Users/john/Documents/Documents - BlackTiger/ChatGPT/Yfsp'
readlink /Users/john/Documents/ChatGPT/Yfsp
```

Expected: the convenience path is a symlink to the resolved `Documents - BlackTiger` checkout.

- [ ] **Step 2: Verify the destination paths do not already exist**

Run:

```bash
test ! -e '/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo'
test ! -L '/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo'
test ! -e /Users/john/Documents/ChatGPT/MyVideo
test ! -L /Users/john/Documents/ChatGPT/MyVideo
```

Expected: all four checks exit successfully. If any destination exists, stop and inspect it; do not overwrite or merge it.

- [ ] **Step 3: Rename the resolved checkout from its parent directory**

Run from `/Users/john/Documents/Documents - BlackTiger/ChatGPT`:

```bash
mv Yfsp MyVideo
```

Expected: the repository now exists at `/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo`.

- [ ] **Step 4: Replace the stale convenience symlink**

Confirm `/Users/john/Documents/ChatGPT/Yfsp` is still a symlink, remove only that exact symlink, and create the new alias:

```bash
test -L /Users/john/Documents/ChatGPT/Yfsp
rm /Users/john/Documents/ChatGPT/Yfsp
ln -s '/Users/john/Documents/Documents - BlackTiger/ChatGPT/MyVideo' /Users/john/Documents/ChatGPT/MyVideo
```

- [ ] **Step 5: Verify the repository from the new path**

Run with working directory `/Users/john/Documents/ChatGPT/MyVideo`:

```bash
pwd -P
git status --short --branch
git remote get-url origin
scripts/verify_myvideo_rename.sh
```

Expected: the resolved path ends in `/MyVideo`, `master` tracks `origin/master`, `origin` is `https://github.com/heshaojian/MyVideo.git`, and the rename contract passes. Reopen the Codex project at `/Users/john/Documents/ChatGPT/MyVideo` if the current workspace no longer resolves.
