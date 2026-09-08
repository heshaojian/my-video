# Aiyifan Saved Freshness and Compact Cards Design

## Goal

Keep Home and Saved visibly current whenever the user opens Aiyifan, immediately reuse fresher episode information discovered by playback, and reduce poster-card footers from three stacked rows to two compact information groups.

## Automatic Freshness

- A cold app launch refreshes both the Home feed and authoritative episode snapshots for Saved titles.
- Returning to the foreground refreshes Home and Saved when the last app-open refresh is at least 15 minutes old. Rapid app switching must not create duplicate requests.
- Home, Saved, and player observations use one reconciliation path. Search and All retain their existing explicit loading behavior.
- The existing daily background check remains the notification safety net. Foreground refreshes may update visible state without producing duplicate notifications for an already observed episode.
- Pull to refresh on Saved forces a new Saved-title check and exposes bounded progress or failure status.

## Saved Metadata Reconciliation

- Introduce an immutable observation value carrying an item identifier, observation date, optional catalog metadata, and optional episode snapshot.
- `SavedItemsStore` remains the persisted source of truth and applies every observation on the main actor.
- Catalog observations may refresh title, artwork, subtitle, year, region, and other provider metadata for an already saved title.
- Detail and episode observations are authoritative for episode availability. Native playback publishes its resolved or recovered episode list through a callback without depending directly on `SavedItemsStore`.
- Merge episode snapshots by validated media key, retain newest-first order, and never replace a known newer episode with an older or partial response.
- Preserve Save membership, alert preferences, seen state, Ready-to-Watch intent, and Played history during metadata reconciliation.

## Card Projection

- Poster cards consume a display projection rather than assuming the originally saved subtitle is current.
- Saved cards prefer the latest reconciled episode title and fall back to the provider subtitle only when no episode snapshot exists.
- Home, Search, Saved, All, and compact poster rails use the same two-group footer:
  - title, limited to two lines;
  - one compact information row containing the latest update in cyan followed by available year and region in muted text.
- The latest update receives layout priority. Year and region truncate first on narrow cards.
- Score, `NEW`, and Save or Remove controls remain on the poster.

## Failure Handling

- Keep existing visible data when an automatic refresh partially or completely fails.
- Do not advance the successful-refresh timestamp after a partial Saved check, allowing a later app opening or manual refresh to retry.
- Cancel refresh work when its owning task is cancelled and coalesce overlapping app-open checks.
- Do not log or persist playback URLs, certificates, cookies, or media payloads.

## Verification

- Unit-test cold launch, 15-minute foreground throttling, request coalescing, partial failure, manual force refresh, and cancellation.
- Unit-test catalog and episode observation merging, non-regression from episode 10 to 9, persistence, duplicate removal, and preservation of user state.
- Integration-test player resolution and episode-list recovery publishing episode 10 back to Saved.
- UI-test automatic Home and Saved refresh, Saved showing episode 10 after playback discovers it, compact footer behavior on every poster-grid consumer, long titles, missing metadata, and narrow devices.
- Run the full unit suite, relevant heavy-user UI suite, static analysis, and a signed device build before delivery.

## Success Criteria

- Opening Aiyifan updates Home and Saved within the bounded foreground freshness policy.
- After the player displays episode 10, the Saved card cannot continue to display episode 9.
- No delayed or partial response can downgrade a newer Saved episode.
- Poster cards retain the requested information with one title group and one compact metadata row.
