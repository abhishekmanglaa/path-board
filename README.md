# path-board

A single-file PATH train departure board for Newport station, designed to run
fullscreen on an iPad as a 24/7 shelf display.

Everything lives in [`index.html`](index.html) — vanilla JS/CSS, no build step,
no framework, no npm dependencies.

## Run locally

```sh
python3 -m http.server 8000
```

Then open http://localhost:8000 in your browser.

To view it from an iPad on the same WiFi, find your Mac's LAN IP:

```sh
ipconfig getifaddr en0
```

Then on the iPad open `http://<that-ip>:8000`.

## Data dependencies

- **Live train data**: fetched every 60s from a Cloudflare Worker at
  https://path.abhishekmangla59.workers.dev (proxies the Port Authority PATH
  feed and adds CORS headers). Deployed separately — not part of this repo.
- **Weather**: fetched directly from [Open-Meteo](https://open-meteo.com/)
  (no API key, CORS-friendly).

## Deploying

This repo is connected to Cloudflare Pages. Every push to `main` auto-deploys —
no build command, no output directory, the single `index.html` is served from
the repo root.

```sh
git add -A
git commit -m "your change"
git push
```

Live within seconds at the Pages URL.

### iOS cache busting

If your iPad's Home Screen icon shows a stale version after a deploy, delete
the Home Screen icon and re-add it (Safari → Share → Add to Home Screen).

## Native iPhone app

Open `ios/PathHome.xcodeproj` in Xcode and run the **PathHome** scheme. The
project includes the app, Train Home / Train Rings widgets, and a user-started
Live Activity. `ios/project.yml` is the XcodeGen specification; the checked-in
project also preserves local Xcode configuration.

The app supports automatic or fixed stations, pinned stations, walking routes,
and leave-by advice with a configurable 1–3 minute station buffer (default 2).
Fixed-station departures work without location permission. Background station
following is optional and requires Always location access.

Native train data comes directly from the PANYNJ feed, with 30-second polling
while the app is active. Predictions under two minutes old are fresh; older
predictions are labeled and expire for recommendations after five minutes.
Offline results never provide leave-by advice. Timetable projections remain
distinct from live predictions. The Swift timetable in `Shared/NewportTimetable.swift`
is generated from the kiosk's `SCHED`; keep them in sync when schedules change.

The direct Hoboken–33rd Street line has a separate published timetable in
`Shared/HobokenTimetable.swift`, generated with
`ios/scripts/generate_hoboken_timetable.py` from PATH's public weekday/weekend
page models. It supplies later Hoboken departures at the five uptown Manhattan
stations even between live postings. The small departure widget uses JSQ/HOB
labels to fit three times per row, with a stable row order. Published service
hours are respected; estimates do not extend an extra overnight train into
invented overnight service.

Each widget has its own station, Newport directions, and departure/recommendation
settings through **Edit Widget**. iOS schedules widget network refreshes.
Live Activities show the selected train and countdown, update from the app,
and ask you to check the app when the prediction becomes stale. They do not use
a push server and cannot independently fetch new train predictions.

### Tests

Run the PathHome scheme's tests in Xcode, or select an installed simulator:

```sh
xcodebuild -project ios/PathHome.xcodeproj -scheme PathHome \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

The suite includes pure planning and freshness tests, cancellation and lifecycle
regressions, live PANYNJ / MapKit integration, and UI flows for station selection,
settings persistence, location permission, and Live Activity start/end. Live
integration tests require internet access. UI tests simulate a location near
Christopher Street and handle the When In Use permission prompt.

Set `TEST_RUNNER_RENDER_DIR=/tmp/pathhome-renders` before the command to also
render widget contact sheets, app states, large text, and Live Activity cards.
The optional render tests skip when that variable is absent.

See [architecture](docs/architecture.md) for the app's state and service boundaries,
and [iPhone installation](docs/iphone-install.md) for the Release install command
and free signing maintenance workflow.
