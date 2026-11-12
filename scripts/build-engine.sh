#!/usr/bin/env bash
# Builds the built-in speech engine into build/engine/ (Apple silicon only), which scripts/build.sh
# then copies into Cicada.app/Contents/Resources/engine/:
#   qwen3_asr_server   SGLang-Omni's native Qwen3-ASR server (C++ on MLX, no Python), at a pinned commit
#   libmlx.dylib, libjaccl.dylib, mlx.metallib   MLX, from its pinned wheel (so no Xcode is needed
#                                                 to compile the Metal shaders)
#   LICENSES/          the licences of all of the above
# Without build/engine the app builds as before and 语音识别 › 内置 is not offered.
# Needs the network: it downloads the sources, CMake, Ninja and MLX (and uv, when it isn't installed).
#   scripts/build-engine.sh           # build (skipped when build/engine is already this commit)
#   scripts/build-engine.sh --force   # build again
set -euo pipefail
cd "$(dirname "$0")/.."

# The sources: https://github.com/sgl-project/sglang-omni (Apache-2.0), sglang_omni_mlx/native.
REPO=https://github.com/sgl-project/sglang-omni.git
COMMIT=dace4cdc67ec91c4d6502594404fbbba4e4025ee

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "the speech engine builds on an Apple silicon Mac" >&2; exit 1; }

OUT=build/engine
WORK=build/engine-work
if [[ "${1:-}" != --force && -x "$OUT/qwen3_asr_server" && "$(cat "$OUT/COMMIT" 2>/dev/null)" == "$COMMIT" ]]; then
  echo "Speech engine already built ($OUT)"
  exit 0
fi

# uv gets the pinned build tools; without one on PATH, a private copy in the work folder.
if ! command -v uv >/dev/null; then
  [[ -x "$WORK/tools/bin/uv" ]] || { python3 -m venv "$WORK/tools" && "$WORK/tools/bin/pip" install -q uv; }
  PATH="$PWD/$WORK/tools/bin:$PATH"
fi

SRC="$WORK/src"
if [[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$COMMIT" ]]; then
  rm -rf "$SRC" && mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$REPO"
  git -C "$SRC" sparse-checkout set sglang_omni_mlx/native
  git -C "$SRC" fetch -q --depth 1 --filter=blob:none origin "$COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
fi
NATIVE="$PWD/$SRC/sglang_omni_mlx/native"

# The same steps as the sources' scripts/build_runtime.sh, for the one server Cicada runs.
TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
uv venv -q -p 3.12 --allow-existing "$WORK/venv"
MACOSX_DEPLOYMENT_TARGET="$TARGET" VIRTUAL_ENV="$PWD/$WORK/venv" uv pip install -q \
  --python-platform aarch64-apple-darwin -r "$NATIVE/scripts/build-tools.lock"
MLX="$("$WORK/venv/bin/python" -c 'from importlib.metadata import distribution; print(distribution("mlx").locate_file("mlx"))')"
PATH="$PWD/$WORK/venv/bin:$PATH" cmake -S "$NATIVE" -B "$WORK/cmake" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DMLX_DIR="$MLX/share/cmake/MLX" -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null
PATH="$PWD/$WORK/venv/bin:$PATH" cmake --build "$WORK/cmake" --target qwen3_asr_server

rm -rf "$OUT" && mkdir -p "$OUT/LICENSES"
cp "$WORK/cmake/qwen3_asr_server" "$MLX/lib/libmlx.dylib" "$MLX/lib/mlx.metallib" "$OUT/"
[[ -f "$MLX/lib/libjaccl.dylib" ]] && cp "$MLX/lib/libjaccl.dylib" "$OUT/"
# MLX is found beside the server, not in the build tree.
while read -r rpath; do
  [[ "$rpath" == @loader_path ]] || install_name_tool -delete_rpath "$rpath" "$OUT/qwen3_asr_server"
done < <(otool -l "$OUT/qwen3_asr_server" | awk '/LC_RPATH/ {getline; getline; print $2}')
codesign --force --sign - "$OUT"/*.dylib "$OUT/qwen3_asr_server" >/dev/null 2>&1

cp "$SRC/LICENSE" "$OUT/LICENSES/sglang-omni-Apache-2.0.txt"
cp "$(dirname "$MLX")"/mlx-*.dist-info/licenses/LICENSE "$OUT/LICENSES/mlx-MIT.txt"
cp "$WORK/cmake/_deps/nlohmann_json-src/LICENSE.MIT" "$OUT/LICENSES/nlohmann-json-MIT.txt"
cp "$WORK/cmake/_deps/civetweb-src/LICENSE.md" "$OUT/LICENSES/civetweb-MIT.md"
cp "$WORK/cmake/_deps/pcre2-src/LICENCE" "$OUT/LICENSES/pcre2-BSD.txt" 2>/dev/null \
  || cp "$WORK/cmake/_deps/pcre2-src/LICENCE.md" "$OUT/LICENSES/pcre2-BSD.md"
echo "$COMMIT" > "$OUT/COMMIT"
echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"
