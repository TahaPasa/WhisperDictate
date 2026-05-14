#!/usr/bin/env bash
# Idempotent: builds whisper-cli from source only if the binary is missing.
# Requires: cmake, a C++17 compiler (Xcode CLT).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="$REPO_ROOT/whisper.cpp"
BINARY="$WHISPER_DIR/build/bin/whisper-cli"

if [[ -x "$BINARY" ]]; then
    echo "[build-whisper] whisper-cli already built at $BINARY"
    exit 0
fi

echo "[build-whisper] Building whisper-cli with Metal (Apple Silicon GPU) support…"

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
    -DGGML_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON

cmake --build "$WHISPER_DIR/build" \
    --target whisper-cli \
    --config Release \
    -j "$(sysctl -n hw.logicalcpu)"

echo "[build-whisper] Done: $BINARY"
