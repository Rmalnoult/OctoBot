#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PY_BIN="$(find "$ROOT_DIR/assets/python" \( -type f -o -type l \) -path "*/bin/python3" | head -n 1)"
if [[ -z "$PY_BIN" ]]; then
  echo "Embedded python not found under $ROOT_DIR/assets/python" >&2
  echo "Run scripts/prepare_python.sh first." >&2
  exit 1
fi

cd "$ROOT_DIR"

PYO3_PYTHON="$PY_BIN" cargo build --release

echo "Binary: $ROOT_DIR/target/release/pyembed-runner"
echo "Python: $ROOT_DIR/target/release/python"
