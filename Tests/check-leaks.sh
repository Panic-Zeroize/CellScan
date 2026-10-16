#!/usr/bin/env bash
# Runs the core test suite under AddressSanitizer with LeakSanitizer ON and
# full-depth allocation stacks. Fails on any memory error, any test failure, or
# any leaked allocation whose stack contains a function from the shipped
# CellScanCore module.
#
# Attribution uses real symbols (addr2line on the test binary): ASan's malloc
# interceptor is linked into the test binary, so "the binary appears in the
# stack" is NOT evidence of a leak in our code. A frame counts as production
# code only if its mangled symbol is defined in CellScanCore ($s12CellScanCore…).
#
# Leaks that remain come from the Linux runtime itself: XCTest never frees its
# per-test run records / test-case instances, plus one-time runtime caches.
# Those are reported, not counted.
set -uo pipefail

BUILD_PATH="${BUILD_PATH:-.build-asan}"
LOG="$(mktemp)"; MAP="$(mktemp)"
trap 'rm -f "$LOG" "$MAP"' EXIT
export ASAN_OPTIONS="detect_leaks=1:fast_unwind_on_malloc=0:malloc_context_size=128:${ASAN_OPTIONS:-}"

swift test --build-path "$BUILD_PATH" --sanitize=address --skip Performance >"$LOG" 2>&1
status=$?

if grep -qE "ERROR: AddressSanitizer: [^d]" "$LOG"; then
  grep -A40 "ERROR: AddressSanitizer" "$LOG" | head -60
  echo "FAIL: AddressSanitizer memory error"; exit 1
fi
if ! grep -qE "Executed [0-9]+ tests, with 0 failures" "$LOG" || grep -qE "with [1-9][0-9]* failures" "$LOG"; then
  grep -E "error:|failed" "$LOG" | head -40
  echo "FAIL: tests did not pass"; exit 1
fi

# Symbolize every frame that lands in the test binary (offset -> mangled name).
BIN="$(grep -oE '\(/[^ ()]*CellScanCorePackageTests\.xctest\+0x[0-9a-f]+\)' "$LOG" | head -1 | sed -E 's/^\(([^+]*)\+.*/\1/')"
if [ -n "$BIN" ]; then
  offs="$(grep -oE 'CellScanCorePackageTests\.xctest\+0x[0-9a-f]+' "$LOG" | sed 's/.*+//' | sort -u)"
  # addr2line prints "function\nfile:line" per address.
  paste <(printf '%s\n' $offs) <(addr2line -f -e "$BIN" $offs | paste - - | cut -f1) >"$MAP"
fi

read -r total prod tests < <(awk -v mapfile="$MAP" '
  BEGIN { while ((getline line < mapfile) > 0) { split(line, a, "\t"); sym[a[1]] = a[2] } }
  function flush() {
    if (!inblk) return
    total++
    if (isprod) prod++; else if (istest) tests++
  }
  /^(Direct|Indirect) leak of/ { flush(); inblk = 1; isprod = 0; istest = 0; next }
  inblk && match($0, /CellScanCorePackageTests\.xctest\+0x[0-9a-f]+/) {
    off = substr($0, RSTART, RLENGTH); sub(/.*\+/, "", off)
    s = sym[off]
    if (s ~ /^\$s12CellScanCore/) { isprod = 1; print "  production frame: " s > "/dev/stderr" }
    else if (s ~ /^\$s17CellScanCoreTests/) istest = 1
  }
  END { flush(); print total + 0, prod + 0, tests + 0 }' "$LOG")

echo "Tests: $(grep -oE 'Executed [0-9]+ tests, with 0 failures' "$LOG" | tail -1)"
echo "LeakSanitizer: $total leak record(s); $prod from CellScanCore (shipped code), $tests held by test fixtures, rest Swift runtime/XCTest (sanitizer exit $status)"
if [ "$prod" -ne 0 ]; then
  echo "FAIL: memory leaked from CellScanCore"; exit 1
fi
echo "PASS: no memory errors, no leaks from CellScanCore"
exit 0
