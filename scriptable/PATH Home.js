// PATH Home — Scriptable widget (iOS).
// Nearest PATH station, walking time to it, and the next train you can
// actually catch that stops at Newport. Tap opens Apple Maps walking directions.
//
// Setup: install Scriptable, paste this as a new script named "PATH Home",
// add a Scriptable widget (small or medium), choose this script. Allow
// location "While Using the App or Widgets" when asked.

const HOME = "NEW"; // Newport

// Feed station code → name, coords, and which headsigns stop at Newport.
// Headsigns come from the PANYNJ feed. Trains via Hoboken overnight carry
// "Journal Square" in their headsign, so /journal/ still matches them.
const STATIONS = {
  NWK: { name: "Newark",          lat: 40.7347, lon: -74.1644, home: /world trade/i, note: "change at Journal Sq" },
  HAR: { name: "Harrison",        lat: 40.7393, lon: -74.1558, home: /world trade/i, note: "change at Journal Sq" },
  JSQ: { name: "Journal Square",  lat: 40.7331, lon: -74.0628, home: /33rd/i },
  GRV: { name: "Grove Street",    lat: 40.7197, lon: -74.0429, home: /33rd/i },
  NEW: { name: "Newport",         lat: 40.7270, lon: -74.0337, home: null },
  EXP: { name: "Exchange Place",  lat: 40.7163, lon: -74.0328, home: /hoboken/i },
  HOB: { name: "Hoboken",         lat: 40.7353, lon: -74.0291, home: /world trade|journal/i },
  WTC: { name: "World Trade Ctr", lat: 40.7126, lon: -74.0099, home: /hoboken/i },
  CHR: { name: "Christopher St",  lat: 40.7330, lon: -74.0071, home: /journal/i },
  "09S": { name: "9th Street",    lat: 40.7342, lon: -73.9989, home: /journal/i },
  "14S": { name: "14th Street",   lat: 40.7374, lon: -73.9968, home: /journal/i },
  "23S": { name: "23rd Street",   lat: 40.7429, lon: -73.9929, home: /journal/i },
  "33S": { name: "33rd Street",   lat: 40.7488, lon: -73.9884, home: /journal/i },
};

const C = { bg: "#0a0b0c", ink: "#eceae6", dim: "#8a8f8f", ghost: "#5a5f62", green: "#7ed320", amber: "#E8913C" };

function km(a, b) {
  const R = 6371, r = Math.PI / 180;
  const dLat = (b.lat - a.lat) * r, dLon = (b.lon - a.lon) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

async function getJSON(url, timeout = 10) {
  const req = new Request(url);
  req.timeoutInterval = timeout;
  return req.loadJSON();
}

// Real walking time from OSM foot routing; falls back to a straight-line
// estimate (×1.3 for street grid, 80 m/min) if the router is unreachable.
async function walkMinutes(from, to) {
  try {
    const url = `https://routing.openstreetmap.de/routed-foot/route/v1/driving/${from.lon},${from.lat};${to.lon},${to.lat}?overview=false`;
    const j = await getJSON(url, 8);
    if (j.code === "Ok") return Math.max(1, Math.round(j.routes[0].duration / 60));
  } catch (e) {}
  return Math.max(1, Math.round(km(from, to) * 1.3 * 1000 / 80));
}

async function load() {
  Location.setAccuracyToHundredMeters();
  const here = await Location.current();

  // Two closest by straight line, then pick whichever is actually the shorter walk
  // (a river or rail yard can make the "closest" one the longer walk).
  const near = Object.entries(STATIONS)
    .map(([code, s]) => ({ code, ...s, km: km(here, s) }))
    .sort((a, b) => a.km - b.km)
    .slice(0, 2);
  for (const s of near) s.walk = await walkMinutes(here, s);
  near.sort((a, b) => a.walk - b.walk);
  const st = near[0];

  if (st.code === HOME) return { st, home: true };

  const feed = await getJSON("https://www.panynj.gov/bin/portauthority/ridepath.json");
  const res = (feed.results || []).find(r => r.consideredStation === st.code);
  const trains = [];
  for (const dest of (res && res.destinations) || [])
    for (const m of dest.messages || []) {
      if (!st.home.test(m.headSign || "")) continue;
      const mins = Math.round(parseInt(m.secondsToArrival, 10) / 60);
      if (!isNaN(mins)) trains.push({ mins, sign: m.headSign, color: "#" + (m.lineColor || "").split(",")[0] });
    }
  trains.sort((a, b) => a.mins - b.mins);

  // Only trains you can reach on foot; "leave in" is the slack you have.
  const catchable = trains.filter(t => t.mins >= st.walk);
  return { st, trains: catchable, missed: trains.length - catchable.length };
}

function text(stack, str, size, color, weight = "regular") {
  const t = stack.addText(str);
  t.font = weight === "bold" ? Font.boldSystemFont(size) : weight === "mono" ? Font.mediumMonospacedSystemFont(size) : Font.systemFont(size);
  t.textColor = new Color(color);
  t.lineLimit = 1;
  t.minimumScaleFactor = 0.6;
  return t;
}

function build(data, error) {
  const w = new ListWidget();
  w.backgroundColor = new Color(C.bg);
  w.setPadding(14, 14, 14, 14);
  w.refreshAfterDate = new Date(Date.now() + 2 * 60 * 1000);

  if (error) {
    text(w, "PATH HOME", 11, C.ghost, "mono");
    w.addSpacer(6);
    text(w, error, 13, C.amber);
    return w;
  }

  const { st } = data;
  w.url = `http://maps.apple.com/?daddr=${st.lat},${st.lon}&dirflg=w`;

  text(w, st.name.toUpperCase(), 12, C.green, "bold");
  text(w, `${st.walk} min walk`, 11, C.dim, "mono");
  w.addSpacer();

  if (data.home) {
    text(w, "You're at Newport", 15, C.ink, "bold");
    return w;
  }

  const [next, after] = data.trains;
  if (!next) {
    text(w, data.missed ? "Can't make the next train" : "No train home listed", 13, C.amber);
    if (st.note) text(w, st.note, 10, C.ghost);
    return w;
  }

  text(w, "NEXT HOME", 9, C.ghost, "mono");
  const row = w.addStack();
  row.bottomAlignContent();
  text(row, String(next.mins), 34, C.ink, "bold");
  row.addSpacer(3);
  text(row, "min", 12, C.dim);
  const slack = next.mins - st.walk;
  text(w, slack <= 1 ? "leave now" : `leave in ${slack} min`, 12, slack <= 2 ? C.amber : C.green, "bold");
  text(w, after ? `then ${after.mins} · ${next.sign}` : next.sign, 10, C.ghost);
  if (st.note) text(w, st.note, 10, C.ghost);
  return w;
}

let widget;
try {
  widget = build(await load());
} catch (e) {
  widget = build(null, String(e.message || e).includes("location") ? "Location unavailable" : "Couldn't load trains");
}

if (config.runsInWidget) Script.setWidget(widget);
else await widget.presentSmall();
Script.complete();
