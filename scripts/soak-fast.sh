#!/usr/bin/env bash
# Deterministic local soak harness: fake model/runtime paths, temp workspaces,
# real session/index/tool plumbing where covered by tests. No network or GPU.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${INTERLESS_SOAK_ITERATIONS:-1}"

cd "$ROOT"

for _ in $(seq 1 "$ITERATIONS"); do
  ./scripts/test.sh --filter fakeSoakCycleKeepsStateBoundedAndExportsDiagnostics
done

