#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <python-build-standalone-tarball> [wheel-path] [requirements-path]" >&2
  exit 1
fi

TARBALL="$1"
WHEEL_PATH="${2:-}"
REQ_PATH="${3:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY_ROOT="$ROOT_DIR/assets/python"

rm -rf "$PY_ROOT"
mkdir -p "$PY_ROOT"

case "$TARBALL" in
  *.tar.zst)
    if ! command -v unzstd >/dev/null 2>&1; then
      echo "unzstd not found. Install zstd or provide a .tar.gz artifact." >&2
      exit 1
    fi
    tar --use-compress-program=unzstd -xf "$TARBALL" -C "$PY_ROOT"
    ;;
  *.tar.gz)
    tar -xzf "$TARBALL" -C "$PY_ROOT"
    ;;
  *)
    echo "Unsupported tarball format: $TARBALL" >&2
    exit 1
    ;;
 esac

PY_BIN="$(find "$PY_ROOT" \( -type f -o -type l \) -path "*/bin/python3" | head -n 1)"
if [[ -z "$PY_BIN" ]]; then
  echo "python3 not found under $PY_ROOT" >&2
  exit 1
fi

"$PY_BIN" -m ensurepip --upgrade
"$PY_BIN" -m pip install --upgrade pip setuptools wheel

if [[ -n "$REQ_PATH" ]]; then
  "$PY_BIN" -m pip install -r "$REQ_PATH"
fi

# Ensure setuptools-provided distutils is available for Python 3.12+.
if ! "$PY_BIN" - <<'PY' >/dev/null 2>&1; then
import distutils  # noqa: F401
PY
  "$PY_BIN" -m pip install --upgrade setuptools
fi

if [[ -n "$WHEEL_PATH" ]]; then
  "$PY_BIN" -m pip install "$WHEEL_PATH"
fi

PYTHON_ROOT="$PY_ROOT" "$PY_BIN" - <<'PY'
import json
import os
import site
import sysconfig

root = os.environ["PYTHON_ROOT"]
paths = set()
paths.add(sysconfig.get_paths()["stdlib"])
paths.add(sysconfig.get_paths()["platstdlib"])
for p in site.getsitepackages():
    paths.add(p)

# Some builds include user site; include it only if it exists in-tree.
user_site = site.getusersitepackages()
if user_site and user_site.startswith(root):
    paths.add(user_site)

rel_paths = []
for p in sorted(paths):
    rel_paths.append(os.path.relpath(p, root))

cfg = {
    "python_home": ".",
    "python_path": rel_paths,
}

with open(os.path.join(root, "pyembed.json"), "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

echo "Embedded Python prepared in $PY_ROOT"
