# Hoboken widget stability and combined-service accent

Release: **PATH Home 1.1.1 (3)**.

## Reported behavior and cause

Near Penn 2, the colored Train Home widget showed the Hoboken service
intermittently and only listed its posted train. The direct HOB–33 line does
not pass Newport, so Newport's timetable projections never supplied its next
departures. Once its last posted train left, its row vanished until the next
live posting. Away-station rows also changed order with the soonest train.

## Changes

- Added the independent published 33 Street–Hoboken weekday/Saturday/Sunday
  timetable, with the verified offsets for 23rd, 14th, 9th and Christopher Street.
- Both JSQ and HOB rows show up to three times, retaining estimates between live
  postings and labeling them with the existing faded treatment.
- Kept JSQ and HOB rows in fixed positions and shortened small-widget labels
  to make room for the later times.
- Preserved the last train/service boundaries. A live unscheduled overnight
  train remains visible but cannot shift the morning timetable into the night.
- Strengthened the combined JSQ–33 via-Hoboken accent from a 4-point stripe to
  a 7-point blue edge with a 56-point blue fade. The departure-count area keeps
  the orange fill. Normal single-line service and system tint behavior are unchanged.

## Source provenance

Official published page models fetched on November 3, 2026:

- https://www.panynj.gov/content/path/en/schedules-maps/weekday-schedules.model.json
- https://www.panynj.gov/content/path/en/schedules-maps/weekend-schedules.model.json

The generated Swift file records SHA-256 hashes of both source captures.
`ios/scripts/generate_hoboken_timetable.py` reads only current top-level
accordions, excludes archived child pages, checks every station offset, and
verifies unique sorted departures. Extracted counts: 110 weekday trains and
67 trains on each weekend day. Regeneration matched the checked-in Swift table
byte for byte.

## Verification

- Twelve new schedule regressions cover live plus estimated trains, empty-feed
  continuity, expiration within an existing timeline, fixed row order, all five
  Manhattan stations, weekend service, uneven gaps, end of service, station
  isolation, unsorted live trains, and an unscheduled post-midnight departure.
- Complete iOS 27.2 suite before the final paint adjustment: 86 app/model/render
  tests and 3 end-to-end UI flows passed, with no failures.
- iOS 18.2: 86 tests, 2 optional render skips, no failures.
- Both Penn 2 scenarios were rendered in light/dark/tinted mode at small and
  medium sizes, including a missing Hoboken live posting. Each colored row
  visibly fits three times at the smallest tested size.
- Final accent render/model run: 86 tests passed, no failures or skips; light/dark/tinted combined-service rows inspected.
- Final signed iPhone build, static analysis and deep signature verification passed.
- Full UI flows passed before the paint-only adjustment; that final adjustment changes only the decorative row background.

Installed on the paired iPhone 13 Pro: device query confirms **1.1.1 (3)**, and remote launch succeeded.

Evidence directory: `/tmp/path-home-hoboken/`. Installation, installed-version and launch receipts are saved there as JSON.

## Practical limits

Timetable departures are estimates; live postings take priority. The Hoboken
row may disappear after published service ends, which is expected. iOS still
controls widget reload timing. The real work-to-station trip has not been
field-tested; the feed transitions were reproduced with deterministic tests.
