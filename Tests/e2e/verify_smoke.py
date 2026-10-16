#!/usr/bin/env python3
"""Verifies Documents/smoke-result.json + smoke.csv written by the app's
DEBUG-only smoke test (CellScan/SmokeTest.swift). Exits non-zero on failure."""
import csv
import json
import sys

docs = sys.argv[1]
r = json.load(open(f"{docs}/smoke-result.json"))
failures = []

def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)

print(json.dumps({k: v for k, v in r.items() if k != "ticks"}, indent=2))
states = [t["appState"] for t in r["ticks"]]
print("timeline:", "".join("B" if s == "background" else "F" for s in states))

check(r.get("error") is None, f"no error ({r.get('error')})")
check(r["locationAccess"] == "granted", "location permission granted")
check(r["samples"] >= r["requestedSeconds"] * 0.5, f"recorded samples ({r['samples']}) at ~1/s")
check(r["foregroundSamples"] >= 5, f"samples while in foreground ({r['foregroundSamples']})")
check("background" in states, "app was backgrounded during the drive")
check(r["backgroundSamples"] >= 10, f"recording continued in background ({r['backgroundSamples']} samples)")
check(r["distanceMiles"] > 0.05, f"distance accumulated from the simulated route ({r['distanceMiles']:.2f} mi)")
check(r["cells"] >= 2, f"coverage cells produced ({r['cells']})")
check(r["samplesWithThroughput"] > 0, f"live throughput probe results attached ({r['samplesWithThroughput']} samples)")
check(r["savedPassFound"], "pass persisted to passes.json and reloadable")
check(r["checkpointRemoved"], "crash-recovery checkpoint cleared after save")
check(r["csvRows"] == r["samples"], f"CSV has one row per sample ({r['csvRows']})")

rows = list(csv.reader(open(f"{docs}/smoke.csv")))
header, body = rows[0], rows[1:]
check(header == ["timestamp", "lat", "lng", "acc", "spd", "hdg", "carrier", "rat",
                 "down_mbps", "up_mbps", "lat_ms"], "CSV header")
check(all(len(row) == 11 for row in body), "every CSV row has 11 columns")
lats = [float(row[1]) for row in body]
check(min(lats) > 37 and max(lats) < 38 and max(lats) - min(lats) > 0.001,
      "CSV coordinates follow the simulated route")
check(all(row[6] == "T-Mobile" for row in body), "carrier stamped on every row")

passes = json.load(open(f"{docs}/passes.json"))
check(len(passes) >= 1, f"passes.json readable ({len(passes)} pass)")

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nAll end-to-end checks passed")
