#!/bin/sh
#
# The gate the iPad work runs before every commit (IPAD_PLAN.md, item 0.3).
#
#   sh scripts/ipad-gate.sh            macOS suite, parity, iOS compile
#   sh scripts/ipad-gate.sh --ios      the same, plus the suite on an iPad simulator
#
# The rule it enforces: the Mac version cannot break, at any commit. So the
# macOS checks come first and a failure there stops everything — an iOS build
# that passes on top of a broken Mac is not progress.
#
# What it does not check: VGTerm. VGTerm links the *staged* SwiftTerm, built by
# CodeBuilder from develop, so building it here would test develop, not this
# branch. It is checked when this branch is merged and restaged.
#
# Tests run serially (--no-parallel, -parallel-testing-enabled NO) so the gate
# does not take over the machine.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CODE=$(CDPATH= cd -- "$ROOT/.." && pwd)
DERIVED=${IPAD_GATE_DERIVED:-$HOME/tmp/SwiftTerm-ipad-gate}
IPAD=${IPAD_SIMULATOR:-iPad Pro 13-inch (M5)}
# The macOS VTG baseline recorded before the port (IPAD_PLAN.md, item 0.4).
# Fewer tests passing than this means tests were lost, not just failed.
MAC_BASELINE=645

cd "$ROOT"
say() { printf '\n== %s ==\n' "$1"; }

say "macOS: the whole SwiftTerm suite"
mkdir -p "$DERIVED"
LOG="$DERIVED/macos-suite.log"
# The whole log is kept, pass or fail. A failure that does not reproduce is
# still a failure, and its cause should not depend on how the gate's output was
# read at the time — one went unexplained on 2026-09-21 for exactly that reason.
out=$(swift test --no-parallel 2>&1) || {
    printf '%s\n' "$out" > "$LOG"
    printf '%s\n' "$out" | tail -30
    echo "FAIL: macOS suite — full log in $LOG" >&2
    exit 1
}
printf '%s\n' "$out" > "$LOG"
count=$(printf '%s\n' "$out" | sed -n 's/.*Test run with \([0-9]*\) tests.*/\1/p' | tail -1)
echo "passed: ${count:-?} tests (baseline $MAC_BASELINE)"
if [ -n "$count" ] && [ "$count" -lt "$MAC_BASELINE" ]; then
    echo "FAIL: fewer macOS tests than the baseline — something was dropped" >&2
    exit 1
fi

say "Capability parity between the Mac and GL hosts"
if [ -f "$CODE/VTGTerm/Scripts/vtg-capability-parity.py" ] && [ -d "$CODE/SwiftTermGL" ]; then
    python3 "$CODE/VTGTerm/Scripts/vtg-capability-parity.py" "$CODE" || { echo "FAIL: capability parity" >&2; exit 1; }
else
    echo "skipped: VTGTerm or SwiftTermGL not beside this checkout"
fi

say "iOS: SwiftTerm compiles for the simulator"
xcodebuild -scheme SwiftTerm -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED/build" -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
    -quiet build || { echo "FAIL: iOS build" >&2; exit 1; }
echo "built"

if [ "${1:-}" = "--ios" ]; then
    say "iOS: the suite on $IPAD"
    xcodebuild test -scheme SwiftTerm-Package -destination "platform=iOS Simulator,name=$IPAD" \
        -derivedDataPath "$DERIVED/test" -skipMacroValidation -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'Test run with|TEST (SUCCEEDED|FAILED)|error:' | tail -5
fi

say "Gate passed"
