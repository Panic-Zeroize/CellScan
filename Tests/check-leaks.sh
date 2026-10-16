#!/usr/bin/env bash
# Runs the core test suite under AddressSanitizer with LeakSanitizer ON and
# full-depth allocation stacks, then fails if any leaked allocation was made
# from CellScan code (the core module or its tests).
#
# The Linux Swift runtime (libswiftCore / Foundation / XCTest) leaks a few
# one-time process-lifetime allocations of its own; those stacks never pass
# through our binary and are reported but not counted.
set -uo pipefail

BUILD_PATH="${BUILD_PATH:-.build-asan}"
LOG="$(mktemp)"
export ASAN_OPTIONS="detect_leaks=1:fast_unwind_on_malloc=0:malloc_context_size=128:${ASAN_OPTIONS:-}"

swift test --build-path "$BUILD_PATH" --sanitize=address --skip Performance >"$LOG" 2>&1
status=$?

if grep -q "ERROR: AddressSanitizer: [^d]" "$LOG"; then
  grep -A30 "ERROR: AddressSanitizer" "$LOG" | head -60
  echo "FAIL: AddressSanitizer memory error"; exit 1
fi
if ! grep -qE "Executed [0-9]+ tests, with 0 failures" "$LOG"; then
  grep -E "error:|failed" "$LOG" | head -40
  echo "FAIL: tests did not pass"; exit 1
fi

# Split the leak report into one block per leak; count blocks touching our code.
ours=$(awk '
  /^(Direct|Indirect) leak of/ { if (blk != "" && blk ~ /CellScanCore|\/Tests\/|\/CellScan\//) n++; blk = $0; next }
  blk != "" { blk = blk "\n" $0 }
  END { if (blk ~ /CellScanCore|\/Tests\/|\/CellScan\//) n++; print n + 0 }' "$LOG")
total=$(grep -cE "^(Direct|Indirect) leak of" "$LOG")

echo "Tests: $(grep -oE "Executed [0-9]+ tests, with 0 failures" "$LOG" | tail -1)"
echo "LeakSanitizer: $total leak record(s) total, $ours from CellScan code (sanitizer exit $status)"
if [ "$ours" -ne 0 ]; then
  awk '/^(Direct|Indirect) leak of/{p=0} /^(Direct|Indirect) leak of/{blk=$0;next} {blk=blk"\n"$0} /CellScanCore|\/Tests\/|\/CellScan\//{print blk; blk=""}' "$LOG" | head -80
  echo "FAIL: memory leaked from CellScan code"; exit 1
fi
echo "PASS: no memory errors, no leaks from CellScan code"
exit 0
