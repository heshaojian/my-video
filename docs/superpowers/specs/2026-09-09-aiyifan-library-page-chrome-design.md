# Aiyifan Library Page Chrome Design

## Goal

Keep first-class library tabs visually consistent with Home and prevent dark-theme page identity regressions from being fixed as one-off color patches.

## Rule

- Home, Saved, and Played are first-class library tabs and must share the same page identity primitive: BrandMark, small Aiyifan label, large white page title, consistent top spacing, semantic dark background, and optional trailing page action.
- Root Home, Saved, and Played tabs must not attach empty native navigation chrome above the custom `LibraryScreenHeader`; that reserves an invisible navigation bar and pushes the header lower than Home.
- Pushed or modal utility screens, such as Ready to Watch, Filters, Settings, Episodes, and Cast, may use native navigation chrome when that better matches platform behavior.
- Shared dark colors and navigation-bar treatment must come from `LibraryScreenChrome` and `libraryNavigationChrome()`, not duplicated per screen.
- First-class library scroll views must reserve `LibraryScreenChrome.scrollBottomClearance` so poster cards, row actions, and titles can scroll above the floating tab bar.
- If a user reports a black-theme visibility issue on a library tab, review the screen against Home structurally before changing only a foreground color.

## Hidden-Problem Audit

Search for these patterns before shipping visual changes:

- `.navigationTitle(...)` on first-class tabs;
- duplicated BrandMark/page-title markup;
- duplicated dark background `Color(red: 0.055, green: 0.052, blue: 0.073)`;
- duplicated `.toolbarBackground(...)` for library dark navigation bars;
- direct `.foregroundStyle(.black)`, `.foregroundStyle(.primary)`, or `.foregroundStyle(.secondary)` on dark custom surfaces;
- one-off `Text("Home")`, `Text("Saved")`, or `Text("Played")` page identity layouts.

## Verification

- UI-test Home, Saved, and Played title visibility in dark mode.
- Verify the shared BrandMark exists for every first-class library tab.
- Verify title and BrandMark vertical alignment to catch invisible or clipped headers.
- Verify Saved and Played header top positions match Home to catch invisible root navigation chrome.
- Verify Saved/Home/Played content can scroll clear of fixed or floating bottom chrome.
- Keep existing Saved/Played behavior tests for persistence, Ready to Watch, clear-history confirmation, and native-player launch.
