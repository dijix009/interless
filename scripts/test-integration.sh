#!/usr/bin/env bash
# Run the real-MLX integration tests (real token streaming + two-model concurrency).
#
# These MUST be built with xcodebuild, not `swift test`: mlx-swift compiles its
# Metal shader library (default.metallib) via Xcode's build rules
# ("PrepareMetalShaders"), which the SwiftPM CLI build does not run — so under
# `swift test` MLX aborts at runtime with "Failed to load the default metallib".
#
# Requirements: full Xcode + the Metal toolchain (`xcrun metal --version` must
# work — see README "First-time toolchain setup"). The first run downloads two
# tiny models (~1 GB) from Hugging Face.
#
# Flags explained:
#   -skipMacroValidation            trust the MLXHuggingFace package macro (CLI has no UI prompt)
#   -D RUN_MLX_INTEGRATION          enables the gated suite (see IntegrationGate.swift)
#   OTHER_SWIFT_FLAGS='$(inherited) …'  appends the flag without dropping SwiftPM's own flags
set -euo pipefail

exec xcodebuild test \
  -scheme Interless-Package \
  -destination 'platform=macOS' \
  -only-testing:MLXEngineIntegrationTests \
  -skipMacroValidation \
  OTHER_SWIFT_FLAGS='$(inherited) -D RUN_MLX_INTEGRATION' \
  "$@"
