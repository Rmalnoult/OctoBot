# Embedded OctoBot

This package builds a Rust binary that embeds CPython 3.13 using PyO3 and bundles your OctoBot wheel + dependencies into the embedded `site-packages`.

## Layout

- `assets/python/` is the embedded Python distribution and site-packages.
- `assets/python/pyembed.json` describes Python paths used by the runner.
- `src/main.rs` bootstraps Python and runs `octobot.cli:main` by default.

## Prepare embedded Python

1. Download a python-build-standalone CPython 3.13 tarball for your target OS/arch.
2. Run the prep script to unpack Python and install your wheel + deps:

```bash
packages/embeded/scripts/prepare_python.sh \
  /path/to/python-build-standalone.tar.zst \
  dist/octobot-2.0.16-py3-none-any.whl \
  requirements.txt
```

Notes:
- The script updates pip/setuptools/wheel, installs `requirements.txt`, then installs your wheel.
- If you want a different requirements file, pass it as the third argument.
- The script writes `assets/python/pyembed.json` based on the embedded interpreter layout.

## Build the Rust binary

You must point PyO3 at the embedded Python when compiling so it links against the correct libpython.
Use an absolute path (the `**` glob isn’t expanded by all shells), or use the helper script.

```bash
cd packages/embeded
PYO3_PYTHON="$(pwd)/assets/python/python/bin/python3" cargo build --release
```

Or use the helper script:

```bash
packages/embeded/scripts/build.sh
```

`build.rs` copies `assets/python` into `target/release/python` so the binary can find it.

## Run

```bash
./target/release/pyembed-runner
```

Optional env vars:
- `OCTOBOT_PY_MODULE` (default: `octobot.cli`) to change the module executed.
- `OCTOBOT_PY_FUNC` (default: `main`) to change the function executed (set empty to use `runpy`).

Notes:
- Python 3.12+ removed stdlib `distutils`. The runner forces `SETUPTOOLS_USE_DISTUTILS=local` and processes `.pth` files to enable the setuptools shim.

## Multi-arch notes (macOS)

Build separate binaries and embedded Python bundles for `x86_64` and `aarch64` on the matching host, then package per-arch. A universal macOS binary can be built later with `lipo`, but you still need separate Python bundles per arch.

## Targets

Windows will need separate packaging logic (different Python artifacts and OS-specific bundling). This setup keeps that boundary clean by loading Python from a sibling `python` folder.

## Multi-target CLI

`scripts/build_targets.sh` generates per-target outputs and archives.

Examples:

Desktop (macOS arm64):

```bash
packages/embeded/scripts/build_targets.sh \
  --os macos \
  --arch aarch64 \
  --python-tarball /path/to/cpython-3.13.*-install_only_stripped.tar.(zst|gz) \
  --wheel dist/octobot-2.0.16-py3-none-any.whl \
  --requirements full_requirements.txt
```

Android (React Native library module via Chaquopy, arm64-v8a):

```bash
packages/embeded/scripts/build_targets.sh \
  --os android \
  --arch arm64-v8a \
  --android-mode chaquopy \
  --android-minsdk 24 \
  --wheel dist/octobot-2.0.16-py3-none-any.whl \
  --requirements full_requirements.txt
```

This produces a `chaquopy-module/` folder with:
- `pyembed/gradle-snippet.txt`
- `pyembed/react-native-snippet.txt`
- `pyembed/requirements.txt`
- your wheel file

iOS (Python-Apple-support prebuilt bundle):

```bash
packages/embeded/scripts/build_targets.sh \
  --os ios \
  --arch aarch64 \
  --ios-mode prebuilt \
  --ios-support-tarball /path/to/Python-Apple-support-*.tar.gz \
  --ios-framework-name PyEmbed \
  --ios-bundle-name PyEmbedResources
```

iOS build mode (manual):

```bash
packages/embeded/scripts/build_targets.sh \
  --os ios \
  --arch aarch64 \
  --ios-mode build \
  --ios-support-repo /path/to/Python-Apple-support
```

Android build mode (manual CPython):

```bash
packages/embeded/scripts/build_targets.sh \
  --os android \
  --arch arm64-v8a \
  --android-mode build \
  --android-cpython-src /path/to/cpython \
  --android-ndk /path/to/android-ndk
```

## WASI (Wasmi)

If you plan to embed and run `python.wasm` in Rust, see:
- `packages/embeded/README_WASMI.md`

## Mobile AAR/XCFramework Layout (Templates)

This repo does not generate a full AAR or XCFramework automatically yet, but the CLI outputs are structured to make it straightforward to build them.

### Android (AAR for React Native)

1. Generate the Chaquopy module bundle:

```bash
packages/embeded/scripts/build_targets.sh \
  --os android \
  --arch arm64-v8a \
  --android-mode chaquopy \
  --android-minsdk 24 \
  --wheel dist/octobot-2.0.16-py3-none-any.whl \
  --requirements full_requirements.txt
```

1. Copy `out/android-arm64-v8a/chaquopy-module` into your React Native module’s Android folder.
1. Merge the contents of:
   - `pyembed/gradle-snippet.txt`
   - `pyembed/react-native-snippet.txt`

1. Build an AAR:

```bash
cd android
./gradlew :<your-module-name>:assembleRelease
```

This produces an AAR at:

```
<your-module-name>/build/outputs/aar/
```

#### Using the AAR in an Android app

1. Copy the AAR into your app’s `libs/` folder.
1. Add it to your app module dependencies:

```gradle
dependencies {
  implementation files("libs/<your-module-name>-release.aar")
}
```

1. Ensure the Chaquopy plugin is applied in exactly one module in the app (either the AAR module or the app module, but not both).
1. In Kotlin, call into the Python entrypoint:

```kotlin
val py = com.chaquo.python.Python.getInstance()
val mod = py.getModule("pyembed_entry")
mod.callAttr("main")
```

### iOS (XCFramework)

1. Obtain a Python-Apple-support bundle (prebuilt or built from source).
1. Use `build_targets.sh` to generate an XCFramework + resource bundle layout.
1. Add the XCFramework(s) and the resource bundle to your Xcode project.
1. Add your wheel and dependencies to the embedded Python `site-packages` inside the resource bundle.

At a minimum, your iOS project needs:
- The Python framework (from Python-Apple-support)
- `PYTHONHOME` pointing at the embedded framework’s Python home
- A small bootstrap that calls into Python and runs `octobot.cli:main`

#### Using the XCFramework in an iOS app

1. Add the Python XCFramework to your Xcode project (Frameworks, Libraries, and Embedded Content).
1. Add the generated resource bundle (e.g. `PyEmbedResources.bundle`) to your app resources.
1. Set `PYTHONHOME` at startup to point to the bundle's `python/` folder.
1. Initialize Python and call the OctoBot entrypoint from Swift:

```swift
setenv("PYTHONHOME", pythonHomePath, 1)
// Initialize and run Python. Your exact API depends on how you link the Python framework.
```

Note: the exact Swift/JNI bootstrap code depends on how the Python framework is linked in your Xcode project; the key requirement is to run `octobot.cli:main` within the embedded interpreter.

## Step-By-Step: Generate pyembed-runner (Desktop)

1. Download the python-build-standalone CPython 3.13 artifact for your OS/arch.
1. Prepare the embedded Python (install full deps + wheel):

```bash
packages/embeded/scripts/prepare_python.sh \
  /path/to/cpython-3.13.*-install_only_stripped.tar.(zst|gz) \
  dist/octobot-2.0.16-py3-none-any.whl \
  full_requirements.txt
```

1. Build the Rust binary:

```bash
packages/embeded/scripts/build.sh
```

1. Run:

```bash
./packages/embeded/target/release/pyembed-runner
```

## Fully Portable Desktop Binary

There are two portability modes:

### 1) Folder Portable (no self-extract)

You must ship:
- the `pyembed-runner` binary
- the sibling `python/` folder produced by the build

The simplest way is to use the multi-target CLI, which packages both into a tarball:

```bash
packages/embeded/scripts/build_targets.sh \
  --os macos \
  --arch aarch64 \
  --python-tarball /path/to/cpython-3.13.*-install_only_stripped.tar.(zst|gz) \
  --wheel dist/octobot-2.0.16-py3-none-any.whl \
  --requirements full_requirements.txt
```

This produces:
- `packages/embeded/out/macos-aarch64/bin/pyembed-runner`
- `packages/embeded/out/macos-aarch64/python/`
- `packages/embeded/out/macos-aarch64.tar.gz`

To run on another machine:
1. Extract the tarball.
1. Keep `bin/pyembed-runner` and `python/` in the same folder.
1. Run `./bin/pyembed-runner`.

Notes:
- The build is **OS/arch specific** (e.g., macOS arm64 vs x86_64).
- For macOS, the binary uses an `rpath` to load `libpython` from `./python/python/lib`.

### 2) Self-Extracting Portable (single binary)

This builds a binary which **embeds** the Python payload and unpacks it on first run
into a cache directory (no manual extraction required).

```bash
packages/embeded/scripts/build_portable.sh
```

Runtime details:
- Extracts to `~/.cache/octobot-pyembed/<payload-name>/` by default.
- Override extraction location with `PYEMBED_EXTRACT_DIR=/path`.
- The embedded payload is generated from `assets/python` (run `prepare_python.sh` first).
