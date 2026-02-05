#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=""
OUT_DIR="$ROOT_DIR/out/wasi"

usage() {
  cat <<'USAGE'
Usage:
  build_wasi.sh --mode <cpython-tools|python-wasi|wasmlabs> [options]

Modes:
  cpython-tools   Use CPython's official wasm build tooling (Tools/wasm/wasm_build.py)
  python-wasi     Use singlestore-labs/python-wasi helper scripts
  wasmlabs        Use WasmLabs prebuilt Python WASI runtimes (manual download)

Options (common):
  --out <dir>     Output directory (default: out/wasi)

Options (cpython-tools):
  --cpython-src <path>   CPython source tree
  --wasi-sdk <path>      WASI SDK path

Options (python-wasi):
  --python-wasi-src <path>   python-wasi repo path

Options (wasmlabs):
  --wasmlabs-wasm <path>     Prebuilt python.wasm path
USAGE
}

CPYTHON_SRC=""
WASI_SDK=""
PYTHON_WASI_SRC=""
WASMLABS_WASM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;

    --cpython-src) CPYTHON_SRC="$2"; shift 2 ;;
    --wasi-sdk) WASI_SDK="$2"; shift 2 ;;

    --python-wasi-src) PYTHON_WASI_SRC="$2"; shift 2 ;;

    --wasmlabs-wasm) WASMLABS_WASM="$2"; shift 2 ;;

    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage
  exit 1
fi

mkdir -p "$OUT_DIR"

case "$MODE" in
  cpython-tools)
    if [[ -z "$CPYTHON_SRC" || -z "$WASI_SDK" ]]; then
      echo "cpython-tools mode requires --cpython-src and --wasi-sdk" >&2
      exit 1
    fi
    echo "Using CPython's Tools/wasm/wasm_build.py" >&2
    echo "Run (example):" >&2
    echo "  python3 $CPYTHON_SRC/Tools/wasm/wasm_build.py --wasi-sdk $WASI_SDK --clean --verbose" >&2
    echo "Then copy the generated python.wasm into: $OUT_DIR" >&2
    ;;

  python-wasi)
    if [[ -z "$PYTHON_WASI_SRC" ]]; then
      echo "python-wasi mode requires --python-wasi-src" >&2
      exit 1
    fi
    echo "Using singlestore-labs/python-wasi" >&2
    echo "Run (example):" >&2
    echo "  (cd $PYTHON_WASI_SRC && ./run.sh)" >&2
    echo "Then copy the resulting wasm artifact into: $OUT_DIR" >&2
    ;;

  wasmlabs)
    if [[ -z "$WASMLABS_WASM" ]]; then
      echo "wasmlabs mode requires --wasmlabs-wasm" >&2
      exit 1
    fi
    cp "$WASMLABS_WASM" "$OUT_DIR/python.wasm"
    echo "Copied prebuilt python.wasm to $OUT_DIR/python.wasm" >&2
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac

cat > "$OUT_DIR/README.txt" <<'EOF'
WASI notes:
- CPython on wasm32-wasi is experimental and may not support threads, sockets, or native extensions.
- You must provide a WASI runtime (e.g., wasmtime) to execute python.wasm.
- Python stdlib may be embedded in the wasm or provided via a mapped virtual filesystem.
EOF

echo "WASI output folder: $OUT_DIR"
