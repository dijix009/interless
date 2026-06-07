#!/usr/bin/env bash
# Optional real-MLX soak harness. This is intentionally separate from the fast
# suite because it can download models, use GPU memory, and run for a long time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCHESTRATOR_MODEL="${INTERLESS_ORCHESTRATOR_MODEL:-}"
UTILITY_MODEL="${INTERLESS_UTILITY_MODEL:-}"
ITERATIONS="${INTERLESS_SOAK_ITERATIONS:-3}"

if [ -z "$ORCHESTRATOR_MODEL" ] || [ -z "$UTILITY_MODEL" ]; then
  cat >&2 <<'EOF'
Set INTERLESS_ORCHESTRATOR_MODEL and INTERLESS_UTILITY_MODEL before running real-MLX soak.
This script is manual-only and may download models/use significant unified memory.
EOF
  exit 2
fi

if ! xcrun metal --version >/dev/null 2>&1; then
  echo "xcrun metal is unavailable; install/select full Xcode before real-MLX soak." >&2
  exit 2
fi

cd "$ROOT"

for _ in $(seq 1 "$ITERATIONS"); do
  ./scripts/test-integration.sh
done

