# Aiyifan Daily Watching Verification

Date: 2026-09-07

## Automated Regression

- Full iPhone 17 Pro simulator run after the continuous-playback, quality, episode-recovery, daily-update, and discovery simplification changes: 167/167 actual test cases passed (137 unit/integration, 30 UI).
- App-icon, launch-branding, lock-screen metadata, audio-session, interruption recovery, and MediaPlayer background-artwork regression tests: passed.
- Program-only local/Cast queues, frozen Played timestamps, active-playback-only progress, and fullscreen/Picture in Picture lifecycle tests: passed.
- Native catalog filter, persistent per-category sort, result count, Save/play, pagination, retry, and race-condition tests: passed.
- Always-visible Automatic quality, exact-1080p preference, highest-rendition fallback, persisted manual quality, and in-place player-item updates: passed.
- Shared full/mini player ownership, browsing while playback remains active, independent episode recovery, and four-attempt partial-playlist retry: passed.
- Direct saved-title baseline, deduplication, daily due policy, partial-check handling, per-title notification preference, and episode deep link: passed.
- Deterministic 50-plus-action power-user session: passed on the stable iPhone 17 Pro simulator.
- Release simulator build: passed.
- Xcode static analysis: passed with no findings.

Line coverage is retained only as a diagnostic. The release gate is explicit feature and failure-path coverage.

The long-session scenario repeatedly opens and closes native playback from Latest, Saved, and Played; changes episodes; uses Cast play/pause, seek, and mute controls; traverses all three tabs while the Cast mini controller remains active; then opens the native movie catalog, paginates, saves and plays a page-two title, returns to the same catalog, and verifies the title in Saved.

## Feature Traceability

| Feature or failure path | Automated evidence | Result | Hardware check |
| --- | --- | --- | --- |
| Latest contains only Movies, Series, Variety, and Anime; search and local filtering are absent while All retains provider filters and sorting | `AiyifanLatestTapTests` Latest and catalog scenarios | Passed | No |
| App-owned interface is English while provider titles, episode names, descriptions, and filter values remain original | Static string scan plus latest/catalog/player UI scenarios | Passed | No |
| Native All catalog for all four categories | Matching catalog navigation UI scenario | Passed | No |
| Provider filters, per-category persisted sort and direction, result count, pagination, empty/error/retry behavior | Catalog preference, unit, race, relaunch, and UI scenarios | Passed | No |
| Provider score on Latest and All cards; Likes, Favorites, Score, and Views in native playback | Feed/catalog/resolver unit tests plus score and player-metric UI scenarios | Passed | No |
| Save/favorite add, remove, persistence, and update tracking | Saved store plus Latest/catalog UI scenarios | Passed | No |
| Native movie and serial playback without an implicit web view | Routing, resolver, and playback UI scenarios | Passed | No |
| Complete episode list, newest-first ordering, selection, autoplay continuity, and legacy Played restoration | Resolver, player model, navigator, and episode-picker scenarios | Passed | No |
| Known latest episode starts before an independently retried full episode list; incomplete lists cannot silently substitute episode 1 | Resolver and player model recovery tests | Passed | No |
| Provider advertisement exclusion from local and Cast program queues | Resolver, player, Cast, and UI scenarios | Passed | Receiver confirmation pending |
| Played third tab, frozen inactive timestamps, resume, completion, watched state, restart, remove, and clear | Played store, player model, and Played UI scenarios | Passed | No |
| Fullscreen and Picture in Picture transitions preserve the active player session | Player lifecycle and fullscreen UI scenarios | Passed | PiP pending |
| Back collapses to a retained video mini-player while Latest, Saved, Played, and All remain navigable | Session state tests plus mini-player and power-user UI scenarios | Passed | Continuity pending |
| Always-visible Automatic quality preferring exact 1080p, highest available fallback, and persistent manual native choices when exposed | Quality projection, preference, player-item, and playback-menu UI tests | Passed | AirPlay quality pending |
| Background audio, interruption recovery, and lock-screen metadata/controls | Playback feature contract tests | Passed | Lock-screen playback pending |
| AirPlay and Google Cast controls, handoff metadata, queue, and simulated remote controls | Cast unit and UI scenarios | Passed | Real receivers pending |
| Playback speed, sleep timer, next/previous episode, retry, and explicit website fallback | Playback feature, player model, and routing tests | Passed | No |
| Direct best-effort daily checks for every saved serial title, Settings Check Now/Last Checked, notifications, deep links, cache fallback, optional iCloud merge | Saved store, update policy, notification, and settings scenarios | Passed | Delivery/timing/iCloud pending |
| Popup containment and untrusted URL/redirect/media input rejection | Popup, routing, catalog, resolver, and redirect security tests | Passed | No |
| Long-session navigation and collection consistency over 50 actions | Heavy-user UI scenario | Passed | No |

## Live Provider Checks

- `电影`, `电视剧`, `综艺`, and `动漫` feeds each returned HTTP 200 and eight current items.
- The signed latest-results response exposed provider score data without per-card detail requests.
- The current detail response exposed `good`, `favoriteCount`, `score`, and `view`; malformed individual values are omitted without blocking playback.
- Native catalog pages one and two returned 24 valid items per page for all four categories using the current signed `/api/list/Search` contract.
- Movie smoke check: `特立独行` resolved through the current signed playback API to a reachable HTTPS HLS manifest.
- Serial smoke check: `交锋` returned six episodes, selected newest episode `06`, and resolved to a reachable HTTPS HLS manifest.
- Both playback responses contained one separately supplied provider advertisement before the program; the decoder excluded it and retained only the validated full program stream.

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

## Device Deployment

- John's paired iPhone 17 Pro Max is connected by cable and Developer Mode is enabled.
- The phone runs iOS 26.6.1 with Xcode 26.2. Developer disk image services and the wired device connection are available.
- Xcode created a Personal Team provisioning profile for `com.john.aiyifan`; the signed Debug build installed and launched successfully on the phone.
- The running process was verified from the Mac after the developer profile was trusted on the phone.
- This Personal Team build keeps the library locally and reports iCloud sync as unavailable. A paid-team build can opt into the iCloud entitlement with the documented project-generation environment variables.
