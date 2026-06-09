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

- **Live train data**: fetched every 10s from a Cloudflare Worker at
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
