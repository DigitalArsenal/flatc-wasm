#!/usr/bin/env bash
set -euo pipefail

npm i

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_DIR="$ROOT_DIR/packages"
EMSDK_DIR="$PACKAGES_DIR/emsdk"
FLATBUFFERS_DIR="$PACKAGES_DIR/flatbuffers"

if command -v nproc >/dev/null 2>&1; then
  CORES=$(nproc)
elif command -v sysctl >/dev/null 2>&1; then
  CORES=$(sysctl -n hw.ncpu)
else
  CORES=4
fi

mkdir -p "$PACKAGES_DIR"

DEFAULT_REMOTE="https://github.com/DigitalArsenal/flatbuffers.git"
GOOGLE_REMOTE="https://github.com/google/flatbuffers.git"

read -r -p "Select FlatBuffers codebase ([d]igitalarsenal/[g]oogle) [d]: " REMOTE_CHOICE
REMOTE_CHOICE_LOWER=$(echo "${REMOTE_CHOICE:-d}" | tr '[:upper:]' '[:lower:]')

case "$REMOTE_CHOICE_LOWER" in
  g|"google")
    FLATBUFFERS_REMOTE="$GOOGLE_REMOTE"
    REMOTE_NAME="google/flatbuffers"
    ;;
  *)
    FLATBUFFERS_REMOTE="$DEFAULT_REMOTE"
    REMOTE_NAME="DigitalArsenal/flatbuffers"
    ;;
esac

echo "[flatc_wasm] Using FlatBuffers remote: ${REMOTE_NAME}"

AVAILABLE_TAGS=()
echo "[flatc_wasm] Resolving tags from ${REMOTE_NAME}..."
TAG_LIST_OUTPUT=""
if TAG_LIST_OUTPUT=$(git ls-remote --tags --refs "$FLATBUFFERS_REMOTE" 2>/dev/null | awk -F/ '{print $NF}' | sort -V); then
  if [ -n "$TAG_LIST_OUTPUT" ]; then
    while IFS= read -r TAG_LINE; do
      [ -n "$TAG_LINE" ] && AVAILABLE_TAGS+=("$TAG_LINE")
    done <<<"$TAG_LIST_OUTPUT"
    if ((${#AVAILABLE_TAGS[@]} > 0)); then
      DEFAULT_FLATBUFFERS_TAG="${AVAILABLE_TAGS[$((${#AVAILABLE_TAGS[@]} - 1))]}"
      echo "[flatc_wasm] Latest tags (showing up to 10):"
      START_INDEX=$(( ${#AVAILABLE_TAGS[@]} > 10 ? ${#AVAILABLE_TAGS[@]} - 10 : 0 ))
      for ((i=START_INDEX; i<${#AVAILABLE_TAGS[@]}; i++)); do
        TAG="${AVAILABLE_TAGS[$i]}"
        if [ "$TAG" = "$DEFAULT_FLATBUFFERS_TAG" ]; then
          echo "  * $TAG (default)"
        else
          echo "  - $TAG"
        fi
      done
    fi
  fi
else
  echo "[flatc_wasm] Warning: unable to list tags from ${REMOTE_NAME}; defaulting to 'main'."
fi

if ((${#AVAILABLE_TAGS[@]} == 0)); then
  DEFAULT_FLATBUFFERS_TAG=""
fi

if [ -z "${DEFAULT_FLATBUFFERS_TAG:-}" ]; then
  DEFAULT_FLATBUFFERS_TAG="main"
fi

read -r -p "Enter FlatBuffers tag to build [${DEFAULT_FLATBUFFERS_TAG}]: " REQUESTED_FLATBUFFERS_TAG
FLATBUFFERS_REF=${REQUESTED_FLATBUFFERS_TAG:-$DEFAULT_FLATBUFFERS_TAG}

echo "[flatc_wasm] Using FlatBuffers ref: ${FLATBUFFERS_REF}"

if [ ! -d "$EMSDK_DIR" ]; then
  echo "[flatc_wasm] emsdk not found, cloning into packages/..."
  git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
  pushd "$EMSDK_DIR" >/dev/null
  ./emsdk install latest
  ./emsdk activate latest
  popd >/dev/null
fi

echo "[flatc_wasm] Activating emsdk..."
# shellcheck disable=SC1091
source "$EMSDK_DIR/emsdk_env.sh"

if [ -d "$FLATBUFFERS_DIR/.git" ]; then
  CURRENT_REMOTE=$(git -C "$FLATBUFFERS_DIR" remote get-url origin)
  if [ "$CURRENT_REMOTE" != "$FLATBUFFERS_REMOTE" ]; then
    echo "[flatc_wasm] Existing FlatBuffers clone points to $CURRENT_REMOTE; recreating from ${REMOTE_NAME}..."
    rm -rf "$FLATBUFFERS_DIR"
    git clone "$FLATBUFFERS_REMOTE" "$FLATBUFFERS_DIR"
  else
    echo "[flatc_wasm] Updating FlatBuffers clone from ${REMOTE_NAME}..."
    git -C "$FLATBUFFERS_DIR" fetch origin --tags --prune
    CURRENT_BRANCH=$(git -C "$FLATBUFFERS_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
    if [ -n "$CURRENT_BRANCH" ]; then
      git -C "$FLATBUFFERS_DIR" pull --ff-only origin "$CURRENT_BRANCH" || true
    fi
  fi
else
  if [ -d "$FLATBUFFERS_DIR" ]; then
    echo "[flatc_wasm] Removing existing non-git directory at $FLATBUFFERS_DIR..."
    rm -rf "$FLATBUFFERS_DIR"
  fi
  echo "[flatc_wasm] Cloning FlatBuffers from ${REMOTE_NAME}..."
  git clone "$FLATBUFFERS_REMOTE" "$FLATBUFFERS_DIR"
fi

echo "[flatc_wasm] Preparing FlatBuffers source..."
git -C "$FLATBUFFERS_DIR" fetch origin --tags --prune
if ! git -C "$FLATBUFFERS_DIR" rev-parse "$FLATBUFFERS_REF" >/dev/null 2>&1; then
  git -C "$FLATBUFFERS_DIR" fetch origin "$FLATBUFFERS_REF"
fi
git -C "$FLATBUFFERS_DIR" checkout "$FLATBUFFERS_REF"

WASM_BUILD_DIR="$FLATBUFFERS_DIR/wasm_build"
mkdir -p "$WASM_BUILD_DIR"

pushd "$FLATBUFFERS_DIR" >/dev/null
echo "[flatc_wasm] Building flatc.mjs (ES6, isomorphic)..."
emcmake cmake -S . -B "$WASM_BUILD_DIR" \
  -DFLATBUFFERS_BUILD_FLATC=ON \
  -DFLATBUFFERS_BUILD_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="-s EXPORTED_RUNTIME_METHODS='[\"FS\",\"callMain\"]' \
                            -s MODULARIZE=1 \
                            -s EXPORT_ES6=1 \
                            -s ENVIRONMENT=web,worker \
                            -s FORCE_FILESYSTEM=1 \
                            -s EXPORTED_RUNTIME_METHODS=['FS','FS_createDataFile','callMain'] \
                            -s EXPORTED_FUNCTIONS=['_main'] \
                            -s EXIT_RUNTIME=1 \
                            -s SINGLE_FILE=1"

emmake cmake --build "$WASM_BUILD_DIR" --target flatc -- -j${CORES}
popd >/dev/null

mkdir -p "$ROOT_DIR/src"
cp "$WASM_BUILD_DIR/flatc.js" "$ROOT_DIR/src/flatc.mjs"
echo "[flatc_wasm] flatc.mjs updated at src/flatc.mjs"
