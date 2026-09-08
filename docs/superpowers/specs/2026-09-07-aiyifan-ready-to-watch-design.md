# Aiyifan Ready to Watch Design

## Goal

Add a compact, dependable Ready to Watch queue to the Saved page without
changing Home, the three-tab navigation, the existing Saved grid, or playback
ownership. The queue combines automatic episode selection with explicit user
ordering and remains useful when provider refreshes fail.

## Product Scope

Ready to Watch appears as a horizontal rail above `All Saved`. It contains only
Saved titles and at most one episode per title. Home, Search, Played, All
catalogs, and the current Saved card grid remain unchanged.

The rail shows artwork, title, episode or resume label, a `NEW` badge when
applicable, and a direct Play action. Tapping a queue card starts that exact
episode. `See All` opens a native queue-management screen with pin,
drag-to-reorder, remove, mark-watched, and Play actions.

## Queue Semantics

### Automatic Candidates

A Saved title contributes one automatic candidate when either condition holds:

1. It has a valid incomplete Played record with progress below the existing
   completion threshold.
2. It has an unseen latest episode discovered by the saved-title update check.

For one title, an incomplete episode wins over a newer episode so the queue does
not jump over unfinished content. Once that episode is completed, the next
available episode becomes eligible. A title that is merely Saved, with no
unfinished playback and no unseen update, does not enter the queue.

### Manual Intent

Users can add a Saved title or exact episode from its context menu, detail
screen, or notification action. Manual additions become ordered pins. Pinned
items appear before automatic candidates and retain the user's order.

Removing an automatic candidate creates a dismissal for that title and episode.
The same episode remains suppressed across refreshes, but a newly discovered
episode is eligible again. Removing a manual pin removes the pin; the title may
still appear later as a qualifying automatic candidate. Unsaving a title
removes its candidates, pins, ordering records, and dismissals.

### Deterministic Ordering

The projector applies these rules in order:

1. Valid manual pins in user order.
2. Unseen new-episode candidates, newest detection first.
3. Incomplete Saved episodes, most recently played first.
4. Stable title ID as the final tie-breaker.

The one-candidate-per-title continuity rule is applied before global ordering.
Invalid, completed, unsaved, and dismissed candidates are removed before
presentation.

## Architecture

### `ReadyToWatchProjector`

A pure service that accepts Saved items, update snapshots, Played records, and
overrides and returns immutable `ReadyToWatchEntry` values. It owns candidate
selection, continuity, deduplication, and ordering. SwiftUI views do not
reimplement these rules.

### `ReadyToWatchOverridesStore`

A versioned local store for sparse user intent:

- `ReadyPin`: title ID, optional episode key, order token, and modification date.
- `ReadyDismissal`: title ID, episode key, and modification date.

The projected queue is never persisted as a snapshot. This prevents stale
entries after new episodes, completion changes, or provider corrections.

### Saved UI

`SavedItemsView` receives Played state and the Ready store in addition to its
existing dependencies. A focused `ReadyToWatchRail` renders the compact queue
using the existing media-card family. `ReadyToWatchView` renders the full
reorderable list. Both views issue commands to stores and projectors rather than
mutating arrays directly.

## Data Flow

1. `SavedUpdateMonitor` resolves the newest episode for every Saved serial title.
2. `SavedItemsStore` records successful baselines and unseen update state.
3. `PlayedItemsStore` supplies real media position and completion state.
4. `ReadyToWatchProjector` combines both stores with user overrides.
5. The Saved rail updates from the projection without another provider request.
6. Direct Play routes the item and episode key through the existing retained
   `PlaybackSessionController`.
7. Playback completion changes Played state and causes a new projection.

## Notifications

Register a notification category with two actions:

- `Play Now` opens the app and starts the exact episode in the notification.
- `Add to Up Next` records an ordered pin without starting playback.

A normal notification tap opens the title detail and episode list. Notification
payloads use the existing bounded `aiyifan://play` contract and add only a
validated action identifier. Duplicate title and episode updates do not create
duplicate queue records or notifications.

Background checks remain best effort because iOS controls their execution time.
Foreground activation performs the existing overdue catch-up check.

## Persistence And Optional Sync

Local Ready overrides use a versioned envelope in UserDefaults. Corrupt or
unsupported data falls back to an empty override set without changing Saved or
Played data.

When `Sync Library` is enabled and entitled, extend the existing iCloud payload
with optional Ready pins and dismissals. Decoding must accept the current V1
payload and default missing Ready fields to empty. Conflict resolution uses the
newest modification date per title and episode; equal timestamps use the stable
device-independent order token. Local behavior remains authoritative and fully
functional when iCloud is disabled or unavailable.

## Failure Handling

- A failed or partial provider check retains the last valid candidates and does
  not advance the global successful-check timestamp.
- Missing episode metadata hides the episode-specific action instead of playing
  an assumed first episode.
- Invalid deep links and stale notification actions are ignored safely and
  leave the Saved page available.
- Removing, completing, or unsaving an item recalculates the queue immediately.
- Reorder persistence failures leave the current in-memory order visible and
  expose a concise retryable message; they never damage Saved or Played data.
- Every asynchronous projection input is applied only if it still belongs to
  the current request generation.

## Accessibility And Layout

- Queue cards use at least 44-point actions and descriptive labels including
  title, episode, update state, and progress.
- Dynamic Type may wrap metadata but cannot resize the poster or move adjacent
  controls.
- The rail scrolls horizontally on compact and large iPhones; the full queue is
  a vertical list with native drag handles.
- Empty state text explains that new or unfinished Saved episodes appear
  automatically. It does not replace the existing Saved grid.

## Test Strategy

Write failing tests before each implementation slice.

### Unit Tests

- One candidate per title and incomplete-episode continuity.
- Manual pin precedence, stable reorder, removal, and new-episode reappearance.
- New-update ordering, Played ordering, completion removal, and deterministic
  tie-breaking.
- Unsaved cleanup, corrupt storage recovery, V1 migration, and iCloud conflicts.
- Notification category payloads, exact-episode routing, and stale actions.

### Integration Tests

- Saved update check to unseen episode, queue projection, notification, and Play.
- Played progress to Ready candidate, completion, and next-episode replacement.
- Local changes followed by optional iCloud merge on two simulated devices.
- Offline launch and partial provider failure with a previously valid queue.

### UI And Heavy-User Tests

- Ready rail above an unchanged Saved grid on compact and large simulators.
- Direct Play, See All, pin, reorder, remove, mark watched, and accessibility.
- Empty, one-item, long-title, large-library, and 100-entry override fixtures.
- Repeated save, unsave, update, play, complete, dismiss, relaunch, and sync
  sequences without duplicates or stale cards.
- Full regression after the phase stabilizes, with repository coverage at or
  above 80 percent.

## Documentation Requirement

The implementation is incomplete until `README.md` and `DEVELOPMENT.md` explain:

- Ready to Watch behavior and its Saved-only scope.
- The projector-versus-overrides architecture.
- Candidate continuity, ordering, dismissal, notification, and sync invariants.
- The tests and extension checklist required when adding future queue features.

## Non-Goals

- No release calendar or predicted release dates.
- No Home-page redesign or new primary tab.
- No automatic queue entries for unsaved titles.
- No hosted backend, social queue, or guaranteed real-time push notification.
- No video download or offline playback.

## Acceptance Criteria

- Saved shows a compact Ready to Watch rail above the unchanged Saved grid.
- The hybrid queue follows the exact candidate, continuity, pin, order, and
  dismissal rules in this specification.
- Notification actions Play the exact episode or pin it without playing.
- Provider failures retain the last valid queue and never erase library state.
- Existing Home, Search, Played, All, mini-player, and playback flows regress
  neither functionally nor visually.
- Local and optional iCloud migrations preserve existing Saved and Played data.
- Automated tests cover all queue behavior and the full stabilized regression
  suite passes with at least 80 percent coverage.
- README and developer guidance are updated in the same feature commit series.
