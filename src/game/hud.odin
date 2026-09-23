package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

HUD_CYAN :: rl.Color{120, 232, 255, 255}
HUD_WHITE :: rl.Color{236, 248, 255, 255}
HUD_ORANGE :: rl.Color{255, 172, 64, 255}
HUD_RED :: rl.Color{255, 64, 88, 255}
HUD_GREEN :: rl.Color{140, 255, 170, 255}

SECTOR_NAMES := [?]cstring{"VIOLET RIFT", "CRIMSON VEIL", "EMERALD DRIFT", "DEEP AZURE", "SOLAR STORM", "PINK NOVA"}

// ---- helpers --------------------------------------------------------------------------------

ui_scale :: proc() -> f32 {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return clamp(min(sh / 900, sw / 1400), 0.55, 2)
}

// World position to screen pixels through the render camera.
project :: proc(p: Vec3) -> (Vec2, bool) {
	rel := p - g.rcam.position
	z := dot(rel, g.rfwd)
	if z < 0.05 {
		return {}, false
	}
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	x := dot(rel, g.rright) / (z * g.tan_half * g.aspect)
	y := dot(rel, g.rup) / (z * g.tan_half)
	return {(x * 0.5 + 0.5) * sw, (0.5 - y * 0.5) * sh}, true
}

projected_radius :: proc(p: Vec3, r: f32) -> f32 {
	z := max(dot(p - g.rcam.position, g.rfwd), 0.1)
	return r / (z * g.tan_half) * f32(rl.GetScreenHeight()) * 0.5
}

length2 :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

rot2 :: proc(v: Vec2, a: f32) -> Vec2 {
	c := math.cos(a)
	s := math.sin(a)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

lerp_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	return {
		u8(lerp(f32(a.r), f32(b.r), t)),
		u8(lerp(f32(a.g), f32(b.g), t)),
		u8(lerp(f32(a.b), f32(b.b), t)),
		u8(lerp(f32(a.a), f32(b.a), t)),
	}
}

kind_color :: proc(k: Entity_Kind) -> rl.Color {
	switch k {
	case .Asteroid:
		return {255, 200, 150, 255}
	case .Drone:
		return {255, 90, 220, 255}
	case .Fighter:
		return {255, 150, 60, 255}
	case .Boss:
		return {255, 60, 80, 255}
	case .Bolt, .Nova:
		return {255, 80, 150, 255}
	}
	return rl.WHITE
}

// align: 0 = left, 0.5 = centre, 1 = right. pos.y is the top of the line.
text :: proc(font: rl.Font, s: cstring, pos: Vec2, size: f32, col: rl.Color, align: f32 = 0, spacing: f32 = 0) {
	if col.a == 0 {
		return
	}
	p := pos
	if align != 0 {
		m := rl.MeasureTextEx(font, s, size, spacing)
		p.x -= m.x * align
	}
	rl.DrawTextEx(font, s, p, size, spacing, col)
}

glow_text :: proc(font: rl.Font, s: cstring, pos: Vec2, size: f32, col: rl.Color, align: f32 = 0, spacing: f32 = 0, glow: f32 = 1) {
	if col.a == 0 {
		return
	}
	p := pos
	if align != 0 {
		m := rl.MeasureTextEx(font, s, size, spacing)
		p.x -= m.x * align
	}
	if glow > 0 {
		rl.BeginBlendMode(.ADDITIVE)
		r1 := max(size * 0.04, 1)
		r2 := size * 0.11
		c1 := fade(col, 0.2 * glow)
		c2 := fade(col, 0.07 * glow)
		for k in 0 ..< 8 {
			a := f32(k) / 8 * math.TAU
			d := Vec2{math.cos(a), math.sin(a)}
			rl.DrawTextEx(font, s, p + d * r2, size, spacing, c2)
			rl.DrawTextEx(font, s, p + d * r1, size, spacing, c1)
		}
		rl.EndBlendMode()
	}
	rl.DrawTextEx(font, s, p, size, spacing, col)
}

// Largest font size (up to max_size) that keeps s within max_w pixels.
fit_size :: proc(font: rl.Font, s: cstring, max_size, spacing_k, max_w: f32) -> f32 {
	m := rl.MeasureTextEx(font, s, 100, 100 * spacing_k)
	if m.x <= 0 {
		return max_size
	}
	return min(max_size, max_w / m.x * 100)
}

sprite2 :: proc(tex: rl.Texture2D, c: Vec2, size: f32, col: rl.Color, rot: f32 = 0) {
	src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
	rl.DrawTexturePro(tex, src, {c.x, c.y, size * 2, size * 2}, {size, size}, rot, col)
}

// Slanted bar segment.
para :: proc(x, y, w, h, slant: f32, col: rl.Color) {
	tl := Vec2{x + slant, y}
	tr := Vec2{x + w + slant, y}
	bl := Vec2{x, y + h}
	br := Vec2{x + w, y + h}
	rl.DrawTriangle(tl, bl, br, col)
	rl.DrawTriangle(tl, br, tr, col)
}

seg_bar :: proc(x, y, w, h, frac: f32, col: rl.Color, u: f32) {
	slant := h * 0.9
	para(x, y, w, h, slant, {8, 18, 36, 170})
	f := clamp01(frac)
	if f > 0 {
		rl.BeginBlendMode(.ADDITIVE)
		para(x - 2 * u, y - h * 0.6, w * f + 4 * u, h * 2.2, slant, fade(col, 0.12))
		rl.EndBlendMode()
		para(x, y, w * f, h, slant, col)
	}
	gap := rl.Color{4, 8, 18, 220}
	segs := 20
	for k in 1 ..< segs {
		sx := x + w * f32(k) / f32(segs)
		rl.DrawLineEx({sx + slant, y}, {sx, y + h}, 1.6 * u, gap)
	}
}

// ---- entry ----------------------------------------------------------------------------------

draw_hud :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	u := ui_scale()
	draw_lens_flare(u)
	switch g.phase {
	case .Title:
		draw_title(u)
	case .Playing:
		if !g.dying {
			draw_play_hud(u)
		}
		draw_floaters(u)
		if !g.dying {
			draw_crosshair(u)
		}
	case .Paused:
		draw_play_hud(u)
		draw_floaters(u)
		draw_pause(u)
	case .Game_Over:
		draw_game_over(u)
	}
	if g.phase != .Playing {
		draw_cursor(u)
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}

draw_play_hud :: proc(u: f32) {
	// soft dark vignettes so the gauges read over bright explosions and the guns
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	sprite2(res.tex_soft, {150 * u, sh - 50 * u}, 260 * u, {0, 0, 0, 150})
	sprite2(res.tex_soft, {sw - 110 * u, sh - 50 * u}, 200 * u, {0, 0, 0, 150})
	draw_frame_corners(u)
	draw_turn_edges(u)
	draw_threats(u)
	draw_offscreen(u)
	draw_lock(u)
	draw_damage_marks(u)
	draw_status(u)
	draw_missiles(u)
	draw_score(u)
	draw_wave_info(u)
	draw_boss_bar(u)
	draw_radar(u)
	draw_wave_banner(u)
}

// ---- in-play widgets ------------------------------------------------------------------------

draw_frame_corners :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	m := 14 * u
	l := 36 * u
	col := rl.Color{120, 232, 255, 70}
	t := 1.5 * u
	rl.DrawLineEx({m, m}, {m + l, m}, t, col)
	rl.DrawLineEx({m, m}, {m, m + l}, t, col)
	rl.DrawLineEx({sw - m, m}, {sw - m - l, m}, t, col)
	rl.DrawLineEx({sw - m, m}, {sw - m, m + l}, t, col)
	rl.DrawLineEx({m, sh - m}, {m + l, sh - m}, t, col)
	rl.DrawLineEx({m, sh - m}, {m, sh - m - l}, t, col)
	rl.DrawLineEx({sw - m, sh - m}, {sw - m - l, sh - m}, t, col)
	rl.DrawLineEx({sw - m, sh - m}, {sw - m, sh - m - l}, t, col)
}

// Shows where the turn zones start and pulses chevrons while turning.
draw_turn_edges :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	for sgn in ([2]f32{-1, 1}) {
		x := sw * 0.5 + sgn * TURN_DEADZONE * sw * 0.5
		rl.DrawLineEx({x, 0}, {x, 12 * u}, 1.5 * u, {120, 232, 255, 70})
		rl.DrawLineEx({x, sh}, {x, sh - 12 * u}, 1.5 * u, {120, 232, 255, 70})
	}
	nx := clamp(g.mouse.x / sw * 2 - 1, -1, 1)
	t := clamp01((abs(nx) - TURN_DEADZONE) / (1 - TURN_DEADZONE))
	if t <= 0 || !rl.IsCursorOnScreen() {
		return
	}
	w := i32(sw * 0.14)
	glow := rl.Color{120, 232, 255, u8(t * 55)}
	clear := rl.Color{120, 232, 255, 0}
	sgn: f32 = 1
	if nx < 0 {
		sgn = -1
		rl.DrawRectangleGradientH(0, 0, w, i32(sh), glow, clear)
	} else {
		rl.DrawRectangleGradientH(i32(sw) - w, 0, w, i32(sh), clear, glow)
	}
	s := 11 * u
	cy := sh * 0.5
	for k in 0 ..< 3 {
		cx := sw * 0.5 + sgn * (sw * 0.5 - 30 * u - f32(k) * 15 * u)
		wave := 0.5 + 0.5 * math.sin(g.real_time * 11 + f32(k) * 1.3)
		col := fade(HUD_CYAN, t * (0.25 + 0.75 * wave))
		rl.DrawLineEx({cx - sgn * s * 0.5, cy - s}, {cx + sgn * s * 0.5, cy}, 2.5 * u, col)
		rl.DrawLineEx({cx + sgn * s * 0.5, cy}, {cx - sgn * s * 0.5, cy + s}, 2.5 * u, col)
	}
}

draw_crosshair :: proc(u: f32) {
	c := g.mouse
	col := HUD_CYAN
	if g.aim_hit != 0 {
		col = HUD_ORANGE
	}
	if g.overheated {
		col = HUD_RED
	}
	gap := (6 + g.spread * 9) * u
	arm := 8 * u
	for k in 0 ..< 4 {
		a := f32(k) * math.PI * 0.5
		d := Vec2{math.cos(a), math.sin(a)}
		rl.DrawLineEx(c + d * gap, c + d * (gap + arm), 2 * u, col)
	}
	rl.DrawCircleV(c, 1.8 * u, col)

	// heat gauge, left arc
	r0 := 24 * u
	r1 := 27.5 * u
	rl.DrawRing(c, r0, r1, 110, 250, 24, {120, 232, 255, 40})
	heat := clamp01(g.heat)
	if heat > 0.001 {
		hc := lerp_color(HUD_CYAN, HUD_ORANGE, smooth(0.3, 0.75, heat))
		if heat > 0.85 {
			hc = HUD_RED
		}
		if g.overheated {
			hc = fade(HUD_RED, 0.5 + 0.5 * math.sin(g.real_time * 24))
		}
		rl.DrawRing(c, r0, r1, 110, 110 + 140 * heat, 24, hc)
	}

	// missile pips, right arc
	for k in 0 ..< MAX_AMMO {
		a1 := 63 - f32(k) * 26
		a0 := a1 - 22
		rl.DrawRing(c, r0, r1, a0, a1, 6, {255, 172, 64, 40})
		if k < g.ammo {
			rl.DrawRing(c, r0, r1, a0, a1, 6, HUD_ORANGE)
		} else if k == g.ammo && g.ammo_charge > 0 {
			rl.DrawRing(c, r0, r1, a1 - 22 * clamp01(g.ammo_charge), a1, 6, {255, 172, 64, 120})
		}
	}

	if g.hitmarker > 0 {
		h := g.hitmarker
		for k in 0 ..< 4 {
			a := f32(k) * math.PI * 0.5 + math.PI * 0.25
			d := Vec2{math.cos(a), math.sin(a)}
			rl.DrawLineEx(c + d * (7 * u), c + d * ((11 + 6 * h) * u), 2.2 * u, fade(HUD_WHITE, h))
		}
	}
	if g.overheated {
		blink := 0.5 + 0.5 * math.sin(g.real_time * 18)
		text(res.font_hud, "OVERHEAT", c + {0, 36 * u}, 13 * u, fade(HUD_RED, 0.5 + 0.5 * blink), 0.5, 3 * u)
	}
}

draw_threats :: proc(u: f32) {
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) || e.kind == .Asteroid || e.kind == .Boss {
			continue
		}
		sp, ok := project(e.pos)
		if !ok {
			continue
		}
		pr := projected_radius(e.pos, e.radius)
		col := kind_color(e.kind)
		switch e.kind {
		case .Bolt, .Nova:
			rl.DrawRing(sp, pr + 5 * u, pr + 6.5 * u, 0, 360, 20, fade(col, 0.55))
		case .Fighter:
			if e.charge > 0 {
				rl.DrawRing(sp, pr + 8 * u, pr + 10.5 * u, -90, -90 + 360 * e.charge, 32, HUD_RED)
				text(res.font_hud, "!", sp + {0, -pr - 30 * u}, 16 * u, HUD_RED, 0.5)
			}
			fallthrough
		case .Drone:
			top := sp.y - pr - 9 * u
			s := 4.5 * u
			rl.DrawTriangle({sp.x - s, top - s}, {sp.x, top}, {sp.x + s, top - s}, fade(col, 0.8))
		case .Asteroid, .Boss:
		}
	}
}

// Arrows on the screen edge pointing at hostiles outside the view.
draw_offscreen :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	c := Vec2{sw * 0.5, sh * 0.5}
	margin := 34 * u
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) {
			continue
		}
		rel := e.pos - g.rcam.position
		dist := length(rel)
		if e.kind == .Asteroid && dist > 115 {
			continue
		}
		z := dot(rel, g.rfwd)
		x := dot(rel, g.rright)
		y := dot(rel, g.rup)
		if z > 0 {
			sp, ok := project(e.pos)
			if ok && sp.x > margin && sp.x < sw - margin && sp.y > margin && sp.y < sh - margin {
				continue
			}
		} else {
			// behind: push the arrow to the nearer side edge
			side: f32 = 1
			if x < 0 {
				side = -1
			}
			x = side * max(abs(x), -z)
		}
		ang := math.atan2(-y, x)
		d := Vec2{math.cos(ang), math.sin(ang)}
		p := c + Vec2{d.x * (sw * 0.5 - margin), d.y * (sh * 0.5 - margin)}
		p.x = clamp(p.x, margin, sw - margin)
		p.y = clamp(p.y, margin, sh - margin)
		close := 1 - clamp01(dist / 150)
		alpha := 0.35 + 0.65 * close
		if dist < 45 {
			alpha *= 0.6 + 0.4 * math.sin(g.real_time * 16)
		}
		col := fade(kind_color(e.kind), alpha)
		size := (6 + 7 * close) * u
		if e.kind == .Boss {
			size = 16 * u
		}
		n := Vec2{-d.y, d.x}
		tip := p + d * size
		rl.DrawTriangle(tip, p - d * (size * 0.5) + n * (size * 0.75), p - d * (size * 0.5) - n * (size * 0.75), col)
	}
}

draw_lock :: proc(u: f32) {
	e := find_entity(g.lock_id)
	if e == nil {
		return
	}
	sp, ok := project(e.pos)
	if !ok {
		return
	}
	t := ease_out(g.lock_t)
	locked := g.lock_t >= 1
	size := max(projected_radius(e.pos, e.radius) * 1.15, 16 * u)
	s := size * (1 + (1 - t) * 1.4)
	rot := (1 - t) * math.PI * 0.5
	col := fade(HUD_CYAN, 0.35 + 0.5 * t)
	if locked {
		col = HUD_ORANGE
		if g.ammo <= 0 {
			col = {170, 170, 180, 200}
		}
	}
	arm := max(s * 0.4, 7 * u)
	thick := 2 * u
	for k in 0 ..< 4 {
		sx: f32 = 1
		sy: f32 = 1
		if k & 1 == 1 {
			sx = -1
		}
		if k >= 2 {
			sy = -1
		}
		corner := Vec2{sx * s, sy * s}
		p0 := sp + rot2(corner, rot)
		rl.DrawLineEx(p0, sp + rot2(corner - {sx * arm, 0}, rot), thick, col)
		rl.DrawLineEx(p0, sp + rot2(corner - {0, sy * arm}, rot), thick, col)
	}
	if locked {
		spin := g.real_time * 90
		r := s * 1.3
		for k in 0 ..< 3 {
			a := spin + f32(k) * 120
			rl.DrawRing(sp, r, r + 1.5 * u, a, a + 50, 12, fade(col, 0.6))
		}
		label: cstring = "LOCKED"
		if g.ammo <= 0 {
			label = "NO MISSILES"
		}
		text(res.font_hud, label, sp + {0, s * 1.3 + 8 * u}, 12 * u, col, 0.5, 3 * u)
	}
	if e.max_hp > 3 {
		w := max(s * 1.6, 44 * u)
		y := sp.y - s - 12 * u
		rl.DrawRectangleV({sp.x - w * 0.5, y}, {w, 3 * u}, {0, 0, 0, 140})
		rl.DrawRectangleV({sp.x - w * 0.5, y}, {w * clamp01(e.hp / e.max_hp), 3 * u}, col)
	}
	text(res.font_body, fmt.ctprintf("%dm", int(length(e.pos))), sp + {s + 7 * u, -s - 2 * u}, 15 * u, fade(col, 0.85), 0, 1 * u)
}

draw_damage_marks :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	c := Vec2{sw * 0.5, sh * 0.5}
	r := 130 * u
	for m in g.damage_marks {
		if m.life <= 0 {
			continue
		}
		x := dot(m.dir, g.rright)
		z := dot(m.dir, g.rfwd)
		ang := math.atan2(-z, x) * math.DEG_PER_RAD
		a := clamp01(m.life / 1.4)
		rl.DrawRing(c, r - 4 * u, r + 14 * u, ang - 16, ang + 16, 12, fade(HUD_RED, a * 0.22))
		rl.DrawRing(c, r, r + 7 * u, ang - 22, ang + 22, 16, fade(HUD_RED, a * 0.9))
	}
}

draw_status :: proc(u: f32) {
	sh := f32(rl.GetScreenHeight())
	x := 34 * u
	w := 250 * u
	h := 11 * u
	y_sh := sh - 88 * u
	y_hu := sh - 44 * u

	scol := HUD_CYAN
	if g.shield_hit > 0.6 {
		scol = HUD_WHITE
	}
	if g.shield <= 0 {
		scol = {120, 232, 255, 80}
	}
	text(res.font_hud, "SHIELD", {x, y_sh - 18 * u}, 12 * u, fade(HUD_CYAN, 0.75), 0, 3 * u)
	text(res.font_body, fmt.ctprintf("%d", int(math.ceil(g.shield))), {x + w + 10 * u, y_sh - 4 * u}, 20 * u, scol, 1)
	seg_bar(x, y_sh, w, h, g.shield / 100, scol, u)

	hcol := lerp_color(HUD_RED, HUD_GREEN, smooth(0.2, 0.6, g.hull / 100))
	if g.hurt > 0.5 {
		hcol = HUD_WHITE
	}
	text(res.font_hud, "HULL", {x, y_hu - 18 * u}, 12 * u, fade(hcol, 0.75), 0, 3 * u)
	text(res.font_body, fmt.ctprintf("%d", int(math.ceil(g.hull))), {x + w + 10 * u, y_hu - 4 * u}, 20 * u, hcol, 1)
	seg_bar(x, y_hu, w, h, g.hull / 100, hcol, u)

	if g.hull < 30 {
		blink := 0.5 + 0.5 * math.sin(g.real_time * 9)
		glow_text(res.font_hud, "HULL CRITICAL", {x, y_sh - 46 * u}, 15 * u, fade(HUD_RED, 0.4 + 0.6 * blink), 0, 4 * u, blink)
	} else if g.shield <= 0 {
		text(res.font_hud, "SHIELD OFFLINE", {x, y_sh - 46 * u}, 13 * u, fade(HUD_ORANGE, 0.8), 0, 4 * u)
	}
}

missile_icon :: proc(x, bottom, w, h: f32, col: rl.Color) {
	body_top := bottom - h * 0.74
	rl.DrawRectangleV({x + w * 0.18, body_top}, {w * 0.64, h * 0.62}, col)
	rl.DrawTriangle({x + w * 0.18, body_top}, {x + w * 0.82, body_top}, {x + w * 0.5, bottom - h}, col)
	fin_top := bottom - h * 0.3
	rl.DrawTriangle({x + w * 0.18, fin_top}, {x, bottom}, {x + w * 0.18, bottom - h * 0.1}, col)
	rl.DrawTriangle({x + w * 0.82, fin_top}, {x + w * 0.82, bottom - h * 0.1}, {x + w, bottom}, col)
}

draw_missiles :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	iw := 13 * u
	ih := 42 * u
	gap := 11 * u
	right := sw - 34 * u
	bottom := sh - 40 * u
	text(res.font_hud, "MISSILES", {right, bottom - ih - 28 * u}, 12 * u, fade(HUD_ORANGE, 0.8), 1, 3 * u)
	text(res.font_body, "RMB", {right - 118 * u, bottom - ih - 30 * u}, 15 * u, {255, 172, 64, 110}, 1, 2 * u)
	for k in 0 ..< MAX_AMMO {
		x := right - f32(MAX_AMMO - k) * (iw + gap) + gap
		missile_icon(x, bottom, iw, ih, {255, 172, 64, 36})
		if k < g.ammo {
			if k == g.ammo - 1 && g.ammo_flash > 0 {
				rl.BeginBlendMode(.ADDITIVE)
				sprite2(res.tex_soft, {x + iw * 0.5, bottom - ih * 0.5}, ih * (0.8 + g.ammo_flash), fade(HUD_ORANGE, g.ammo_flash))
				rl.EndBlendMode()
			}
			col := HUD_ORANGE
			if k == g.ammo - 1 && g.ammo_flash > 0 {
				col = lerp_color(HUD_ORANGE, HUD_WHITE, g.ammo_flash)
			}
			missile_icon(x, bottom, iw, ih, col)
		} else if k == g.ammo && g.ammo_charge > 0 {
			fh := ih * clamp01(g.ammo_charge)
			rl.BeginScissorMode(i32(x - 2), i32(bottom - fh), i32(iw + 4), i32(fh + 2))
			missile_icon(x, bottom, iw, ih, {255, 172, 64, 120})
			rl.EndScissorMode()
		}
	}
	rl.DrawLineEx({right - f32(MAX_AMMO) * (iw + gap) + gap, bottom + 7 * u}, {right, bottom + 7 * u}, 1.5 * u, {255, 172, 64, 90})
}

draw_score :: proc(u: f32) {
	x := 34 * u
	y := 26 * u
	text(res.font_hud, "SCORE", {x, y}, 12 * u, fade(HUD_CYAN, 0.75), 0, 3 * u)
	glow_text(res.font_hud, fmt.ctprintf("%07d", int(g.shown_score + 0.5)), {x, y + 16 * u}, 34 * u, HUD_WHITE, 0, 2 * u, 0.5)
	if g.combo > 1 && g.combo_t > 0 {
		mult := combo_mult()
		cy := y + 62 * u
		col := HUD_CYAN
		if mult >= 4 {
			col = {255, 130, 60, 255}
		} else if mult >= 2 {
			col = HUD_ORANGE
		}
		glow_text(res.font_hud, fmt.ctprintf("x%d", mult), {x, cy}, 26 * u, col, 0, 1 * u, 0.6)
		text(res.font_body, fmt.ctprintf("CHAIN %d", g.combo), {x + 58 * u, cy + 5 * u}, 19 * u, fade(HUD_WHITE, 0.8), 0, 2 * u)
		rl.DrawRectangleV({x, cy + 34 * u}, {150 * u, 3 * u}, {255, 255, 255, 30})
		rl.DrawRectangleV({x, cy + 34 * u}, {150 * u * clamp01(g.combo_t / 2.6), 3 * u}, col)
	}
}

draw_wave_info :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	right := sw - 34 * u
	y := 26 * u
	text(res.font_hud, "WAVE", {right, y}, 12 * u, fade(HUD_CYAN, 0.75), 1, 3 * u)
	glow_text(res.font_hud, fmt.ctprintf("%02d", g.level), {right, y + 16 * u}, 34 * u, HUD_WHITE, 1, 2 * u, 0.5)
	remaining := hostiles_alive() + (g.queue_n - g.queue_i)
	text(res.font_body, fmt.ctprintf("HOSTILES  %d", remaining), {right, y + 60 * u}, 19 * u, fade(HUD_WHITE, 0.75), 1, 2 * u)
	name := SECTOR_NAMES[max(g.level - 1, 0) % len(SECTOR_NAMES)]
	text(res.font_body, name, {right, y + 82 * u}, 15 * u, fade(HUD_CYAN, 0.5), 1, 4 * u)
}

draw_boss_bar :: proc(u: f32) {
	e := find_entity(g.boss_id)
	if e == nil || e.kind != .Boss {
		return
	}
	sw := f32(rl.GetScreenWidth())
	appear := clamp01(1 - e.warp)
	w := min(560 * u, sw * 0.46)
	h := 10 * u
	x := sw * 0.5 - w * 0.5
	y := 30 * u
	label: cstring = "MOTHERSHIP"
	if e.hp < e.max_hp * 0.5 && e.state != 2 {
		label = "MOTHERSHIP  -  ENRAGED"
	}
	glow_text(res.font_hud, label, {sw * 0.5, y}, 13 * u, fade(HUD_RED, appear), 0.5, 6 * u, 0.6)
	y += 22 * u
	rl.DrawRectangleV({x, y}, {w, h}, {30, 6, 12, u8(190 * appear)})
	f := clamp01(e.hp / e.max_hp)
	col := HUD_RED
	if e.flash > 0.5 {
		col = HUD_WHITE
	}
	rl.DrawRectangleV({x, y}, {w * f, h}, fade(col, appear))
	for k in 1 ..< 4 {
		tx := x + w * f32(k) / 4
		rl.DrawLineEx({tx, y}, {tx, y + h}, 1.5 * u, {20, 0, 6, 200})
	}
	rl.DrawRectangleLinesEx({x - 3 * u, y - 3 * u, w + 6 * u, h + 6 * u}, 1.2 * u, fade(HUD_RED, 0.5 * appear))
}

draw_radar :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	R := 68 * u
	c := Vec2{sw * 0.5, sh - R - 20 * u}
	dim := rl.Color{120, 232, 255, 30}
	rl.DrawCircleV(c, R, {4, 10, 24, 150})
	half := f32(math.atan(g.tan_half * g.aspect) * math.DEG_PER_RAD)
	rl.DrawCircleSector(c, R, -90 - half, -90 + half, 20, {120, 232, 255, 24})
	sweep := math.mod(g.real_time * 140, 360)
	for k in 0 ..< 10 {
		a1 := sweep - f32(k) * 4
		rl.DrawCircleSector(c, R, a1 - 4, a1, 3, {120, 232, 255, u8(36 - k * 3)})
	}
	rl.DrawRing(c, R - 1.5 * u, R, 0, 360, 64, {120, 232, 255, 130})
	rl.DrawRing(c, R * 0.5 - 0.6 * u, R * 0.5 + 0.6 * u, 0, 360, 48, {120, 232, 255, 45})
	rl.DrawLineEx(c - {R, 0}, c + {R, 0}, 1, dim)
	rl.DrawLineEx(c - {0, R}, c + {0, R}, 1, dim)
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead || e.ambient {
			continue
		}
		rx := dot(e.pos, g.right) / RADAR_RANGE * R
		rz := dot(e.pos, g.fwd) / RADAR_RANGE * R
		p := c + Vec2{rx, -rz}
		d := length2(p - c)
		col := kind_color(e.kind)
		if d > R - 4 * u {
			p = c + (p - c) / d * (R - 4 * u)
			col = fade(col, 0.45)
		}
		switch e.kind {
		case .Asteroid:
			rl.DrawCircleV(p, (1.4 + f32(2 - e.tier) * 0.7) * u, col)
		case .Drone:
			rl.DrawCircleV(p, 2 * u, col)
		case .Fighter:
			s := 3.5 * u
			rl.DrawTriangle(p + {0, -s}, p + {-s, s}, p + {s, s}, col)
		case .Boss:
			s := 5 * u
			rl.DrawRectangleV(p - s, {s * 2, s * 2}, col)
		case .Bolt, .Nova:
			rl.DrawCircleV(p, 1.4 * u, col)
		}
	}
	rl.DrawTriangle(c + {0, -5 * u}, c + {-3.5 * u, 4 * u}, c + {3.5 * u, 4 * u}, HUD_WHITE)
}

draw_wave_banner :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	cx := sw * 0.5
	cy := sh * 0.3
	switch g.wave_state {
	case .Intro:
		t := g.wave_t
		a := smooth(0, 0.3, t) * (1 - smooth(2.1, 2.6, t))
		if a <= 0 {
			return
		}
		lw := sw * 0.28 * ease_out(clamp01(t / 0.7))
		if is_boss_level(g.level) {
			flash := 0.5 + 0.5 * math.sin(g.real_time * 12)
			band := 74 * u
			rl.DrawRectangleV({0, cy - band * 0.5}, {sw, band}, {255, 30, 50, u8(38 * a)})
			rl.DrawRectangleV({0, cy - band * 0.5 - 3 * u}, {sw, 2 * u}, fade(HUD_RED, a * 0.8))
			rl.DrawRectangleV({0, cy + band * 0.5 + 1 * u}, {sw, 2 * u}, fade(HUD_RED, a * 0.8))
			size := fit_size(res.font_title, "WARNING", 64 * u, 0.12, sw * 0.8)
			glow_text(res.font_title, "WARNING", {cx, cy - size * 0.5}, size, fade(HUD_RED, a * (0.55 + 0.45 * flash)), 0.5, size * 0.12, 1)
			text(res.font_body, "MOTHERSHIP APPROACHING", {cx, cy + band * 0.5 + 16 * u}, 24 * u, fade(HUD_WHITE, a), 0.5, 8 * u)
		} else {
			label := fmt.ctprintf("WAVE %d", g.level)
			size := fit_size(res.font_title, label, 76 * u, 0.08, sw * 0.8)
			spacing := size * (0.08 + 0.25 * (1 - ease_out(clamp01(t / 0.9))))
			glow_text(res.font_title, label, {cx, cy - size * 0.5}, size, fade(HUD_WHITE, a), 0.5, spacing, 1)
			ly := cy + size * 0.62
			rl.DrawRectangleGradientH(i32(cx - lw), i32(ly), i32(lw), i32(max(2 * u, 1)), {120, 232, 255, 0}, fade(HUD_CYAN, a))
			rl.DrawRectangleGradientH(i32(cx), i32(ly), i32(lw), i32(max(2 * u, 1)), fade(HUD_CYAN, a), {120, 232, 255, 0})
			name := SECTOR_NAMES[max(g.level - 1, 0) % len(SECTOR_NAMES)]
			text(res.font_body, fmt.ctprintf("SECTOR  -  %s", name), {cx, ly + 12 * u}, 24 * u, fade(HUD_CYAN, a), 0.5, 7 * u)
		}
	case .Cleared:
		t := g.wave_t
		a := smooth(0, 0.25, t) * (1 - smooth(3.2, 3.8, t))
		if a <= 0 {
			return
		}
		size := fit_size(res.font_title, "WAVE CLEARED", 58 * u, 0.1, sw * 0.8)
		glow_text(res.font_title, "WAVE CLEARED", {cx, cy - size * 0.5}, size, fade(HUD_CYAN, a), 0.5, size * 0.1, 1)
		text(res.font_body, fmt.ctprintf("BONUS +%d    HULL +15    SHIELDS RESTORED", 250 * g.level), {cx, cy + size * 0.7}, 22 * u, fade(HUD_WHITE, a * 0.9), 0.5, 5 * u)
	case .Active:
	}
}

draw_floaters :: proc(u: f32) {
	for i in 0 ..< g.floater_n {
		f := &g.floaters[i]
		sp, ok := project(f.pos)
		if !ok {
			continue
		}
		t := 1 - f.life / f.max_life
		a := 1 - smooth(0.65, 1, t)
		pop := 1 + 0.6 * (1 - ease_out(clamp01(t * 5)))
		size := 19 * u * f.size * pop
		s := cstring(raw_data(f.text[:]))
		glow_text(res.font_hud, s, sp - {0, size * 0.5}, size, fade(f.col, a), 0.5, 1 * u, 0.6 * a)
	}
}

// ---- lens flare -----------------------------------------------------------------------------

Ghost :: struct {
	t, size, alpha: f32,
	ring:           bool,
	tint:           Vec3,
}

FLARE_GHOSTS := [?]Ghost {
	{0.35, 20, 0.22, false, {0.6, 0.8, 1.0}},
	{0.62, 62, 0.10, true, {0.9, 0.6, 1.0}},
	{0.9, 12, 0.35, false, {1.0, 0.7, 0.4}},
	{1.25, 95, 0.08, true, {0.5, 1.0, 0.8}},
	{1.5, 30, 0.16, false, {0.5, 0.6, 1.0}},
	{1.9, 150, 0.06, true, {1.0, 0.8, 0.6}},
	{2.2, 9, 0.3, false, {0.7, 1.0, 1.0}},
}

draw_lens_flare :: proc(u: f32) {
	sd := norm(SUN_DIR)
	facing := dot(sd, g.rfwd)
	if facing < 0.3 {
		return
	}
	sp, ok := project(g.rcam.position + sd * 1000)
	if !ok {
		return
	}
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	nx := sp.x / sw * 2 - 1
	ny := sp.y / sh * 2 - 1
	vis := 1 - smooth(0.8, 1.3, max(abs(nx), abs(ny)))
	if vis <= 0 {
		return
	}
	c := Vec2{sw * 0.5, sh * 0.5}
	axis := c - sp
	sun := g.pal.sun
	rl.BeginBlendMode(.ADDITIVE)
	for gh in FLARE_GHOSTS {
		p := sp + axis * gh.t
		tex := res.tex_soft
		if gh.ring {
			tex = res.tex_ring
		}
		sprite2(tex, p, gh.size * u, rgba(gh.tint * sun, gh.alpha * vis), 0)
	}
	rl.EndBlendMode()
}

// ---- menus ----------------------------------------------------------------------------------

draw_cursor :: proc(u: f32) {
	c := g.mouse
	rl.DrawRing(c, 6 * u, 8 * u, 0, 360, 24, HUD_CYAN)
	rl.DrawCircleV(c, 1.8 * u, HUD_WHITE)
}

draw_title :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	cx := sw * 0.5
	t := g.phase_t
	a := smooth(0, 1.2, t)
	rl.DrawRectangleGradientV(0, 0, i32(sw), i32(sh * 0.4), {0, 0, 0, 170}, {0, 0, 0, 0})
	rl.DrawRectangleGradientV(0, i32(sh * 0.5), i32(sw), i32(sh * 0.5) + 1, {0, 0, 0, 0}, {0, 0, 0, 210})

	title: cstring = "STARBREAKER"
	size := fit_size(res.font_title, title, 112 * u, 0.1, sw * 0.88)
	spacing := size * 0.1
	ty := sh * 0.2
	glitch := f32(0)
	if math.sin(g.real_time * 1.7) > 0.96 {
		glitch = (randf() * 2 - 1) * 8 * u
	}
	off := (2.5 + 1.5 * math.sin(g.real_time * 2.3)) * u + abs(glitch)
	rl.BeginBlendMode(.ADDITIVE)
	text(res.font_title, title, {cx - off + glitch, ty}, size, {255, 40, 90, u8(110 * a)}, 0.5, spacing)
	text(res.font_title, title, {cx + off + glitch, ty}, size, {40, 160, 255, u8(110 * a)}, 0.5, spacing)
	rl.EndBlendMode()
	glow_text(res.font_title, title, {cx + glitch * 0.3, ty}, size, fade(HUD_WHITE, a), 0.5, spacing, 1)

	sub_y := ty + size * 1.05
	sub: cstring = "DEEP SPACE ASTEROID DEFENSE"
	sub_size := 24 * u
	m := rl.MeasureTextEx(res.font_body, sub, sub_size, 9 * u)
	text(res.font_body, sub, {cx, sub_y}, sub_size, fade(HUD_CYAN, a * 0.9), 0.5, 9 * u)
	lw := 90 * u
	ly := sub_y + sub_size * 0.5
	rl.DrawRectangleGradientH(i32(cx - m.x * 0.5 - lw - 16 * u), i32(ly), i32(lw), i32(max(u, 1)), {120, 232, 255, 0}, fade(HUD_CYAN, a))
	rl.DrawRectangleGradientH(i32(cx + m.x * 0.5 + 16 * u), i32(ly), i32(lw), i32(max(u, 1)), fade(HUD_CYAN, a), {120, 232, 255, 0})

	rows := [?][2]cstring {
		{"MOUSE TO SCREEN EDGE", "TURN"},
		{"LEFT CLICK  /  SPACE", "PLASMA CANNONS"},
		{"RIGHT CLICK  /  F", "SEEKER MISSILES"},
		{"DESTROY ANYTHING", "RELOAD MISSILES"},
		{"P  /  ESC", "PAUSE"},
		{"M", "MUTE"},
	}
	row_h := 31 * u
	ry := sh * 0.54
	rl.DrawLineEx({cx, ry - 4 * u}, {cx, ry + f32(len(rows)) * row_h - 8 * u}, 1 * u, fade(HUD_CYAN, 0.35 * a))
	for row, i in rows {
		y := ry + f32(i) * row_h
		ra := a * smooth(0.3 + f32(i) * 0.08, 0.8 + f32(i) * 0.08, t)
		text(res.font_body, row[0], {cx - 18 * u, y}, 22 * u, fade(HUD_CYAN, ra * 0.75), 1, 3 * u)
		text(res.font_body, row[1], {cx + 18 * u, y}, 22 * u, fade(HUD_WHITE, ra), 0, 3 * u)
	}

	pulse := 0.55 + 0.45 * math.sin(g.real_time * 4)
	py := sh * 0.87
	glow_text(res.font_hud, "CLICK TO LAUNCH", {cx, py}, 22 * u, fade(HUD_ORANGE, a * pulse), 0.5, 8 * u, 1)
	if g.best > 0 {
		text(res.font_body, fmt.ctprintf("BEST  %07d", g.best), {cx, py + 36 * u}, 18 * u, fade(HUD_WHITE, a * 0.6), 0.5, 4 * u)
	}
	if g.muted {
		text(res.font_body, "MUTED", {sw - 30 * u, sh - 36 * u}, 16 * u, fade(HUD_WHITE, 0.5), 1, 3 * u)
	}
}

draw_pause :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	cx := sw * 0.5
	rl.DrawRectangleV({0, 0}, {sw, sh}, {0, 0, 0, 110})
	size := fit_size(res.font_title, "PAUSED", 68 * u, 0.18, sw * 0.8)
	glow_text(res.font_title, "PAUSED", {cx, sh * 0.38}, size, HUD_WHITE, 0.5, size * 0.18, 1)
	pulse := 0.55 + 0.45 * math.sin(g.real_time * 4)
	text(res.font_body, "CLICK TO RESUME", {cx, sh * 0.38 + size * 1.3}, 22 * u, fade(HUD_CYAN, pulse), 0.5, 7 * u)
	if g.muted {
		text(res.font_body, "MUTED  -  PRESS M", {cx, sh * 0.38 + size * 1.3 + 34 * u}, 17 * u, fade(HUD_WHITE, 0.5), 0.5, 3 * u)
	}
}

draw_game_over :: proc(u: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	cx := sw * 0.5
	t := g.phase_t
	a := smooth(0, 0.8, t)
	rl.DrawRectangleGradientV(0, 0, i32(sw), i32(sh) + 1, {40, 0, 10, u8(110 * a)}, {0, 0, 0, u8(200 * a)})

	title: cstring = "SIGNAL LOST"
	size := fit_size(res.font_title, title, 92 * u, 0.1, sw * 0.86)
	ty := sh * 0.2
	jit := (1 - smooth(0, 1.4, t)) * 16 * u * (randf() * 2 - 1)
	rl.BeginBlendMode(.ADDITIVE)
	text(res.font_title, title, {cx - 3 * u + jit, ty}, size, {255, 30, 60, u8(100 * a)}, 0.5, size * 0.1)
	text(res.font_title, title, {cx + 3 * u - jit, ty}, size, {60, 120, 255, u8(70 * a)}, 0.5, size * 0.1)
	rl.EndBlendMode()
	glow_text(res.font_title, title, {cx + jit * 0.4, ty}, size, fade(HUD_RED, a), 0.5, size * 0.1, 1)

	sy := ty + size * 1.35
	sa := a * smooth(0.5, 1.0, t)
	text(res.font_hud, "FINAL SCORE", {cx, sy}, 14 * u, fade(HUD_CYAN, sa * 0.8), 0.5, 5 * u)
	glow_text(res.font_hud, fmt.ctprintf("%07d", g.score), {cx, sy + 22 * u}, 52 * u, fade(HUD_WHITE, sa), 0.5, 4 * u, 0.8)

	acc := 0
	if g.shots > 0 {
		acc = int(f32(g.hits) / f32(g.shots) * 100 + 0.5)
	}
	labels := [?]cstring{"WAVE REACHED", "HOSTILES DESTROYED", "ACCURACY"}
	values := [?]cstring{fmt.ctprintf("%d", g.level), fmt.ctprintf("%d", g.kills), fmt.ctprintf("%d%%", acc)}
	row_h := 32 * u
	ry := sy + 100 * u
	for i in 0 ..< len(labels) {
		ra := a * smooth(0.9 + f32(i) * 0.2, 1.3 + f32(i) * 0.2, t)
		y := ry + f32(i) * row_h
		text(res.font_body, labels[i], {cx - 18 * u, y}, 23 * u, fade(HUD_CYAN, ra * 0.75), 1, 3 * u)
		text(res.font_body, values[i], {cx + 18 * u, y}, 23 * u, fade(HUD_WHITE, ra), 0, 3 * u)
	}
	by := ry + f32(len(labels)) * row_h + 18 * u
	ba := a * smooth(1.5, 1.9, t)
	if g.new_best {
		blink := 0.6 + 0.4 * math.sin(g.real_time * 8)
		glow_text(res.font_hud, "NEW RECORD", {cx, by}, 24 * u, fade(HUD_ORANGE, ba * blink), 0.5, 7 * u, 1)
	} else {
		text(res.font_body, fmt.ctprintf("BEST  %07d", g.best), {cx, by}, 20 * u, fade(HUD_WHITE, ba * 0.65), 0.5, 4 * u)
	}
	if t > 1.8 {
		pulse := 0.55 + 0.45 * math.sin(g.real_time * 4)
		glow_text(res.font_hud, "CLICK TO REDEPLOY", {cx, sh * 0.86}, 22 * u, fade(HUD_ORANGE, smooth(1.8, 2.3, t) * pulse), 0.5, 8 * u, 1)
	}
}
