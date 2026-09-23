#!/usr/bin/env bash
# Builds STARBREAKER for the web: Odin (js_wasm32 obj) + raylib (emscripten) -> build/web
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$(dirname "$(command -v emcc)"):$PATH"

RAYLIB_VERSION=5.5
DEPS=build/deps
OUT=build/web
RAYLIB_SRC="$DEPS/raylib-$RAYLIB_VERSION/src"
mkdir -p "$DEPS" "$OUT"

# Homebrew Odin ships the raylib bindings but not the web archive, so build it once.
if [[ ! -f "$RAYLIB_SRC/libraylib.a" ]]; then
	if [[ ! -d "$DEPS/raylib-$RAYLIB_VERSION" ]]; then
		curl -fsSL "https://codeload.github.com/raysan5/raylib/tar.gz/refs/tags/$RAYLIB_VERSION" -o "$DEPS/raylib.tar.gz"
		tar -xzf "$DEPS/raylib.tar.gz" -C "$DEPS"
	fi
	emmake make -C "$RAYLIB_SRC" PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES2 -j8
fi

ODIN_FLAGS=(-target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -vet -strict-style)
if [[ "${DEBUG:-0}" == "1" ]]; then
	ODIN_FLAGS+=(-debug)
	EMCC_OPT=(-O0 -sASSERTIONS=1)
else
	ODIN_FLAGS+=(-o:speed)
	EMCC_OPT=(-O2)
fi

odin build src/web "${ODIN_FLAGS[@]}" -out:"$OUT/game.wasm.o"

cp "$(odin root)/core/sys/wasm/js/odin.js" "$OUT/odin.js"
cp src/web/sfx.js "$OUT/sfx.js"

emcc "$OUT/game.wasm.o" "$RAYLIB_SRC/libraylib.a" \
	-o "$OUT/index.html" \
	"${EMCC_OPT[@]}" \
	-sUSE_GLFW=3 \
	-sGL_ENABLE_GET_PROC_ADDRESS \
	-sALLOW_MEMORY_GROWTH=1 \
	-sINITIAL_MEMORY=67108864 \
	-sSTACK_SIZE=2097152 \
	-sERROR_ON_UNDEFINED_SYMBOLS=0 \
	-sWARN_ON_UNDEFINED_SYMBOLS=0 \
	-sEXPORTED_FUNCTIONS=_main_start,_main_update,_main_blur \
	--js-library src/web/bridge.js \
	--shell-file src/web/index.html

rm -f "$OUT/game.wasm.o"
echo "built $OUT/index.html"
