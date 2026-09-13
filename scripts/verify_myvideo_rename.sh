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

scan_targets=(MyVideo MyVideoTests MyVideoUITests MyVideo.xcodeproj/project.pbxproj MyVideo.xcworkspace/contents.xcworkspacedata Podfile README.md DEVELOPMENT.md scripts/create_xcode_project.rb)
legacy_hits="$(/usr/bin/grep -RInE 'Aiyifan|aiyifan|AIYIFAN' "${scan_targets[@]}" 2>/dev/null \
  | /usr/bin/sed -E \
      -e '/ProviderRequestSigner\.swift:/s/aiyifan\.tv//g' \
      -e '/WebViewLoadTrackerTests\.swift:/s#https://www\.aiyifan\.tv/#https://provider.invalid/#g' \
      -e '/LibraryServicesTests\.swift:/s#aiyifan://play#legacy-scheme://play#g' \
  | /usr/bin/grep -E 'Aiyifan|aiyifan|AIYIFAN' \
  || true)"
[[ -z "$legacy_hits" ]] || { printf '%s\n' "$legacy_hits" >&2; exit 1; }

info_plist=MyVideo/Resources/Info.plist
plist_buddy=/usr/libexec/PlistBuddy

assert_plist_value() {
  local key_path="$1"
  local expected="$2"
  local actual
  actual="$($plist_buddy -c "Print :$key_path" "$info_plist")"
  [[ "$actual" == "$expected" ]] || {
    printf 'Unexpected Info.plist value for %s: %s\n' "$key_path" "$actual" >&2
    exit 1
  }
}

assert_plist_value CFBundleDisplayName MyVideo
assert_plist_value CFBundleName MyVideo
assert_plist_value CFBundleURLTypes:0:CFBundleURLName com.john.myvideo
assert_plist_value CFBundleURLTypes:0:CFBundleURLSchemes:0 myvideo
assert_plist_value NSLocalNetworkUsageDescription 'MyVideo uses your local network to find Cast-enabled TVs and streaming devices.'
assert_plist_value BGTaskSchedulerPermittedIdentifiers:0 com.john.myvideo.refresh

if $plist_buddy -c 'Print :CFBundleURLTypes:1' "$info_plist" >/dev/null 2>&1 \
  || $plist_buddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:1' "$info_plist" >/dev/null 2>&1; then
  printf 'Info.plist must register myvideo as its sole URL scheme.\n' >&2
  exit 1
fi

/usr/bin/grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.john.myvideo;' MyVideo.xcodeproj/project.pbxproj
printf 'MyVideo rename contract passed.\n'
