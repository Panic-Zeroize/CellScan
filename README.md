# CellScan

A native iOS (SwiftUI) drive-test app that records **real** cellular coverage while you
drive: GPS track, radio type (5G/LTE/3G), and a real throughput + latency probe — then
shows a map, a coverage summary, and exports a CSV.

Built from the CellScan design mock. You can run it on your own iPhone with a free Apple ID —
no paid developer account required.

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
| Saved passes | ✅ Real | Persisted to disk (JSON in the app's Documents dir, visible in the Files app); last 7 days + "Earlier" |
| Crash-safe recording | ✅ Real | The live pass is checkpointed every ~10 samples / 30 s; a crash or force-quit recovers it on next launch |
| CSV export | ✅ Real | **Save** writes a real `.csv` via the Files picker; **Copy** puts the table on the clipboard |
| Combine multiple scans | ✅ Real | Home multi-select → merge into one new scan (originals deleted). Every row keeps its own carrier, so mixed-carrier merges still map per carrier |
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

> `UIBackgroundModes`, `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` live in
> `CellScan-Info.plist` (merged with Xcode's generated Info.plist), because Xcode's
> `INFOPLIST_KEY_*` build settings can't express background modes.

---

## Using it

- **Start New Pass** → tag your carrier, toggle the throughput test, **Start Recording**.
- Drive. The recording screen shows elapsed time, current radio type, a live signal
  sparkline, sample/cell counts, last GPS fix, speed, download and latency — plus a warning
  if location access is off or GPS is still acquiring a fix.
- **Stop** → choose **Save Pass**, **Discard Pass**, or **Keep Recording**. Saving opens the
  coverage summary (cells, dead zones, breakdown).
- **View Map** to see your route with cells colored by real download speed (toggle to color
  by radio type). Tap any cell for its detail.
- **Export CSV** → **Save** (writes a `.csv` through the Files picker) or **Copy** (the whole
  table to the clipboard). Columns are ArcGIS-friendly.
- Tapping a pass opens its **Summary** (View Map / Export CSV / Delete / Done).
- **Select scans**: on Home, tap **Select** (or long-press a card), pick several passes, then
  **Combine** (merges them into one new scan and deletes the originals), **Export** (Save/Copy
  a combined CSV), or **Delete**.
- **Settings** (gear icon, top-right of Home): sample interval, speed-test interval, minimum
  distance per sample, cell merge radius, Average vs Worst-case merge, default speed-test state,
  and Imperial/Metric units — each with its default labeled.

## Reliability & error handling

- **No silent data loss.** If `passes.json` is damaged, the readable passes still load, the
  original file is copied aside (`passes.corrupt-<time>.json` / `passes.partial-<time>.json`,
  visible in Files ▸ On My iPhone ▸ CellScan) and the app tells you — it never overwrites it.
  Unknown values written by a future version (e.g. a new radio type) decode instead of failing.
- **Saves are atomic and off the main thread.** Every write goes through one serial queue, so a
  checkpoint can never land after the finished pass was saved. A failed save shows an alert.
- **Recording survives crashes.** The checkpoint is cleared only after the finished pass is
  safely on disk; if the app dies mid-drive, the pass is recovered on next launch.
- **Bad sensor data can't poison a pass.** Non-finite / negative readings are sanitized,
  invalid coordinates are skipped, stale GPS fixes (tunnels, garages) aren't reused, and
  in-flight speed probes are cancelled when you stop.
- **Permissions.** If location access is off, New Pass explains why and links straight to
  Settings, and recording can't start; nothing-recorded passes are reported, not silently dropped.

## Testing

The platform-independent core (`CellScan/Core`: model, cell merging, CSV export, persistence and
crash-recovery) is a Swift package you can test without a simulator, on macOS or Linux:

```sh
swift test                                   # 58 tests incl. 100k-sample stress cases
swift test --sanitize=thread --skip Performance
```

On Linux without a toolchain: `docker run --rm -v "$PWD":/src -w /src swift:6.1-noble swift test`.
CI runs the suite (plus a warnings-as-errors and Swift 6 strict-concurrency build) on every push —
see `.github/workflows/core-tests.yml`.

## Notes & knobs

- Recording cadence (sample interval, speed-test interval, min distance, cell merge radius) is
  set in the **Settings** screen and read as a snapshot at the start of each pass in
  `RecordingEngine.start(...)`. The probe size is adaptive in `runThroughput()`.
- The throughput test uses cellular data (roughly ~1–3 GB/hour at highway speeds with the test
  on). Turn it off in New Pass for a GPS-only, near-zero-data pass.
- CSV columns: `timestamp,lat,lng,acc,spd,hdg,carrier,rat,down_mbps,up_mbps,lat_ms` — one
  header, one row per sample, UTC ISO-8601 timestamps, RFC 4180 quoting, rows time-sorted when
  several passes are exported together.

## Project layout

```
CellScan.xcodeproj/          Xcode project (synchronized folder group)
CellScan-Info.plist          Background mode + Files-app access (merged into Info.plist)
Package.swift                Test harness for CellScan/Core (`swift test`)
CellScan/
  CellScanApp.swift          App entry
  Core/                      Foundation-only, unit-tested
    Models.swift             Carrier, RAT, CoverageTier, Sample, Cell, Pass, cell merging
    CSV.swift                CSV export + file naming
    AppSettings.swift        Settings model (forward-compatible decoding, clamping)
    PassArchive.swift        Disk persistence, corruption backups, crash checkpoint
  PassStore.swift            Observable pass list, background saves, recovery on launch
  SettingsStore.swift        Settings persisted in UserDefaults
  RecordingEngine.swift      Orchestrates GPS + radio + throughput sampling, checkpoints
  Theme.swift                Colors + reusable card styles
  Services/
    LocationManager.swift    CoreLocation wrapper (permission state, background updates)
    RadioMonitor.swift       CoreTelephony radio-type reader
    ThroughputTester.swift   Real, cancellable download/upload/latency probe
  Views/                     RootView, Home, NewPass, Recording, Summary, Map,
                             Export, Settings, Components, ModelUI (model colors)
  Assets.xcassets            Accent color + app icon slot
Tests/CellScanCoreTests/     Model, merge, CSV, combine, archive and settings tests
```
