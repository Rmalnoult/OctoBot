#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "$ROOT_DIR/assets/python" ]]; then
  echo "assets/python not found. Run scripts/prepare_python.sh first." >&2
  exit 1
fi

PAYLOAD="$ROOT_DIR/assets/python-payload.tar.zst"

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd not found. Install zstd to build a portable payload." >&2
  exit 1
fi

rm -f "$PAYLOAD"

tar -C "$ROOT_DIR/assets" -cf - python | zstd -T0 -19 -o "$PAYLOAD"

echo "Created payload: $PAYLOAD"

cd "$ROOT_DIR"
PYEMBED_PAYLOAD="$PAYLOAD" cargo build --release

echo "Portable binary: $ROOT_DIR/target/release/pyembed-runner"
