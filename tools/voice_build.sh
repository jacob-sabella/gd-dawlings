#!/usr/bin/env bash
# Builds native/voice (dawlings' C ABI over CHIMERA, the pinned submodule vendor/chimera) into a
# static library for the rack engine, and prints its path. Needs cargo (Rust 1.85+, edition 2024).
# Cargo fetches the crates CHIMERA uses (serde, serde_json, libm, flate2) at the versions in
# native/voice/Cargo.lock; VOICE_BUILD_DIR moves the build (default build/voice).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f vendor/chimera/Cargo.toml ] || { echo "run: git submodule update --init vendor/chimera" >&2; exit 1; }
OUT=${VOICE_BUILD_DIR:-build/voice}
cargo build --quiet --release --locked --manifest-path native/voice/Cargo.toml --target-dir "$OUT" >&2 \
  || cargo build --quiet --release --manifest-path native/voice/Cargo.toml --target-dir "$OUT" >&2
echo "$OUT/release/libdawlings_voice.a"
