package game

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

BLOOM_LEVELS :: 6

Lit_Locs :: struct {
	cam_pos,
	sun_dir,
	sun_col,
	amb_top,
	amb_bot,
	rim,
	flash,
	emissive,
	fog_col,
	fog,
	time,
	lpos,
	lcol: i32,
}

Resources :: struct {
	lit:        rl.Shader,
	lit_mat:    rl.Material,
	ll:         Lit_Locs,
	shield:     rl.Shader,
	shield_mat: rl.Material,
	planet:     rl.Shader,
	planet_mat: rl.Material,
	nebula:     rl.Shader,
	bright:     rl.Shader,
	down:       rl.Shader,
	up:         rl.Shader,
	composite:  rl.Shader,
	rocks:      [N_ROCKS]rl.Mesh,
	molten:     [N_MOLTEN]rl.Mesh,
	chunks:     [N_CHUNKS]rl.Mesh,
	shard:      rl.Mesh,
	drone:      rl.Mesh,
	fighter:    rl.Mesh,
	boss_hull:  rl.Mesh,
	boss_core:  rl.Mesh,
	gun:        rl.Mesh,
	missile:    rl.Mesh,
	sphere:     rl.Mesh,
	tex_glow:   rl.Texture2D,
	tex_soft:   rl.Texture2D,
	tex_smoke:  rl.Texture2D,
	tex_ring:   rl.Texture2D,
	tex_flare:  rl.Texture2D,
	tex_white:  rl.Texture2D,
	font_title: rl.Font,
	font_hud:   rl.Font,
	font_body:  rl.Font,
	rt_scene:   rl.RenderTexture2D,
	rt_neb:     rl.RenderTexture2D,
	rt_bloom:   [BLOOM_LEVELS]rl.RenderTexture2D,
	rt_w, rt_h: i32,
}

res: Resources

// Desktop test harness: when set, the next composited frame is written to this path.
debug_shot: cstring

FONT_TITLE_DATA :: #load("../../assets/Orbitron-Black.ttf")
FONT_HUD_DATA :: #load("../../assets/Orbitron-Bold.ttf")
FONT_BODY_DATA :: #load("../../assets/Rajdhani-SemiBold.ttf")

load_font :: proc(data: []u8, size: i32) -> rl.Font {
	f := rl.LoadFontFromMemory(".ttf", raw_data(data), i32(len(data)), size, nil, 0)
	rl.GenTextureMipmaps(&f.texture)
	rl.SetTextureFilter(f.texture, .TRILINEAR)
	return f
}

loc :: proc(s: rl.Shader, name: cstring) -> i32 {
	return rl.GetShaderLocation(s, name)
}

set_f :: proc(s: rl.Shader, l: i32, v: f32) {
	v := v
	rl.SetShaderValue(s, l, &v, .FLOAT)
}

set_v2 :: proc(s: rl.Shader, l: i32, v: Vec2) {
	v := v
	rl.SetShaderValue(s, l, &v, .VEC2)
}

set_v3 :: proc(s: rl.Shader, l: i32, v: Vec3) {
	v := v
	rl.SetShaderValue(s, l, &v, .VEC3)
}

set_v4 :: proc(s: rl.Shader, l: i32, v: Vec4) {
	v := v
	rl.SetShaderValue(s, l, &v, .VEC4)
}

set_f_name :: proc(s: rl.Shader, name: cstring, v: f32) {
	set_f(s, loc(s, name), v)
}

set_v2_name :: proc(s: rl.Shader, name: cstring, v: Vec2) {
	set_v2(s, loc(s, name), v)
}

set_v3_name :: proc(s: rl.Shader, name: cstring, v: Vec3) {
	set_v3(s, loc(s, name), v)
}

set_v4_name :: proc(s: rl.Shader, name: cstring, v: Vec4) {
	set_v4(s, loc(s, name), v)
}

// ---- procedural sprite textures -------------------------------------------------------------

Tex_Style :: enum {
	Glow,
	Soft,
	Smoke,
	Ring,
	Flare,
}

make_texture :: proc(size: i32, style: Tex_Style) -> rl.Texture2D {
	img := rl.GenImageColor(size, size, rl.BLANK)
	pixels := cast([^]rl.Color)img.data
	for y in 0 ..< size {
		for x in 0 ..< size {
			dx := (f32(x) + 0.5) / f32(size) * 2 - 1
			dy := (f32(y) + 0.5) / f32(size) * 2 - 1
			d2 := dx * dx + dy * dy
			d := math.sqrt(d2)
			a: f32
			switch style {
			case .Glow:
				a = math.exp(-d2 * 5.5) * 0.75 + math.exp(-d2 * 40) * 0.6
			case .Soft:
				a = math.exp(-d2 * 3.2)
			case .Smoke:
				n :=
					noise3(5, {dx, dy, 0.5}, 3) * 0.5 +
					noise3(6, {dx, dy, 1.5}, 6.5) * 0.3 +
					noise3(7, {dx, dy, 2.5}, 13) * 0.2
				falloff := 1 - smooth(0.0, 1.0, d)
				a = clamp01(falloff * falloff * (0.55 + 1.1 * n))
			case .Ring:
				k := (d - 0.8) / 0.085
				a = math.exp(-k * k) + math.exp(-((d - 0.72) / 0.2) * ((d - 0.72) / 0.2)) * 0.25
			case .Flare:
				sx := math.exp(-abs(dy) * 38 - dx * dx * 2.2)
				sy := math.exp(-abs(dx) * 38 - dy * dy * 2.2)
				a = max(sx, sy) * 0.9 + math.exp(-d2 * 30) * 0.8
			}
			a *= 1 - smooth(0.82, 1.0, d)
			pixels[y * size + x] = {255, 255, 255, u8(clamp01(a) * 255)}
		}
	}
	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.GenTextureMipmaps(&tex)
	rl.SetTextureFilter(tex, .TRILINEAR)
	rl.SetTextureWrap(tex, .CLAMP)
	return tex
}

load_resources :: proc() {
	res.lit = rl.LoadShaderFromMemory(LIT_VS, LIT_FS)
	res.lit_mat = rl.LoadMaterialDefault()
	res.lit_mat.shader = res.lit
	s := res.lit
	res.ll = {
		cam_pos  = loc(s, "uCamPos"),
		sun_dir  = loc(s, "uSunDir"),
		sun_col  = loc(s, "uSunCol"),
		amb_top  = loc(s, "uAmbTop"),
		amb_bot  = loc(s, "uAmbBot"),
		rim      = loc(s, "uRimCol"),
		flash    = loc(s, "uFlash"),
		emissive = loc(s, "uEmissive"),
		fog_col  = loc(s, "uFogCol"),
		fog      = loc(s, "uFog"),
		time     = loc(s, "uTime"),
		lpos     = loc(s, "uLPos"),
		lcol     = loc(s, "uLCol"),
	}

	res.shield = rl.LoadShaderFromMemory(LIT_VS, SHIELD_FS)
	res.shield_mat = rl.LoadMaterialDefault()
	res.shield_mat.shader = res.shield
	res.planet = rl.LoadShaderFromMemory(LIT_VS, PLANET_FS)
	res.planet_mat = rl.LoadMaterialDefault()
	res.planet_mat.shader = res.planet
	res.nebula = rl.LoadShaderFromMemory(nil, NEBULA_FS)
	res.bright = rl.LoadShaderFromMemory(nil, BRIGHT_FS)
	res.down = rl.LoadShaderFromMemory(nil, DOWN_FS)
	res.up = rl.LoadShaderFromMemory(nil, UP_FS)
	res.composite = rl.LoadShaderFromMemory(nil, COMPOSITE_FS)

	for i in 0 ..< N_ROCKS {
		res.rocks[i] = make_rock(i64(100 + i * 13), 2, false, 1)
	}
	for i in 0 ..< N_MOLTEN {
		res.molten[i] = make_rock(i64(300 + i * 17), 2, true, 1)
	}
	for i in 0 ..< N_CHUNKS {
		res.chunks[i] = make_rock(i64(500 + i * 7), 0, false, 2.5)
	}
	res.shard = make_shard()
	res.drone = make_drone()
	res.fighter = make_fighter()
	res.boss_hull = make_boss_hull()
	res.boss_core = make_boss_core()
	res.gun = make_gun()
	res.missile = make_missile()
	res.sphere = rl.GenMeshSphere(1, 48, 48)

	res.tex_glow = make_texture(64, .Glow)
	res.tex_soft = make_texture(64, .Soft)
	res.tex_smoke = make_texture(64, .Smoke)
	res.tex_ring = make_texture(128, .Ring)
	res.tex_flare = make_texture(128, .Flare)
	white := rl.GenImageColor(4, 4, rl.WHITE)
	res.tex_white = rl.LoadTextureFromImage(white)
	rl.UnloadImage(white)

	res.font_title = load_font(FONT_TITLE_DATA, 112)
	res.font_hud = load_font(FONT_HUD_DATA, 56)
	res.font_body = load_font(FONT_BODY_DATA, 48)
}

load_rt :: proc(w, h: i32) -> rl.RenderTexture2D {
	rt := rl.LoadRenderTexture(max(w, 1), max(h, 1))
	rl.SetTextureFilter(rt.texture, .BILINEAR)
	rl.SetTextureWrap(rt.texture, .CLAMP)
	return rt
}

ensure_targets :: proc() {
	w := rl.GetScreenWidth()
	h := rl.GetScreenHeight()
	if w == res.rt_w && h == res.rt_h && res.rt_scene.id != 0 {
		return
	}
	if res.rt_scene.id != 0 {
		rl.UnloadRenderTexture(res.rt_scene)
		rl.UnloadRenderTexture(res.rt_neb)
		for rt in res.rt_bloom {
			rl.UnloadRenderTexture(rt)
		}
	}
	res.rt_w = w
	res.rt_h = h
	res.rt_scene = load_rt(w, h)
	res.rt_neb = load_rt(w / 2, h / 2)
	bw := w / 2
	bh := h / 2
	for i in 0 ..< BLOOM_LEVELS {
		res.rt_bloom[i] = load_rt(bw, bh)
		bw = max(bw / 2, 1)
		bh = max(bh / 2, 1)
	}
}

// Draws a render texture (stored upside down) over the current target.
blit :: proc(src: rl.RenderTexture2D, dw, dh: i32) {
	t := src.texture
	rl.DrawTexturePro(
		t,
		{0, 0, f32(t.width), -f32(t.height)},
		{0, 0, f32(dw), f32(dh)},
		{0, 0},
		0,
		rl.WHITE,
	)
}

fullscreen_quad :: proc(dw, dh: i32) {
	rl.DrawTexturePro(res.tex_white, {0, 0, 4, 4}, {0, 0, f32(dw), f32(dh)}, {0, 0}, 0, rl.WHITE)
}

// ---- billboards through the rlgl batch --------------------------------------------------------

vtx :: #force_inline proc(p: Vec3) {
	rlgl.Vertex3f(p.x, p.y, p.z)
}

bb_quad :: proc(p: Vec3, size, rot: f32, c: rl.Color) {
	// never let a sprite right next to the lens swallow the screen
	size := size
	depth := dot(p - g.rcam.position, g.rfwd)
	near := max(depth, 0.05) * 0.3
	if depth < 60 && size > near {
		size = near
	}
	cr := math.cos(rot)
	sr := math.sin(rot)
	r := (g.rright * cr + g.rup * sr) * size
	u := (g.rup * cr - g.rright * sr) * size
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	rlgl.TexCoord2f(0, 0)
	vtx(p - r + u)
	rlgl.TexCoord2f(0, 1)
	vtx(p - r - u)
	rlgl.TexCoord2f(1, 1)
	vtx(p + r - u)
	rlgl.TexCoord2f(1, 0)
	vtx(p + r + u)
}

// Camera-facing quad stretched between a and b.
streak :: proc(a, b: Vec3, width: f32, c: rl.Color) {
	axis := b - a
	l := length(axis)
	if l < 1e-4 {
		bb_quad(a, width, 0, c)
		return
	}
	ad := axis / l
	view := (a + b) * 0.5 - g.rcam.position
	side := norm(cross(ad, view)) * width
	a2 := a - ad * width
	b2 := b + ad * width
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	rlgl.TexCoord2f(0, 0)
	vtx(a2 - side)
	rlgl.TexCoord2f(1, 0)
	vtx(a2 + side)
	rlgl.TexCoord2f(1, 1)
	vtx(b2 + side)
	rlgl.TexCoord2f(0, 1)
	vtx(b2 - side)
}

// Oriented quad (not camera facing) for flat rings.
flat_quad :: proc(p, ax, ay: Vec3, c: rl.Color) {
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	rlgl.TexCoord2f(0, 0)
	vtx(p - ax + ay)
	rlgl.TexCoord2f(0, 1)
	vtx(p - ax - ay)
	rlgl.TexCoord2f(1, 1)
	vtx(p + ax - ay)
	rlgl.TexCoord2f(1, 0)
	vtx(p + ax + ay)
}

begin_sprites :: proc(tex: rl.Texture2D) {
	rlgl.SetTexture(tex.id)
	rlgl.Begin(rlgl.QUADS)
}

end_sprites :: proc() {
	rlgl.End()
	rlgl.SetTexture(0)
}

// ---- lighting -------------------------------------------------------------------------------

frame_lights: [MAX_LIGHTS + 32]Frame_Light
frame_light_n: int

push_frame_light :: proc(pos, col: Vec3, radius: f32) {
	if frame_light_n >= len(frame_lights) {
		return
	}
	intensity := max(col.x, max(col.y, col.z))
	dist := length(pos - g.cam.position)
	frame_lights[frame_light_n] = {pos, col, radius, intensity * radius / (1 + dist * 0.03)}
	frame_light_n += 1
}

upload_lights :: proc() {
	// pick the strongest SHADER_LIGHTS contributors
	for i in 0 ..< min(SHADER_LIGHTS, frame_light_n) {
		best := i
		for j in i + 1 ..< frame_light_n {
			if frame_lights[j].weight > frame_lights[best].weight {
				best = j
			}
		}
		frame_lights[i], frame_lights[best] = frame_lights[best], frame_lights[i]
	}
	lpos: [SHADER_LIGHTS]Vec3
	lcol: [SHADER_LIGHTS]Vec4
	for i in 0 ..< SHADER_LIGHTS {
		if i < frame_light_n {
			l := frame_lights[i]
			lpos[i] = l.pos
			lcol[i] = {l.col.x, l.col.y, l.col.z, max(l.radius, 0.1)}
		} else {
			lpos[i] = {0, -9999, 0}
			lcol[i] = {0, 0, 0, 1}
		}
	}
	rl.SetShaderValueV(res.lit, res.ll.lpos, &lpos, .VEC3, SHADER_LIGHTS)
	rl.SetShaderValueV(res.lit, res.ll.lcol, &lcol, .VEC4, SHADER_LIGHTS)
}

set_lit_frame_uniforms :: proc() {
	s := res.lit
	p := g.pal
	set_v3(s, res.ll.cam_pos, g.rcam.position)
	set_v3(s, res.ll.sun_dir, norm(SUN_DIR))
	set_v3(s, res.ll.sun_col, p.sun)
	set_v3(s, res.ll.amb_top, p.amb_top)
	set_v3(s, res.ll.amb_bot, p.amb_bot)
	set_v3(s, res.ll.rim, p.rim * 0.55)
	set_v3(s, res.ll.fog_col, p.fog)
	set_v2(s, res.ll.fog, {130, 290})
	set_f(s, res.ll.time, g.time)
	upload_lights()
}

draw_lit :: proc(
	mesh: rl.Mesh,
	m: rl.Matrix,
	tint: Vec3 = {1, 1, 1},
	flash: Vec4 = {},
	emissive: Vec3 = {},
	spec: f32 = 1,
) {
	set_v4(res.lit, res.ll.flash, flash)
	set_v3(res.lit, res.ll.emissive, emissive)
	res.lit_mat.maps[0].color = to_color({tint.x, tint.y, tint.z, spec})
	rl.DrawMesh(mesh, res.lit_mat, m)
}

// ---- frame ----------------------------------------------------------------------------------

render :: proc() {
	w := res.rt_w
	h := res.rt_h
	p := g.pal

	// nebula at half resolution
	nw := res.rt_neb.texture.width
	nh := res.rt_neb.texture.height
	rl.BeginTextureMode(res.rt_neb)
	rl.BeginShaderMode(res.nebula)
	ns := res.nebula
	set_v3_name(ns, "uRight", g.rright)
	set_v3_name(ns, "uUp", g.rup)
	set_v3_name(ns, "uFwd", g.rfwd)
	th := math.tan(g.rcam.fovy * math.RAD_PER_DEG * 0.5)
	set_v2_name(ns, "uTan", {th * g.aspect, th})
	set_f_name(ns, "uTime", g.time)
	set_v3_name(ns, "uCol1", p.neb1)
	set_v3_name(ns, "uCol2", p.neb2)
	set_v3_name(ns, "uCol3", p.neb3)
	set_v3_name(ns, "uSunDir", norm(SUN_DIR))
	set_v3_name(ns, "uSunCol", p.sun)
	fullscreen_quad(nw, nh)
	rl.EndShaderMode()
	rl.EndTextureMode()

	// scene
	rl.BeginTextureMode(res.rt_scene)
	rl.ClearBackground(rl.BLACK)
	blit(res.rt_neb, w, h)
	rl.BeginMode3D(g.rcam)
	draw_background()
	set_lit_frame_uniforms()
	draw_world_opaque()
	draw_world_transparent()
	rl.EndMode3D()
	rl.EndTextureMode()

	// bloom
	b0 := res.rt_bloom[0]
	rl.BeginTextureMode(b0)
	rl.BeginShaderMode(res.bright)
	set_v2_name(res.bright, "uTexel", {1 / f32(w), 1 / f32(h)})
	set_f_name(res.bright, "uThreshold", 0.62)
	blit(res.rt_scene, b0.texture.width, b0.texture.height)
	rl.EndShaderMode()
	rl.EndTextureMode()
	for i in 1 ..< BLOOM_LEVELS {
		src := res.rt_bloom[i - 1]
		dst := res.rt_bloom[i]
		rl.BeginTextureMode(dst)
		rl.BeginShaderMode(res.down)
		set_v2_name(res.down, "uTexel", {1 / f32(src.texture.width), 1 / f32(src.texture.height)})
		blit(src, dst.texture.width, dst.texture.height)
		rl.EndShaderMode()
		rl.EndTextureMode()
	}
	for i := BLOOM_LEVELS - 2; i >= 0; i -= 1 {
		src := res.rt_bloom[i + 1]
		dst := res.rt_bloom[i]
		rl.BeginTextureMode(dst)
		rl.BeginShaderMode(res.up)
		set_v2_name(
			res.up,
			"uTexel",
			{0.5 / f32(src.texture.width), 0.5 / f32(src.texture.height)},
		)
		set_f_name(res.up, "uGain", 1.0)
		rl.BeginBlendMode(.ADDITIVE)
		blit(src, dst.texture.width, dst.texture.height)
		rl.EndBlendMode()
		rl.EndShaderMode()
		rl.EndTextureMode()
	}

	// composite + HUD
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	cs := res.composite
	rl.BeginShaderMode(cs)
	set_f_name(cs, "uTime", g.real_time)
	set_f_name(cs, "uBloomStr", 0.85)
	set_f_name(cs, "uAberr", 0.0025 + g.aberr)
	set_f_name(cs, "uDamage", clamp01(g.hurt * 0.75 + low_hull_pulse()))
	set_v4_name(cs, "uFlash", g.flash)
	set_v2_name(cs, "uRes", {f32(w), f32(h)})
	set_f_name(cs, "uGrain", 0.045)
	desat: f32 = 0
	if g.phase == .Paused {
		desat = 0.7
	} else if g.phase == .Game_Over {
		desat = 0.55
	}
	set_f_name(cs, "uDesat", desat)
	rl.SetShaderValueTexture(cs, loc(cs, "uBloom"), res.rt_bloom[0].texture)
	blit(res.rt_scene, w, h)
	rl.EndShaderMode()
	draw_hud()
	if debug_shot != nil {
		rl.TakeScreenshot(debug_shot)
		debug_shot = nil
	}
	rl.EndDrawing()
}

low_hull_pulse :: proc() -> f32 {
	if g.phase != .Playing || g.hull > 30 {
		return 0
	}
	return (0.5 + 0.5 * math.sin(g.real_time * 6)) * 0.35 * (1 - g.hull / 30)
}

// ---- background: stars, sun, planet ----------------------------------------------------------

draw_background :: proc() {
	cam := g.rcam.position
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginBlendMode(.ADDITIVE)

	// stars
	begin_sprites(res.tex_glow)
	for s in stars {
		if dot(s.dir, g.rfwd) < 0.35 {
			continue
		}
		tw := 0.7 + 0.3 * math.sin(g.real_time * s.speed + s.phase)
		bb_quad(cam + s.dir * STAR_DIST, s.size, 0, rgba(s.col, tw))
	}
	end_sprites()

	// sun
	sun_dir := norm(SUN_DIR)
	sun_pos := cam + sun_dir * (STAR_DIST * 0.9)
	begin_sprites(res.tex_soft)
	bb_quad(sun_pos, 380, 0, rgba(g.pal.sun, 0.16))
	bb_quad(sun_pos, 110, 0, rgba(g.pal.sun, 0.55))
	end_sprites()
	begin_sprites(res.tex_glow)
	bb_quad(sun_pos, 60, 0, rgba({1, 1, 1}, 1))
	streak(
		sun_pos - g.rright * 520,
		sun_pos + g.rright * 520,
		7,
		rgba(g.pal.sun * {0.8, 0.9, 1.0}, 0.55),
	)
	end_sprites()
	begin_sprites(res.tex_flare)
	bb_quad(sun_pos, 220, g.real_time * 0.02, rgba(g.pal.sun, 0.5))
	end_sprites()

	// planet halo
	planet_dir := norm(PLANET_DIR)
	planet_pos := cam + planet_dir * 1000
	planet_r := f32(330)
	begin_sprites(res.tex_soft)
	bb_quad(planet_pos, planet_r * 1.45, 0, rgba(g.pal.atmo, 0.35))
	end_sprites()
	rl.EndBlendMode()
	rlgl.DrawRenderBatchActive()

	// planet body
	rlgl.EnableDepthTest()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
	ps := res.planet
	set_v3_name(ps, "uCamPos", cam)
	set_v3_name(ps, "uSunDir", sun_dir)
	set_v3_name(ps, "uColA", g.pal.planet_a)
	set_v3_name(ps, "uColB", g.pal.planet_b)
	set_v3_name(ps, "uAtmo", g.pal.atmo)
	set_f_name(ps, "uTime", g.time)
	tilt := quat_axis(norm(Vec3{0.2, 0, 1}), 0.35)
	rl.DrawMesh(res.sphere, res.planet_mat, transform_q(planet_pos, tilt, planet_r))
}

// ---- world ----------------------------------------------------------------------------------

entity_transform :: proc(e: ^Entity, scale: f32) -> rl.Matrix {
	x, y, z := look_basis(e.fwd, {0, 1, 0})
	if e.kind == .Drone {
		// barrel roll
		c := math.cos(e.phase * 1.3)
		s := math.sin(e.phase * 1.3)
		x, y = x * c + y * s, y * c - x * s
	}
	return transform(e.pos, x * scale, y * scale, z * scale)
}

draw_world_opaque :: proc() {
	rlgl.EnableDepthTest()
	rlgl.EnableDepthMask()
	rlgl.DisableBackfaceCulling()

	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		flash := Vec4{1, 1, 1, e.flash * 0.85}
		switch e.kind {
		case .Asteroid:
			mesh := res.rocks[e.mesh % N_ROCKS]
			if e.molten {
				mesh = res.molten[e.mesh % N_MOLTEN]
			}
			heat := Vec3{1.0, 0.32, 0.06} * (e.hot * 0.9)
			draw_lit(mesh, transform_q(e.pos, e.rot, e.radius), {1, 1, 1}, flash, heat, 0.4)
		case .Drone:
			s := 1 - e.warp * e.warp
			draw_lit(
				res.drone,
				entity_transform(e, e.radius * 0.8 * s),
				{1, 1, 1},
				flash + Vec4{0, 0, 0, e.warp},
				{},
				1,
			)
		case .Fighter:
			s := 1 - e.warp * e.warp
			charge := Vec3{1.0, 0.25, 0.1} * (e.charge * e.charge * 0.35)
			draw_lit(
				res.fighter,
				entity_transform(e, e.radius * 0.62 * s),
				{1, 1, 1},
				flash + Vec4{0, 0, 0, e.warp},
				charge,
				1,
			)
		case .Boss:
			draw_boss(e, flash)
		case .Bolt, .Nova:
		// drawn as sprites
		}
	}

	// debris
	for i in 0 ..< g.debris_n {
		d := &g.debris[i]
		fade_s := clamp01(d.life / 0.6)
		s := d.scale * fade_s
		heat := Vec3{1.0, 0.4, 0.1} * (d.hot * 0.8)
		if d.metal {
			draw_lit(res.shard, transform_q(d.pos, d.rot, s), {1, 1, 1}, {}, heat, 1)
		} else {
			draw_lit(
				res.chunks[d.mesh % N_CHUNKS],
				transform_q(d.pos, d.rot, s),
				d.tint,
				{},
				heat,
				0.3,
			)
		}
	}

	// missiles
	for i in 0 ..< g.missile_n {
		m := &g.missiles[i]
		x, y, z := look_basis(m.vel, {0, 1, 0})
		roll := m.age * 9
		c := math.cos(roll)
		s := math.sin(roll)
		x, y = x * c + y * s, y * c - x * s
		draw_lit(res.missile, transform(m.pos, x * 1.3, y * 1.3, z * 1.3), {1, 1, 1}, {}, {}, 1)
	}

	draw_guns()
}

draw_boss :: proc(e: ^Entity, flash: Vec4) {
	x, y, z := look_basis(e.fwd, {0, 1, 0})
	spin := e.age * 0.35
	c := math.cos(spin)
	s := math.sin(spin)
	rx := x * c + y * s
	ry := y * c - x * s
	scale := e.radius / 9.5 * (1 - e.warp * e.warp)
	f := flash + Vec4{0, 0, 0, e.warp}
	draw_lit(
		res.boss_hull,
		transform(e.pos, rx * scale, ry * scale, z * scale),
		{1, 1, 1},
		f,
		{},
		1,
	)
	pulse := 0.5 + 0.5 * math.sin(e.age * 5)
	core_glow := Vec3{1.0, 0.15, 0.2} * (0.25 + pulse * 0.35 + e.charge * 0.6)
	cs := scale * 3.4 * (1 + 0.06 * pulse)
	spin2 := -e.age * 0.9
	c2 := math.cos(spin2)
	s2 := math.sin(spin2)
	draw_lit(
		res.boss_core,
		transform(e.pos + z * 0.5 * scale, (x * c2 + z * s2) * cs, y * cs, (z * c2 - x * s2) * cs),
		{1, 1, 1},
		f,
		core_glow,
		1,
	)
}

gun_transform :: proc(side: int) -> (rl.Matrix, Vec3, Vec3) {
	sgn: f32 = -1
	if side == 1 {
		sgn = 1
	}
	base := g.rcam.position + g.rright * (sgn * 0.62) - g.rup * 0.5 + g.rfwd * 1.05
	d := norm(g.aim_point - base)
	x, y, z := look_basis(d, g.rup)
	base -= z * (g.recoil[side] * 0.1)
	sc := f32(0.5)
	tip := base + z * (1.6 * sc)
	return transform(base, x * sc, y * sc, z * sc), tip, z
}

draw_guns :: proc() {
	if g.phase == .Title || g.phase == .Game_Over || g.dying {
		return
	}
	heat := g.heat * g.heat
	glow := Vec3{1.0, 0.3, 0.05} * heat * 0.3
	if g.overheated {
		glow = Vec3{1.0, 0.25, 0.05} * (0.3 + 0.1 * math.sin(g.real_time * 20))
	}
	for side in 0 ..< 2 {
		m, _, _ := gun_transform(side)
		draw_lit(res.gun, m, {1, 1, 1}, {}, glow, 1)
	}
}

draw_world_transparent :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()

	// shield bubble
	if g.shield_hit > 0.01 ||
	   (g.phase == .Playing && g.shield > 0 && g.shield_delay > 0 && g.shield_delay < 0.4) {
		ss := res.shield
		set_v3_name(ss, "uCamPos", g.rcam.position)
		set_v3_name(ss, "uHitDir", g.shield_hit_dir)
		set_f_name(ss, "uHit", g.shield_hit)
		set_f_name(ss, "uIdle", 0.3)
		set_f_name(ss, "uTime", g.time)
		set_v3_name(ss, "uShieldCol", Vec3{0.35, 0.8, 1.0} * 0.8)
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawMesh(
			res.sphere,
			res.shield_mat,
			transform(g.rcam.position, {3, 0, 0}, {0, 3, 0}, {0, 0, 3}),
		)
		rl.EndBlendMode()
	}

	// smoke (alpha blended, drawn first)
	rl.BeginBlendMode(.ALPHA)
	begin_sprites(res.tex_smoke)
	for i in 0 ..< g.part_n {
		p := &g.parts[i]
		if p.kind != .Smoke {
			continue
		}
		t := 1 - p.life / p.max_life
		c := lerp4(p.c0, p.c1, t)
		bb_quad(p.pos, lerp(p.s0, p.s1, ease_out(t)), p.rot, to_color(c))
	}
	end_sprites()
	rl.EndBlendMode()

	rl.BeginBlendMode(.ADDITIVE)
	draw_particles_additive()
	draw_entity_glows()
	draw_bullets()
	draw_missile_fx()
	draw_muzzle_flashes()
	rl.EndBlendMode()

	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}

draw_particles_additive :: proc() {
	begin_sprites(res.tex_glow)
	for i in 0 ..< g.part_n {
		p := &g.parts[i]
		t := 1 - p.life / p.max_life
		c := to_color(lerp4(p.c0, p.c1, t))
		size := lerp(p.s0, p.s1, ease_out(t))
		switch p.kind {
		case .Glow:
			bb_quad(p.pos, size, p.rot, c)
		case .Ember:
			tw := 0.6 + 0.4 * math.sin(p.rot * 7 + g.time * 18)
			bb_quad(p.pos, size, 0, fade(c, tw))
		case .Spark:
			tail := p.pos - p.vel * p.stretch
			streak(tail, p.pos, size, c)
		case .Smoke, .Ring, .Flare:
		}
	}
	end_sprites()

	begin_sprites(res.tex_ring)
	for i in 0 ..< g.part_n {
		p := &g.parts[i]
		if p.kind != .Ring {
			continue
		}
		t := 1 - p.life / p.max_life
		bb_quad(p.pos, lerp(p.s0, p.s1, ease_out(t)), p.rot, to_color(lerp4(p.c0, p.c1, t)))
	}
	end_sprites()

	begin_sprites(res.tex_flare)
	for i in 0 ..< g.part_n {
		p := &g.parts[i]
		if p.kind != .Flare {
			continue
		}
		t := 1 - p.life / p.max_life
		bb_quad(p.pos, lerp(p.s0, p.s1, ease_out(t)), p.rot, to_color(lerp4(p.c0, p.c1, t)))
	}
	end_sprites()
}

draw_entity_glows :: proc() {
	begin_sprites(res.tex_glow)
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		x, y, z := look_basis(e.fwd, {0, 1, 0})
		switch e.kind {
		case .Asteroid:
			if e.molten {
				bb_quad(
					e.pos,
					e.radius * 2.2,
					0,
					rgba({1.0, 0.35, 0.08}, 0.18 + 0.05 * math.sin(e.age * 3)),
				)
			}
		case .Drone:
			s := e.radius * 0.8
			tail := e.pos - z * (1.25 * s)
			flick := 0.8 + 0.2 * math.sin(g.time * 40 + e.phase)
			bb_quad(tail, 1.4 * s * flick, 0, rgba({1.0, 0.3, 0.85}, 0.9))
			streak(tail, tail - z * (3 * s), 0.5 * s, rgba({1.0, 0.25, 0.8}, 0.6))
			bb_quad(e.pos + z * (1.3 * s), 0.6 * s, 0, rgba({1.0, 0.6, 1.0}, 0.9))
			if length(e.pos) < 50 {
				blink := f32(0)
				if math.sin(g.time * 22) > 0 {
					blink = 1
				}
				bb_quad(e.pos, 3.2 * s, 0, rgba({1.0, 0.1, 0.3}, 0.5 * blink))
			}
		case .Fighter:
			s := e.radius * 0.62
			flick := 0.85 + 0.15 * math.sin(g.time * 50 + e.phase)
			for sx in ([2]f32{-0.8, 0.8}) {
				ep := e.pos + (x * sx - y * 0.07 - z * 1.6) * s
				bb_quad(ep, 1.1 * s * flick, 0, rgba({1.0, 0.55, 0.2}, 0.95))
				streak(
					ep,
					ep - z * (4.5 * s) - e.vel * 0.05,
					0.45 * s,
					rgba({1.0, 0.4, 0.1}, 0.55),
				)
			}
			for sx in ([2]f32{-2.6, 2.6}) {
				blink := f32(0.15)
				if math.sin(g.time * 6 + sx) > 0.6 {
					blink = 1
				}
				bb_quad(
					e.pos + (x * sx - y * 0.1 - z * 1.2) * s,
					0.5 * s,
					0,
					rgba({1.0, 0.2, 0.2}, blink),
				)
			}
			if e.charge > 0 {
				np := e.pos + z * (3.1 * s)
				bb_quad(
					np,
					(0.6 + e.charge * 2.8) * s,
					g.time * 5,
					rgba({1.0, 0.3, 0.2}, 0.4 + e.charge * 0.6),
				)
				bb_quad(np, (0.3 + e.charge * 1.1) * s, 0, rgba({1.0, 0.9, 0.8}, e.charge))
			}
		case .Boss:
			draw_boss_glows(e, x, y, z)
		case .Bolt:
			d := norm(e.vel)
			pulse := 0.85 + 0.15 * math.sin(e.age * 30)
			streak(e.pos - d * 5, e.pos, 0.9, rgba({1.0, 0.15, 0.35}, 0.7))
			bb_quad(e.pos, 2.6 * pulse, 0, rgba({1.0, 0.2, 0.4}, 0.8))
			bb_quad(e.pos, 1.0, 0, rgba({1.0, 0.85, 0.9}, 1))
		case .Nova:
			pulse := 0.8 + 0.2 * math.sin(e.age * 12)
			bb_quad(e.pos, e.radius * 3.4 * pulse, e.age, rgba({0.9, 0.1, 0.6}, 0.55))
			bb_quad(e.pos, e.radius * 1.7, -e.age * 2, rgba({1.0, 0.5, 0.9}, 0.9))
			bb_quad(e.pos, e.radius * 0.8, 0, rgba({1, 1, 1}, 1))
		}
		// warp-in flare
		if e.warp > 0 {
			bb_quad(e.pos, e.radius * (1 + 6 * e.warp), 0, rgba({0.6, 0.85, 1.0}, e.warp))
		}
	}
	end_sprites()

	begin_sprites(res.tex_flare)
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		#partial switch e.kind {
		case .Bolt:
			bb_quad(e.pos, 4.5, e.age * 4, rgba({1.0, 0.3, 0.5}, 0.7))
		case .Nova:
			bb_quad(e.pos, e.radius * 5, e.age * 1.5, rgba({1.0, 0.4, 0.8}, 0.8))
		case .Boss:
			if e.charge > 0 {
				_, _, z := look_basis(e.fwd, {0, 1, 0})
				bb_quad(
					e.pos + z * 4,
					10 + e.charge * 30,
					e.age,
					rgba({1.0, 0.25, 0.35}, e.charge),
				)
			}
		}
		if e.warp > 0 {
			bb_quad(e.pos, e.radius * (2 + 10 * e.warp), e.warp * 3, rgba({0.7, 0.9, 1.0}, e.warp))
		}
	}
	end_sprites()
}

draw_boss_glows :: proc(e: ^Entity, x, y, z: Vec3) {
	scale := e.radius / 9.5 * (1 - e.warp * e.warp)
	pulse := 0.5 + 0.5 * math.sin(e.age * 5)
	bb_quad(
		e.pos + z * (1.5 * scale),
		(6 + pulse * 2 + e.charge * 6) * scale,
		0,
		rgba({1.0, 0.15, 0.25}, 0.55),
	)
	for s in 0 ..< 4 {
		ang := f32(s) / 4 * math.TAU + math.PI * 0.25
		d := x * math.cos(ang) + y * math.sin(ang)
		ep := e.pos + (d * 6.2 - z * 3.8) * scale
		bb_quad(ep, 2.2 * scale, 0, rgba({1.0, 0.5, 0.25}, 0.9))
		streak(ep, ep - z * (9 * scale), 1.1 * scale, rgba({1.0, 0.35, 0.15}, 0.5))
	}
}

draw_bullets :: proc() {
	begin_sprites(res.tex_glow)
	for i in 0 ..< g.bullet_n {
		b := &g.bullets[i]
		d := norm(b.vel)
		travelled := length(b.pos - b.origin)
		tail := b.pos - d * min(9, travelled)
		col := Vec3{0.25, 0.85, 1.0}
		if b.side == 1 {
			col = Vec3{0.45, 0.6, 1.0}
		}
		// thin near the lens, full width once out in the field
		k := clamp(length(b.pos - g.rcam.position) / 40, 0.1, 1)
		streak(tail, b.pos, 0.55 * k, rgba(col, 0.75))
		streak(tail + d * (min(9, travelled) * 0.4), b.pos, 0.16 * k, rgba({1, 1, 1}, 1))
		bb_quad(b.pos, 1.3 * k, 0, rgba(col, 0.9))
	}
	end_sprites()
}

draw_missile_fx :: proc() {
	begin_sprites(res.tex_glow)
	for i in 0 ..< g.missile_n {
		m := &g.missiles[i]
		d := norm(m.vel)
		// ribbon trail
		n := m.trail_n
		if n >= 2 {
			for k in 0 ..< n - 1 {
				a := m.trail[k]
				b := m.trail[k + 1]
				t := f32(k) / f32(n - 1)
				streak(
					a,
					b,
					0.15 + 0.35 * t,
					rgba({1.0, 0.55 + 0.3 * t, 0.25 + 0.5 * t}, 0.08 + 0.4 * t * t),
				)
			}
			streak(m.trail[n - 1], m.pos, 0.5, rgba({1.0, 0.85, 0.6}, 0.5))
		}
		flick := 0.75 + 0.25 * math.sin(m.age * 60 + m.seed)
		tail := m.pos - d * 0.9
		streak(tail - d * (2.4 * flick), tail, 0.45, rgba({1.0, 0.5, 0.15}, 0.95))
		streak(tail - d * (1.2 * flick), tail, 0.18, rgba({1, 1, 0.9}, 1))
		bb_quad(tail, 1.6 * flick, 0, rgba({1.0, 0.6, 0.25}, 0.9))
	}
	end_sprites()
	begin_sprites(res.tex_flare)
	for i in 0 ..< g.missile_n {
		m := &g.missiles[i]
		bb_quad(m.pos - norm(m.vel) * 0.9, 2.4, m.age * 3, rgba({1.0, 0.7, 0.4}, 0.6))
	}
	end_sprites()
}

draw_muzzle_flashes :: proc() {
	if g.phase == .Title || g.phase == .Game_Over || g.dying {
		return
	}
	begin_sprites(res.tex_flare)
	for side in 0 ..< 2 {
		if g.muzzle[side] <= 0 {
			continue
		}
		_, tip, z := gun_transform(side)
		k := g.muzzle[side]
		bb_quad(tip + z * 0.12, 0.2 * k + 0.05, g.time * 13 + f32(side), rgba({0.6, 0.95, 1.0}, k))
	}
	end_sprites()
	begin_sprites(res.tex_glow)
	for side in 0 ..< 2 {
		_, tip, z := gun_transform(side)
		k := g.muzzle[side]
		coil := 0.2 + g.heat * 0.4
		bb_quad(tip - z * 0.24, 0.05 + coil * 0.04, 0, rgba({0.4, 0.9, 1.0}, coil))
		if k <= 0 {
			continue
		}
		bb_quad(tip + z * 0.1, 0.16 * k + 0.04, 0, rgba({0.5, 0.9, 1.0}, k))
		streak(tip, tip + z * (0.9 * k), 0.045 * k, rgba({0.8, 1.0, 1.0}, k))
	}
	end_sprites()
}
