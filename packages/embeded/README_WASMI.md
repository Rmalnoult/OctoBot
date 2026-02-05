# WASI + Wasmi Notes

This repo includes `scripts/build_wasi.sh` to help stage a `python.wasm` artifact.
If you want to **embed** and run that WASI module in Rust, `wasmi` is a good fit.
Wasmi is a Rust WebAssembly interpreter, and WASI support is provided via the
`wasmi_wasi` crate.

## What Wasmi Is (and Isn’t)

- Wasmi is a **library**, not a CLI runtime. You embed it in your Rust app.
- WASI support is available via the `wasmi_wasi` crate.

If you want a CLI runtime to quickly test `python.wasm`, use Wasmtime or Wasmer
instead of Wasmi.

## Minimal Embed Flow (High-Level)

1. Obtain a `python.wasm` built for `wasm32-wasi`.
2. In Rust, add `wasmi` and `wasmi_wasi` crates.
3. Create a WASI context (preopen dirs, env vars, args).
4. Instantiate the module and call its entrypoint (often `_start` for WASI).

## How To Get `python.wasm`

You have three common options. Pick one based on how “official” vs “prebuilt” you want it:

### Option A: CPython official WASI tooling (source build)

CPython ships WASI build tooling under `Tools/wasm/`. You build from a CPython
source tree and produce a WASI `python.wasm` artifact.

High-level steps:
1. Get CPython source for the version you want.
2. Use the WASI build tooling to produce `python.wasm` (see CPython’s WASI docs).

Example (illustrative only; exact flags may change by CPython version):
```bash
python3 /path/to/cpython/Tools/wasm/wasm_build.py --wasi-sdk /path/to/wasi-sdk --clean --verbose
```

### Option B: singlestore-labs/python-wasi (build helper)

The `python-wasi` repo provides scripts (and an optional Docker flow) to build
CPython for WASI and produce a runnable `python.wasm`.

High-level steps:
1. Clone `singlestore-labs/python-wasi`.
2. Build the Docker image and run the container (optional but recommended).
3. Run `./run.sh` to build; it will produce a `wasi-python*.wasm` artifact and can
   optionally pack the stdlib into the wasm file.

Example:
```bash
git clone https://github.com/singlestore-labs/python-wasi
cd python-wasi
./run.sh
```

The repo supports multiple build modes:
- Default: packs the stdlib into the wasm file (single-file, large output).
- `COMPILE_STDLIB=0`: skips bytecode compilation (smaller wasm, but no on-the-fly bytecode writes).
- `INCLUDE_STDLIB=0`: excludes stdlib from the wasm; you must map a stdlib directory at runtime.

Examples:
```bash
# Default (stdlib packed)
wasmtime run -- wasi-python3.10.wasm

# No stdlib embedded: map the stdlib directory into WASI
wasmtime run --mapdir=/opt/wasi-python/lib/python3.10::/opt/wasi-python/lib/python3.10 \
  -- wasi-python3.10.wasm
```

`PYTHONHOME` defaults to `/opt/wasi-python`, and you can relocate by mapping a new
directory and setting `PYTHONHOME` accordingly.

### Option C: WasmLabs prebuilt binaries (download)

WasmLabs publishes prebuilt Python WASI artifacts and examples for running them.

This is the fastest way to get a working `python.wasm`.

Typical layout (from WasmLabs examples):
```
python.wasm
usr/local/lib/python3.x/
```
You must map `usr/` into the WASI filesystem at runtime so Python can find its stdlib.

## Other Things You’ll Need

- A WASI runtime to run `python.wasm` (e.g., Wasmtime).
- A plan for Python stdlib:
  - Some builds embed stdlib into the wasm file (single large wasm).
  - Others require mapping a stdlib directory via WASI VFS.

If you plan to embed with `wasmi`:
- You will set WASI preopens for any stdlib directory and data directories.
- You will pass `argv` so Python can locate its home (or set `PYTHONHOME`).

## Notes for Python

- CPython on WASI is experimental and may not support native extensions.
- The Python stdlib may be embedded in the WASM artifact or provided via a virtual filesystem.
- WASI currently lacks full support for threads, subprocesses, and sockets, which
  impacts many Python packages.

## Prebuilt WASM: What Exists Today

Yes, **there are prebuilt `python.wasm` artifacts** from WasmLabs’ WebAssembly Language Runtimes
project. They publish a Python WASI build and provide example layouts showing the
`python.wasm` plus a `usr/local/lib/python3.x` stdlib tree that must be mapped at runtime.

If you want a more turnkey install, WasmLabs’ Workers Server tooling can also
install the Python WASM runtime for you.

If you want, I can add a concrete Rust example using `wasmi` + `wasmi_wasi`
once you pick the exact `python.wasm` artifact you intend to use.
