# Energy audit and iPhone signing maintenance — 1.1.2 (4)

## Changes

- Replaced the per-second dashboard timer with a native SwiftUI timeline schedule. It redraws at departure-minute, leave-by, walk-validity, and prediction-freshness boundaries. The iterator continues through long outages without retaining an unbounded list. Covered or inactive dashboards do not run this schedule.
- Foreground refresh stays at 30 seconds normally and slows to 60 seconds in Low Power Mode. Failures back off to 120 seconds. A single automatic gate covers both the poller and location callbacks. Manual refresh bypasses the gate; only a newly fetched plan clears failures.
- Requested foreground location accuracy is 100 metres with a 100-metre distance filter and automatic pauses. Standard location updates and the poller still stop when the scene is inactive. Optional significant-movement/region monitoring remains off by default.
- Routine widget reload requests coalesce to at most once per minute within the app process; explicit user actions and station changes bypass the gate. WidgetKit still controls actual refresh delivery.
- iPhone installations now use an optimized Release configuration. The install command runs static analysis, verifies the signature, checks app and widget signing expiry, and records successful installation only after device confirmation. Signed products live outside Desktop/iCloud folders to avoid Finder metadata invalidating their signatures.
- Architecture and maintenance instructions are in `docs/architecture.md` and `docs/iphone-install.md`.

## Verification

- Regression tests were initially red because the energy policy and schedule types were absent.
- Final iOS 27.2 run: **95 model/render tests and 3 UI tests passed**. Includes timeline boundaries, long outages, Low Power Mode, shared retry gating, cache reuse during failure, manual refresh, dynamic polling cancellation, all prior planning regressions, and rendering at iPhone/accessibility sizes.
- iOS 18.2 compatibility: **95 tests, zero failures, 2 optional render exports skipped** because no export directory was configured. The full render suite passed in the primary run. An earlier compatibility attempt was interrupted when its extra simulator was stopped to reduce concurrent build contention; the subsequent isolated run passed.
- Installer tests: **3 passed**, covering the renewal margin, an earlier widget expiry, and missing extension detection.
- Signed Release **build and static analysis passed**, with no compiler/analyzer warnings. Deep strict signature verification passed.
- iPhone device query confirms **1.1.2 (4)** installed. Launch succeeded. The script's `maintain` command correctly skipped a rebuild while the recorded signing expiry was more than 48 hours away.
- Earliest embedded app/widget signing expiry at delivery: **November 9, 2026, 4:19:59 p.m. Eastern**. Rebuilding/installing did not renew that already-valid profile; the tool reports its actual expiry.
- Daily midnight local-time signing check created and confirmed active: `keep-path-home-signed-on-iphone`. Near expiry it runs model tests before attempting maintenance, and reports signing or connectivity problems. It never deletes profiles/certificates or changes app identity.
- Read-only code review found a location-callback backoff bypass; that issue was fixed and covered by regression tests. Follow-up review found no remaining material issues. `git diff --check` passed.

## Evidence and limits

Primary results: `/tmp/path-home-energy/ReviewedTests.xcresult`, `CompatibilityRetry.xcresult`, simulator renders, Release build/install logs, and device query JSON. Local installation history is in ignored `ios/.device-build/last-install.json`.

This is a code-level energy improvement, not a measured battery-percentage claim. Power Profiler could not attach by process name or by the process ID returned by CoreDevice; Instruments listed the network-paired iPhone offline even though CoreDevice installed and launched the app. No valid physical power capture was collected. A physical-device power capture and a representative commute/day of use are still needed to quantify drain. Keep the iPhone connected to the Mac by cable and unlocked with the app open when completing that measurement.

The scheduled task needs the Mac on, Codex running, the local project available, and a reachable/trusted iPhone for installation. Free Personal Team signing may require an interactive Xcode account/signing refresh; a schedule cannot bypass that requirement.
