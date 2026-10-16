#!/usr/bin/env bash
# Runs the full core test suite under AddressSanitizer with LeakSanitizer ON and
# requires a clean process exit (status 0): no memory errors, no test failures,
# no leaks.
#
# One suppression is used (Tests/lsan-xctest.supp): a 32-byte weak-reference
# side table leaked by Linux XCTest's own XCTWaiter. XCTest's other objects are
# kept reachable by CoreTestCase (see Tests/CellScanCoreTests/CoreTestCase.swift).
# Planting a leak in CellScanCore makes this script fail — verified.
#
# LeakSanitizer symbolizes with addr2line (the Swift Linux image has no
# llvm-symbolizer), so the suppression pattern is a mangled-symbol substring.
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_PATH="${BUILD_PATH:-.build-asan}"
export ASAN_OPTIONS="detect_leaks=1:external_symbolizer_path=$(command -v addr2line)${ASAN_OPTIONS:+:$ASAN_OPTIONS}"
export LSAN_OPTIONS="suppressions=$PWD/Tests/lsan-xctest.supp:print_suppressions=1${LSAN_OPTIONS:+:$LSAN_OPTIONS}"

swift test --build-path "$BUILD_PATH" --sanitize=address --skip Performance 2>&1 \
  | grep -v "ld.gold: warning: Cannot export local symbol" \
  | grep -E "error|Executed [0-9]+ tests|leak of|SUMMARY|Suppressions used|count +bytes|XCTWaiter|ERROR"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "FAIL: sanitizer run exited with status $status"
  exit "$status"
fi
echo "PASS: all tests passed under ASan + LeakSanitizer, process exited 0"
