#!/usr/bin/env bash
# Run the test suite, adding the Swift Testing framework search path when needed.
#
# Swift Testing ships as `Testing.framework` under the active developer dir, but
# SwiftPM does not add that search path automatically on a Command Line Tools–only
# install (no full Xcode). When the framework is present there, pass it through;
# otherwise (full Xcode) `swift test` finds it on its own.
#
# Usage:
#   ./scripts/test.sh                         # fast suite (integration tests skip)
#   INTERLESS_RUN_MLX_INTEGRATION=1 ./scripts/test.sh --filter MLXEngineIntegrationTests
set -euo pipefail

FW="$(xcode-select -p)/Library/Developer/Frameworks"
EXTRA=()
if [ -d "$FW/Testing.framework" ]; then
  EXTRA+=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW")
fi

# bash 3.2 (macOS default) errors on "${EXTRA[@]}" when the array is empty under
# `set -u`, so branch on length. EXTRA is empty under full Xcode (Swift Testing
# is found natively) and populated only on a Command-Line-Tools-only install.
if [ "${#EXTRA[@]}" -gt 0 ]; then
  exec swift test "${EXTRA[@]}" "$@"
else
  exec swift test "$@"
fi
