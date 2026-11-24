# PATH Home architecture

This app uses native SwiftUI and a small, unidirectional data flow:

1. SwiftUI views render immutable plans and send user actions to main-actor controllers.
2. `LocationMonitor` owns app state and coordinates location, refresh lifecycle, and persistence. `CommuteActivityController` owns ActivityKit lifecycle.
3. `Planner` combines the feed, published schedules, and walking estimates. Its injected dependencies allow deterministic tests without network or GPS.
4. Shared value models and pure policies define departure rows, recommendations, freshness, refresh delays, and display update dates. App and widget use the same rules.
5. `SharedStore` persists settings and station-specific plans in the existing App Group. Widget providers use their own configuration without changing app settings.

Keep network and location work out of view bodies. Keep new calculations in small value types or functions with explicit inputs. UI-owned state stays in views; shared side effects stay in controllers. Introduce protocols or extra layers when a real second implementation or testing boundary needs them.

`LatestPlanRequest` combines cancellation with a generation check so obsolete requests cannot overwrite a newer station. `ForegroundPoller` owns one cancellable loop, stopped when the scene is inactive. `ForegroundRefreshPolicy` controls delay, while `WidgetReloadGate` coalesces routine reload requests independently of saving data. `DepartureTimelineSchedule` updates displayed values at their boundaries without a per-second dashboard timer.

Background location following is optional and off by default. Its significant movement callbacks only cache location for widgets. The app stops standard location updates and trip planning outside the foreground. Scheduled widget refreshes reuse available location and ask for train data every 10–15 minutes. iOS controls the actual timing. The widget refresh button can request a fresh fix if needed.

Before delivery, run model and rendering tests, the UI flows, static analysis, and a signed Release build. Measure energy on a physical device; passing tests or fewer scheduled redraws does not establish a battery percentage.
