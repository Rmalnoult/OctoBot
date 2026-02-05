#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"

OS=""
ARCH=""
PY_TARBALL=""
WHEEL_PATH=""
REQ_PATH=""

IOS_MODE="prebuilt"
IOS_SUPPORT_TARBALL=""
IOS_SUPPORT_REPO=""
IOS_FRAMEWORK_NAME="PyEmbed"
IOS_BUNDLE_NAME="PyEmbedResources"

ANDROID_MODE="prebuilt"
ANDROID_PYTHON_ROOT=""
ANDROID_CPYTHON_SRC=""
ANDROID_NDK=""
ANDROID_MINSDK="24"
ANDROID_MODULE_NAME="pyembed"
ANDROID_PACKAGE_NAME="com.pyembed"

usage() {
  cat <<'USAGE'
Usage:
  build_targets.sh --os <linux|macos|ios|android> --arch <x86_64|aarch64|arm64-v8a> [options]

Desktop options:
  --python-tarball <path>   python-build-standalone tarball
  --wheel <path>            OctoBot wheel
  --requirements <path>     Requirements file (use full_requirements.txt for full deps)

iOS options:
  --ios-mode <prebuilt|build>         (default: prebuilt)
  --ios-support-tarball <path>        Prebuilt Python-Apple-support .tar.gz
  --ios-support-repo <path>           Local clone of Python-Apple-support (for build)
  --ios-framework-name <name>         iOS framework name (default: PyEmbed)
  --ios-bundle-name <name>            iOS resource bundle name (default: PyEmbedResources)
  --ios-framework-name <name>         iOS framework name (default: PyEmbed)

Android options:
  --android-mode <prebuilt|build|chaquopy> (default: prebuilt)
  --android-python-root <path>        Prebuilt Python root containing libpython and stdlib
  --android-cpython-src <path>        CPython source tree (for build)
  --android-ndk <path>                Android NDK path (for build)
  --android-minsdk <num>              minSdkVersion for Chaquopy (default: 24)
  --android-module-name <name>        Android library module name (default: pyembed)
  --android-package-name <name>       Android package name (default: com.pyembed)

Outputs:
  1) Embedded python bundle in out/<os>-<arch>/python
  2) pyembed-runner binary (desktop only) in out/<os>-<arch>/bin
  3) Packaged archive out/<os>-<arch>.tar.gz
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) OS="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --python-tarball) PY_TARBALL="$2"; shift 2 ;;
    --wheel) WHEEL_PATH="$2"; shift 2 ;;
    --requirements) REQ_PATH="$2"; shift 2 ;;

    --ios-mode) IOS_MODE="$2"; shift 2 ;;
    --ios-support-tarball) IOS_SUPPORT_TARBALL="$2"; shift 2 ;;
    --ios-support-repo) IOS_SUPPORT_REPO="$2"; shift 2 ;;
    --ios-framework-name) IOS_FRAMEWORK_NAME="$2"; shift 2 ;;
    --ios-bundle-name) IOS_BUNDLE_NAME="$2"; shift 2 ;;
    --ios-framework-name) IOS_FRAMEWORK_NAME="$2"; shift 2 ;;

    --android-mode) ANDROID_MODE="$2"; shift 2 ;;
    --android-python-root) ANDROID_PYTHON_ROOT="$2"; shift 2 ;;
    --android-cpython-src) ANDROID_CPYTHON_SRC="$2"; shift 2 ;;
    --android-ndk) ANDROID_NDK="$2"; shift 2 ;;
    --android-minsdk) ANDROID_MINSDK="$2"; shift 2 ;;
    --android-module-name) ANDROID_MODULE_NAME="$2"; shift 2 ;;
    --android-package-name) ANDROID_PACKAGE_NAME="$2"; shift 2 ;;

    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$OS" || -z "$ARCH" ]]; then
  usage
  exit 1
fi

TARGET_DIR="$OUT_DIR/${OS}-${ARCH}"
BIN_DIR="$TARGET_DIR/bin"
PY_DIR="$TARGET_DIR/python"

rm -rf "$TARGET_DIR"
mkdir -p "$BIN_DIR" "$PY_DIR"

case "$OS" in
  linux|macos)
    if [[ -z "$PY_TARBALL" || -z "$WHEEL_PATH" || -z "$REQ_PATH" ]]; then
      echo "For desktop targets, --python-tarball, --wheel, and --requirements are required." >&2
      exit 1
    fi

    "$ROOT_DIR/scripts/prepare_python.sh" "$PY_TARBALL" "$WHEEL_PATH" "$REQ_PATH"
    "$ROOT_DIR/scripts/build.sh"

    cp -R "$ROOT_DIR/target/release/python" "$PY_DIR"
    cp "$ROOT_DIR/target/release/pyembed-runner" "$BIN_DIR/"
    ;;

  ios)
    if [[ "$IOS_MODE" == "prebuilt" ]]; then
      if [[ -z "$IOS_SUPPORT_TARBALL" ]]; then
        echo "iOS prebuilt mode requires --ios-support-tarball" >&2
        exit 1
      fi
      mkdir -p "$PY_DIR"
      tar -xzf "$IOS_SUPPORT_TARBALL" -C "$PY_DIR"
      echo "Unpacked Python-Apple-support into $PY_DIR" >&2

      IOS_OUT_DIR="$TARGET_DIR/ios-bundle"
      IOS_FW_DIR="$IOS_OUT_DIR/Frameworks"
      IOS_RES_BUNDLE="$IOS_OUT_DIR/${IOS_BUNDLE_NAME}.bundle"
      mkdir -p "$IOS_FW_DIR" "$IOS_RES_BUNDLE"

      # Copy any xcframeworks included in the support package.
      while IFS= read -r -d '' fw; do
        cp -R "$fw" "$IOS_FW_DIR/"
      done < <(find "$PY_DIR" -name "*.xcframework" -print0)

      # Place the embedded Python tree inside the resource bundle.
      mkdir -p "$IOS_RES_BUNDLE/python"
      cp -R "$PY_DIR"/* "$IOS_RES_BUNDLE/python/"

      cat > "$IOS_OUT_DIR/README.txt" <<EOF
iOS output layout:
  Frameworks/                    (xcframeworks copied from Python-Apple-support if present)
  ${IOS_BUNDLE_NAME}.bundle/     (resource bundle with embedded Python)

Next steps:
  1) Embed the xcframework(s) in your Xcode project.
  2) Add ${IOS_BUNDLE_NAME}.bundle as a resource.
  3) Set PYTHONHOME to the bundle's python/ path at runtime.
  4) Call into Python and run octobot.cli:main.

Framework name label: ${IOS_FRAMEWORK_NAME}
EOF

      echo "Created iOS bundle layout in $IOS_OUT_DIR" >&2
    elif [[ "$IOS_MODE" == "build" ]]; then
      if [[ -z "$IOS_SUPPORT_REPO" ]]; then
        echo "iOS build mode requires --ios-support-repo" >&2
        exit 1
      fi
      echo "Build iOS support packages by running 'make iOS' in $IOS_SUPPORT_REPO" >&2
      echo "Then re-run with --ios-mode prebuilt and --ios-support-tarball pointing at dist/*.tar.gz" >&2
      exit 1
    else
      echo "Unknown --ios-mode: $IOS_MODE" >&2
      exit 1
    fi
    ;;

  android)
    if [[ "$ANDROID_MODE" == "prebuilt" ]]; then
      if [[ -z "$ANDROID_PYTHON_ROOT" ]]; then
        echo "Android prebuilt mode requires --android-python-root" >&2
        exit 1
      fi
      cp -R "$ANDROID_PYTHON_ROOT"/* "$PY_DIR/"
      echo "Copied Android Python root into $PY_DIR" >&2
      echo "You must ensure libpython*.so and stdlib/site-packages are present for $ARCH." >&2
    elif [[ "$ANDROID_MODE" == "build" ]]; then
      if [[ -z "$ANDROID_CPYTHON_SRC" || -z "$ANDROID_NDK" ]]; then
        echo "Android build mode requires --android-cpython-src and --android-ndk" >&2
        exit 1
      fi
      echo "Build CPython for Android using $ANDROID_CPYTHON_SRC/Android/README.md" >&2
      echo "Then re-run with --android-mode prebuilt and --android-python-root pointing at the build output." >&2
      exit 1
    elif [[ "$ANDROID_MODE" == "chaquopy" ]]; then
      if [[ -z "$WHEEL_PATH" || -z "$REQ_PATH" ]]; then
        echo "Android chaquopy mode requires --wheel and --requirements" >&2
        exit 1
      fi

      CHAQUOPY_DIR="$TARGET_DIR/chaquopy-module"
      mkdir -p "$CHAQUOPY_DIR/src/main/python" "$CHAQUOPY_DIR/src/main/resources" "$CHAQUOPY_DIR/pyembed"
      cp "$WHEEL_PATH" "$CHAQUOPY_DIR/pyembed/"
      cp "$REQ_PATH" "$CHAQUOPY_DIR/pyembed/requirements.txt"

      cat > "$CHAQUOPY_DIR/pyembed/README.md" <<EOF
This folder is generated for Chaquopy integration in an Android library module.
Copy it into your React Native Android module and merge the Gradle snippet.
EOF

      cat > "$CHAQUOPY_DIR/pyembed/gradle-snippet.txt" <<'EOF'
// In your Android library module (React Native native module):
plugins {
  id 'com.android.library'
  id 'com.chaquo.python'
}

android {
  defaultConfig {
    minSdk 24
    ndk {
      abiFilters "arm64-v8a"
    }
  }
}

python {
  pip {
    install file("$projectDir/pyembed/YOUR_WHEEL.whl")
    install("-r", "$projectDir/pyembed/requirements.txt")
  }
}
EOF

      cat > "$CHAQUOPY_DIR/pyembed/react-native-snippet.txt" <<'EOF'
// React Native integration (Android)
// 1) Apply Chaquopy in your native module's build.gradle (library module).
// 2) Ensure only ONE module in the app uses the Chaquopy plugin.
// 3) Add the package in your MainApplication (if not using autolinking).
//
// Example for your Android library module (build.gradle):
plugins {
  id 'com.android.library'
  id 'com.chaquo.python'
}

android {
  defaultConfig {
    minSdk 24
    ndk {
      abiFilters "arm64-v8a"
    }
  }
}

python {
  pip {
    install file("$projectDir/pyembed/YOUR_WHEEL.whl")
    install("-r", "$projectDir/pyembed/requirements.txt")
  }
}

// Example usage in Kotlin:
// val py = Python.getInstance()
// val mod = py.getModule("pyembed_entry")
// mod.callAttr("main")
EOF

      cat > "$CHAQUOPY_DIR/src/main/python/pyembed_entry.py" <<'EOF'
def main():
    # Placeholder entry for Chaquopy integration.
    import octobot.cli as cli
    cli.main()
EOF

      echo "Generated Chaquopy module bundle in $CHAQUOPY_DIR" >&2
    else
      echo "Unknown --android-mode: $ANDROID_MODE" >&2
      exit 1
    fi
    ;;

  *)
    echo "Unknown OS: $OS" >&2
    usage
    exit 1
    ;;
esac

# Package the output
(
  cd "$OUT_DIR"
  tar -czf "${OS}-${ARCH}.tar.gz" "${OS}-${ARCH}"
)

echo "Output bundle: $TARGET_DIR"
echo "Archive: $OUT_DIR/${OS}-${ARCH}.tar.gz"
