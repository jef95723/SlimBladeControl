#!/bin/bash
# Prefer the caller's Rust toolchain; also support the workspace-local install.
if ! command -v cargo >/dev/null && [[ -x ../.toolchain/cargo/bin/cargo ]]; then
  export CARGO_HOME="$(cd ../.toolchain/cargo && pwd)"
  export RUSTUP_HOME="$(cd ../.toolchain/rustup && pwd)"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
if [[ "$(uname -s)" == Darwin ]]; then
  export MACOSX_DEPLOYMENT_TARGET=12.0
fi
