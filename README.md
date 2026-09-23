# spacebreaker

Asteroids-ish arcade shooter. Play: https://starbreaker.guillemus.workers.dev/

Disclaimer: this is AI slop. Made with [Odin](https://odin-lang.org) + [raylib](https://www.raylib.com), compiled to WASM.

## Build

Needs `odin` and `emcc` (emscripten).

```sh
./build_web.sh          # -> build/web
bunx wrangler deploy    # deploy to Cloudflare Workers
```

Native (smoke-test harness): `odin build src/desktop -out:build/desktop/starbreaker`
