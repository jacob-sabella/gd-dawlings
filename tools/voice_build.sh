#!/usr/bin/env bash
# Builds native/voice (dawlings' C ABI over CHIMERA, the pinned submodule vendor/chimera) into a
# static library for the rack engine, and prints its path. Needs cargo (Rust 1.85+, edition 2024).
# Cargo fetches the crates CHIMERA uses (serde, serde_json, libm, flate2) at the versions in
# native/voice/Cargo.lock; VOICE_BUILD_DIR moves the build (default build/voice). VOICE_TARGET=x86_64-pc-windows-gnu
# builds it for Windows (rustup target add x86_64-pc-windows-gnu; the rack's Windows build, tools/rack_build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f vendor/chimera/Cargo.toml ] || { echo "run: git submodule update --init vendor/chimera" >&2; exit 1; }
OUT=${VOICE_BUILD_DIR:-build/voice}
TARGET=()
LIB="$OUT/release/libdawlings_voice.a"
if [ -n "${VOICE_TARGET:-}" ]; then
  TARGET=(--target "$VOICE_TARGET")
  LIB="$OUT/$VOICE_TARGET/release/libdawlings_voice.a"
fi
cargo build --quiet --release --locked "${TARGET[@]}" --manifest-path native/voice/Cargo.toml --target-dir "$OUT" >&2 \
  || cargo build --quiet --release "${TARGET[@]}" --manifest-path native/voice/Cargo.toml --target-dir "$OUT" >&2
echo "$LIB"
