# Aiyifan Daily Watching Verification

Date: 2026-09-07

## Automated Regression

- Full iPhone 17 Pro simulator run: 87/87 passed (68 unit, 19 UI).
- App-source line coverage: 84.04% (6,777/8,064 executable lines).
- Critical UI repeatability: 15/15 runs passed across three iterations.
- Deterministic 50-plus-action session: passed on iPhone 17 Pro and iPhone 16e simulators.
- Release simulator build: passed.
- Xcode static analysis: passed with no findings.

The long-session scenario repeatedly opens and closes native playback from Latest, Saved, and Played; changes episodes; uses Cast play/pause, seek, and mute controls; and traverses all three tabs while the Cast mini controller remains active.

## Live Provider Checks

- `电影`, `电视剧`, `综艺`, and `动漫` feeds each returned HTTP 200 and eight current items.
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
