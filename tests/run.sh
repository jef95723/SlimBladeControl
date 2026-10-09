#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p build
if ! command -v cargo >/dev/null; then
  echo 'Rust toolchain missing. Install Rust from https://rustup.rs, then retry.' >&2
  exit 1
fi
cargo test --offline --manifest-path rust/Cargo.toml
cargo build --offline --release --manifest-path rust/Cargo.toml
libs=(-ldl -lpthread -lm)
if [[ "$(uname -s)" == Darwin ]]; then libs=(-liconv -lresolv); fi
cc -std=c11 -Wall -Wextra -Werror -pedantic -DRUST_CORE tests/chords_test.c \
  rust/target/release/libslimblade_core.a "${libs[@]}" -o build/chords_test_rust
build/chords_test_rust
if [[ "$(uname -s)" == Darwin ]]; then
  xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=12.0 \
    tests/native_test.m src/actions.m src/interface.m src/shortcuts.m rust/target/release/libslimblade_core.a \
    -liconv -lresolv -framework Cocoa -framework IOKit -framework ApplicationServices -framework Carbon -framework UniformTypeIdentifiers -o build/native_test
  build/native_test
fi
