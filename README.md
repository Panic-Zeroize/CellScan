# CellScan

A native iOS (SwiftUI) drive-test app that records **real** cellular coverage while you
drive: GPS track, radio type (5G/LTE/3G), and a real throughput + latency probe — then
shows a map, a coverage summary, and exports a CSV.

Built from the CellScan design mock. This is a **working prototype** you can run on your
own iPhone with a free Apple ID — no paid developer account required.

---

## What's real vs. what the design faked

The original mock used hardcoded data. This app captures live data on device:

| Capability | Status | Notes |
|---|---|---|
| GPS track (lat/lng, accuracy, speed, heading) | ✅ Real | `CoreLocation`, updates in background while recording |
| Radio type (5G / LTE / 3G / 2G / none) | ✅ Real | `CoreTelephony` — the radio *type* is still readable natively |
| Carrier **name** | ✍️ Manual tag | iOS deprecated carrier name; you tag the SIM per pass |
| Download / upload / latency | ✅ Real | Periodic capped probe against Cloudflare's public speed endpoint |
| Map + colored coverage cells | ✅ Real | `MapKit`, colored by measured throughput (or radio type) |
| Saved passes (Home "Recent") | ✅ Real | Persisted to disk (JSON in the app's Documents dir) |
| CSV export | ✅ Real | **Save** writes a real `.csv` via the Files picker; **Copy** puts the table on the clipboard |
| Combine multiple scans | ✅ Real | Home multi-select → one layered map (per-carrier layers) + a combined CSV share |
| Tunable recording | ✅ Real | Settings screen: sample/speed-test intervals, min distance, cell merge radius, average vs worst-case, units |

Coverage cells **average** co-located samples by default (RAT tier, download, up, latency);
Worst-case is selectable in Settings. Everything stays on your device — the only network call
is the optional speed test to `speed.cloudflare.com`.

---

## Build & run on your iPhone (free provisioning)

**Requirements:** a Mac with **Xcode 16 or newer** (the project uses Xcode's synchronized
file groups), and an iPhone on iOS 17+.

1. Open **`CellScan.xcodeproj`** in Xcode.
2. Select the **CellScan** target → **Signing & Capabilities**.
   - Check **Automatically manage signing**.
   - **Team:** pick your personal Apple ID (add it under Xcode ▸ Settings ▸ Accounts if needed).
   - If the bundle id `com.cellscan.CellScan` is taken, change it to something unique like
     `com.yourname.CellScan`.
3. Plug in your iPhone, select it as the run destination, and press **⌘R**.
4. First launch on the phone: go to **Settings ▸ General ▸ VPN & Device Management**, tap your
   developer profile, and **Trust** it. Then reopen the app.
5. Grant **location** permission when prompted (choose *While Using*). The app uses
   When-In-Use location plus the `location` background mode, so it keeps recording with the
   screen off during an active pass (the blue status bar shows while it does).

> Free provisioning apps expire after **7 days** — just re-run from Xcode to refresh.

### If your Xcode is older than 16
Synchronized folder groups need Xcode 16+. Fallback (2 min): create a new **iOS App** project
(SwiftUI, named `CellScan`), delete its starter files, then drag everything inside the
`CellScan/` folder (all `.swift` files + `Assets.xcassets`) into it. Add these to the target's
build settings / Info: `NSLocationWhenInUseUsageDescription`, `UIBackgroundModes = location`,
and set the deployment target to iOS 17.

---

## Using it

- **Start New Pass** → tag your carrier, toggle the throughput test, **Start Recording**.
- Drive. The recording screen shows elapsed time, current radio type, a live signal
  sparkline, sample/cell counts, last GPS fix, speed, and latency.
- **Stop & Save** → coverage summary (cells, dead zones, breakdown).
- **View Map** to see your route with cells colored by real download speed (toggle to color
  by radio type). Tap any cell for its detail.
- **Export CSV** → **Save** (writes a `.csv` through the Files picker) or **Copy** (the whole
  table to the clipboard). Columns are ArcGIS-friendly.
- **Combine scans**: on Home, tap **Select** (or long-press a card), pick several passes, then
  **Combine** (one map with per-carrier layer toggles), **Export** (a combined CSV via the
  share sheet), or **Delete**.
- **Settings** (gear icon, top-right of Home): sample interval, speed-test interval, minimum
  distance per sample, cell merge radius, Average vs Worst-case merge, default speed-test state,
  and Imperial/Metric units — each with its default labeled.

## Notes & knobs

- Recording cadence (sample interval, speed-test interval, min distance, cell merge radius) is
  set in the **Settings** screen and read as a snapshot at the start of each pass in
  `RecordingEngine.start(...)`. The probe size is adaptive in `runThroughput()`.
- The throughput test uses cellular data (roughly ~1–3 GB/hour at highway speeds with the test
  on). Turn it off in New Pass for a GPS-only, near-zero-data pass.
- CSV columns: `timestamp,lat,lng,acc,spd,hdg,carrier,rat,down_mbps,up_mbps,lat_ms`.

## Project layout

```
CellScan.xcodeproj/          Xcode project (synchronized folder group)
CellScan/
  CellScanApp.swift          App entry
  Theme.swift                Colors + reusable card styles
  Models.swift               Carrier, RAT, CoverageTier, Sample, Cell, Pass (+CSV)
  Settings.swift             AppSettings model + SettingsStore (persisted)
  PassStore.swift            On-disk persistence of passes
  RecordingEngine.swift      Orchestrates GPS + radio + throughput sampling
  Services/
    LocationManager.swift    CoreLocation wrapper (background updates)
    RadioMonitor.swift       CoreTelephony radio-type reader
    ThroughputTester.swift   Real download/upload/latency probe
  Views/                     RootView, Home, NewPass, Recording, Summary, Map,
                             Export, Settings, Components, ShareSheet
  Assets.xcassets            Accent color + app icon slot
```
