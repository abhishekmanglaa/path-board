# Commute Experience Implementation Plan

> **For agentic workers:** Implement inline with superpowers:executing-plans and test-driven-development. The user approved all eight recommendations and device installation on 2026-11-03.

**Goal:** Make PATH Home answer when to leave, with honest freshness, reliable refresh, station control, configurable widgets, progressive permissions, and a local Live Activity; test and install on the paired iPhone.

**Architecture:** Keep SwiftUI and the existing shared Plan/Planner model. Add pure recommendation/freshness policy, station-scoped caching, injected planning dependencies, a cancellable foreground refresh controller, App Intent widget configuration, and ActivityKit. Keep the kiosk and Scriptable implementation unchanged.

**Tech Stack:** Swift 5, iOS 17+, SwiftUI, MapKit, CoreLocation, WidgetKit, AppIntents, ActivityKit, XCTest, Xcode 27.2.

**Spec:** The eight recommendations in this chat, approved by the user with “Can you do all this … thorough testing … push the app to my iPhone”.

## Global Constraints

- Preserve existing signing team, bundle IDs, App Group, Xcode scheme changes, and stored plans.
- Default station buffer: 2 minutes, configurable from 1 to 3 minutes.
- Fresh predictions: under 2 minutes; aging: 2–5 minutes; expired: 5+ minutes. Offline recommendations require a successful refresh. Never label old predictions live.
- Foreground fetch every 30 seconds while active; cancel obsolete work and ignore out-of-order results.
- Fixed stations work without location; walking-based advice requires a recent, nearby origin.
- Widget settings are per instance: automatic/fixed station, Newport directions, departures/recommendation. Keep board and rings widget kinds.
- Live Activities are user-started, local-only, with explicit prediction time/stale date and end controls. No server or push entitlement is added.
- Do not push repository changes to main or run the provisioning-renewal script.

## Review Focus

- Fixed-station cache must never leak to automatic selection or another station.
- Missing/old/inaccurate location allows departure browsing but suppresses leave-by guidance.
- Expired feed predictions cannot appear live even if countdowns continue.
- A canceled/slow response cannot overwrite a newer station or request.
- No-permission, denied-permission, offline, empty and departed-train states must remain usable.

### Task 1: Trust and recommendation model

**Files:** Shared/Commute.swift, Shared/Planner.swift, Shared/SharedStore.swift, Tests/CommuteTests.swift.
**Interfaces:** `PlanFreshness`, `CommuteRecommendation.make(plan:now:bufferMinutes:destinations:hasWalk:offline:)`; station-scoped saved plans and fixed-station Planner parameter.
- [x] Write and run tests for freshness thresholds, catchability boundary, buffer, hidden destinations, expired/offline plans, missing walk, override/reuse isolation, old saved plans.
- [x] Implement the pure policies and dependency-injected planning, then run tests.

### Task 2: Reliable app state and foreground refresh

**Files:** App/LocationMonitor.swift, App/CommuteActivityController.swift, Tests/RefreshTests.swift.
**Interfaces:** async refresh; selected station; walk availability; polling tied to scene phase; latest-request controller.
- [x] Test cancellation/out-of-order responses and station switches, polling lifecycle, error recovery.
- [x] Implement request generation/cancellation, 30-second polling, fixed-station mode, opt-in background following; run tests.

### Task 3: App experience and onboarding

**Files:** App/ContentView.swift, App/CommuteViews.swift, App/SettingsView.swift.
- [x] Build a prominent recommendation, destination-aware next trains, freshness label, station picker with pins, alternatives, directions, and accessible Dynamic Type.
- [x] Move settings and widget gallery off the main board; request permissions in response to feature selection.
- [x] Render and verify ordinary/large text, small screens, empty/offline/location states.

### Task 4: Configurable, honest widgets

**Files:** Shared/WidgetConfiguration.swift, Shared/BoardViews.swift, Shared/GlassViews.swift, Shared/TimelineBuilder.swift, Shared/RefreshIntent.swift, Widget/PathHomeWidget.swift.
- [x] Test widget selection, cache isolation, freshness boundary redraws and recommendation changes.
- [x] Implement AppIntentConfiguration with per-instance station/directions/display options; retain kinds; make refresh target the current widget's station.
- [x] Render all widget families and modes; inspect images.

### Task 5: Live Activity

**Files:** Shared/CommuteActivity.swift, App/CommuteActivityController.swift, Widget/CommuteLiveActivity.swift, App/Info.plist, project.yml, project.pbxproj.
- [x] Test activity state creation, stale deadline, train matching and departure expiration.
- [x] Implement lock-screen/Dynamic Island activity and in-app start/end, update while active, fail clearly when unavailable.
- [x] Build both targets and inspect rendered activity UI.

### Task 6: Whole-app verification and iPhone install

- [x] Run complete simulator suite including live service integration; record failures separately from deterministic tests.
- [x] Render contact sheets and app states in light/dark/tinted/large text; review images.
- [x] Build/analyze with warnings reviewed; review final diff.
- [x] Signed device build with existing team/profiles, install using devicectl, and verify installed version. Launch attempted; iOS denied it because the phone is locked. User can open PATH Home after unlocking.

## Execution ledger

- Initial checkout: main, two existing modified Xcode files and untracked scriptable folder. Saved original Xcode diff to /tmp/path-home-work/original-xcode.patch. Using a feature branch in place so device signing and local project configuration stay available.
- Device discovered: Abhishek’s iPhone, iPhone 13 Pro, UDID 00008110-00184521013A801E, paired/available.

- Implementation complete on codex/commute-experience. All changes remain uncommitted so the user's original Xcode edits are not silently included in a commit. No repository push or kiosk deployment performed.
- Baseline: 42 tests, 1 optional render skip, zero failures.
- Final iOS 27.2: 74 app/model/integration/render tests plus 3 UI tests, all passed; /tmp/path-home-work/DeliveryTests.xcresult.
- iOS 18.2 compatibility: 74 tests, 2 optional render skips, zero failures; /tmp/path-home-work/DeliveryCompatibility18.xcresult.
- Render review: small/large phones, accessibility text, light/dark/tinted widgets, offline/expired/location states, fresh/stale Live Activities. Live Activity height <=130pt reserves space within Apple's 160pt presentation limit.
- Independent review: fixed shared End intent target membership, initial refresh cancellation, late location callbacks, activity expiry without a reliable walk, aging accessory advice, and single-train ring states.
- Additional regressions: reject nonfinite feed counts; real widget snapshots never invent live trains; stale/unknown-walk plans never receive urgent Smart Stack relevance.
- Signed device build and static analysis passed, no device build warnings; deep signature verification passed. App/extension version 1.1 (2).
- Device install succeeded. Device query confirms PATH Home 1.1 (build 2). Launch attempt returned the explicit iOS Locked error; no physical first-launch or trip/geofence test is claimed.
