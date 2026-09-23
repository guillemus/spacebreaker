package game

// Sound ids shared with src/web/sfx.js.
SFX :: enum i32 {
	Shoot,
	Hit,
	Explode_S,
	Explode_L,
	Missile,
	Lock,
	Ammo,
	Hull_Hit,
	Shield_Hit,
	Wave,
	Clear,
	Boss,
	Enemy_Fire,
	Overheat,
	Game_Over,
	UI,
	Warp,
	Empty,
	Charge,
	Pop,
	Mega,
}

when ODIN_OS == .JS {
	// Resolved at link time by emscripten from src/web/bridge.js (same trick as the raylib bindings).
	foreign import js_bridge "env.o"

	@(default_calling_convention = "c")
	foreign js_bridge {
		js_sfx :: proc(id: i32, vol, pan, pitch: f32) ---
		js_music :: proc(intensity: f32) ---
		js_set_muted :: proc(muted: i32) ---
		js_get_best :: proc() -> i32 ---
		js_set_best :: proc(value: i32) ---
		js_get_start_wave :: proc() -> i32 ---
	}
} else {
	js_sfx :: proc(id: i32, vol, pan, pitch: f32) {}
	js_music :: proc(intensity: f32) {}
	js_set_muted :: proc(muted: i32) {}
	js_get_best :: proc() -> i32 {
		return 0
	}
	js_set_best :: proc(value: i32) {}
	js_get_start_wave :: proc() -> i32 {
		return 1
	}
}

sfx :: proc(s: SFX, vol: f32 = 1, pan: f32 = 0, pitch: f32 = 1) {
	js_sfx(i32(s), vol, clamp(pan, -1, 1), pitch)
}

// Positional one-shot: pans by the listener's right vector, fades with distance.
sfx_at :: proc(s: SFX, pos: Vec3, vol: f32 = 1, pitch: f32 = 1) {
	dist := length(pos)
	pan: f32 = 0
	if dist > 0.01 {
		pan = dot(pos / dist, g.right) * 0.8
	}
	sfx(s, vol / (1 + dist * 0.012), pan, pitch)
}

music_intensity :: proc(v: f32) {
	js_music(clamp01(v))
}

set_muted :: proc(m: bool) {
	g.muted = m
	v: i32 = 0
	if m {
		v = 1
	}
	js_set_muted(v)
}

load_best :: proc() -> int {
	return int(js_get_best())
}

save_best :: proc(v: int) {
	js_set_best(i32(v))
}
