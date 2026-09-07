# Playback Correctness Implementation Plan

Date: 2026-09-07
Design: `docs/superpowers/specs/2026-09-07-playback-correctness-design.md`

## 1. Program-Only Playback

- Change resolver tests to require one full-program entry when the provider response also contains a front advertisement.
- Change Cast tests to require advertisement entries to be discarded.
- Update the response decoder and Cast plan builder to retain only non-advertisement program entries.
- Update the deterministic fixture to keep an advertisement in resolver input where useful, while asserting that playback consumers never queue it.

## 2. Truthful Played Progress

- Add a pure formatter test for fixed `Paused at mm:ss / mm:ss` labels.
- Add view-model tests proving periodic progress does not persist while paused or stalled and persists once when real playback stops.
- Track the previous effective playback state without estimating position from wall-clock time.
- Replace the relative Played timestamp with the fixed saved-position label.

## 3. Fullscreen Continuity

- Add lifecycle tests proving repeated starts are idempotent and explicit shutdown is repeatable.
- Move playback monitoring into a single view-model-owned task.
- Remove presentation-driven cleanup from `onDisappear`.
- Wrap Back and Website actions so they explicitly stop the player before navigation.
- Add a UI regression that invokes the native fullscreen control when available and verifies the native player remains active after returning inline.

## 4. Verification

- Run affected resolver, casting, player-model, and Played UI tests.
- Run the complete unit/UI suite with coverage.
- Run release build, static analysis, diff, secret, asset, and dependency checks.
- Commit, push to GitHub, build for John's iPhone, install, launch, and verify the process.
