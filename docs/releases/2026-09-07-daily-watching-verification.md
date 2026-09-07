# Aiyifan Daily Watching Verification

Date: 2026-09-07

## Automated Regression

- Full iPhone 17 Pro simulator run: 103/103 passed (78 unit, 25 UI).
- App-source line coverage: 84.33% (7,463/8,850 executable lines).
- Native catalog open, Save/play, and pagination repeatability: 9/9 passed across three iterations.
- Deterministic 50-plus-action session: passed on iPhone 17 Pro and iPhone 16e simulators.
- Release simulator build: passed.
- Xcode static analysis: passed with no findings.

The long-session scenario repeatedly opens and closes native playback from Latest, Saved, and Played; changes episodes; uses Cast play/pause, seek, and mute controls; traverses all three tabs while the Cast mini controller remains active; then opens the native movie catalog, paginates, saves and plays a page-two title, returns to the same catalog, and verifies the title in Saved.

## Live Provider Checks

- `电影`, `电视剧`, `综艺`, and `动漫` feeds each returned HTTP 200 and eight current items.
- Native catalog pages one and two returned 24 valid items per page for all four categories using the current signed `/api/list/index` contract.
- Movie smoke check: `特立独行` resolved through the current signed playback API to a reachable HTTPS HLS manifest.
- Serial smoke check: `交锋` returned six episodes, selected newest episode `06`, and resolved to a reachable HTTPS HLS manifest.
- Both playback responses contained one provider advertisement before the program, matching the tested mute-and-restore queue policy.

No stream URL, page certificate, cookie, or media payload was saved.

## Security And Dependencies

- Tracked source secret-pattern scan: no findings.
- Google Cast SDK is pinned to `4.8.6`; `GTMSessionFetcher` resolves to `5.3.1`.
- `pod outdated`: no updates available.
- Repository diff and whitespace checks: clean.

## Physical Device Checks Still Required

The simulator cannot prove the following hardware and account-dependent behavior:

- Background audio and lock-screen controls after the iPhone is locked.
- Picture in Picture during app switching.
- Local update notification delivery and notification deep-link launch.
- iCloud Saved/Played merge between two signed-in devices.
- AirPlay playback on Apple TV or another Apple receiver.
- Google Cast discovery and playback on Chromecast or Cast-enabled Android TV.

These checks require a signed iPhone build plus reachable receivers on the same network. The app uses Apple's native route picker and Google's Default Media Receiver; it does not use a custom receiver, proxy, download path, DRM bypass, or provider-control bypass.

## Device Deployment Attempt

- John's paired iPhone 17 Pro Max is connected by cable and Developer Mode is enabled.
- The phone runs iOS 26.6.1 with Xcode 26.2. On the latest retry, developer disk image services were available and the wired device connection was ready.
- The Apple Development certificate for team `VGGZ34H2PS` is valid, but Xcode currently has no signed-in account and no provisioning profile for `com.john.aiyifan`.
- Installation therefore remains blocked only until the existing Apple developer account is added in Xcode so it can create the development profile.
