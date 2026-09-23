package game

import "core:math"
import "core:mem"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

init :: proc(width, height: i32) {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(width, height, "STARBREAKER")
	rl.SetExitKey(.KEY_NULL)
	rlgl.SetClipPlanes(0.25, 4000)
	load_resources()
	init_stars()
	g.best = load_best()
	g.start_level = max(int(js_get_start_wave()), 1)
	g.pal = palette_for_level(g.start_level)
	g.pal_target = g.pal
	enter_title()
}

init_stars :: proc() {
	for &s in stars {
		d := rand_unit()
		// a denser galactic band near the horizon
		if randf() < 0.45 {
			d.y *= 0.22
			d = norm(d)
		}
		s.dir = d
		s.size = rand_range(2.2, 5.5)
		if randf() < 0.05 {
			s.size *= 2.2
		}
		warm := randf()
		s.col = lerp3({0.65, 0.78, 1.0}, {1.0, 0.85, 0.7}, warm) * rand_range(0.45, 1.1)
		s.phase = rand_range(0, math.TAU)
		s.speed = rand_range(0.8, 4)
	}
}

// Resets everything except the settings that survive between runs.
reset_state :: proc() {
	best := g.best
	muted := g.muted
	start_level := g.start_level
	yaw := g.yaw
	real_time := g.real_time
	t := g.time
	pal := g.pal
	pal_target := g.pal_target
	next_id := g.next_id
	mem.zero_item(&g)
	g.best = best
	g.muted = muted
	g.start_level = start_level
	g.yaw = yaw
	g.real_time = real_time
	g.time = t
	g.pal = pal
	g.pal_target = pal_target
	g.next_id = next_id
	g.time_scale = 1
	g.mouse = rl.GetMousePosition()
}

enter_title :: proc() {
	reset_state()
	g.phase = .Title
	g.pal_target = palette_for_level(g.start_level)
	spawn_ambient_field()
}

start_game :: proc() {
	reset_state()
	g.phase = .Playing
	g.hull = 100
	g.shield = 100
	g.ammo = MAX_AMMO
	g.fire_lock = true
	start_wave(g.start_level)
	// warp-in
	g.flash = {0.55, 0.85, 1, 0.55}
	g.fov_kick = 16
	g.aberr = 0.02
	for k in 0 ..< 3 {
		emit(.Ring, g.fwd * 30, {}, {0.6, 0.9, 1, 0.9}, {0.2, 0.4, 1, 0}, 4, 90 + f32(k) * 40, 0.7 + f32(k) * 0.2)
	}
	for _ in 0 ..< 160 {
		d := norm(g.fwd * 2.5 + rand_unit())
		emit(.Spark, d * rand_range(20, 120), d * rand_range(-260, -120), {0.7, 0.9, 1, 1}, {0.3, 0.5, 1, 0}, 0.25, 0.1, rand_range(0.3, 0.8), 0, 0.03)
	}
	sfx(.Warp, 1, 0, 0.8)
}

enter_game_over :: proc() {
	g.phase = .Game_Over
	g.phase_t = 0
	g.dying = false
	if g.score > g.best {
		g.best = g.score
		g.new_best = true
		save_best(g.best)
	}
}

pause :: proc() {
	g.phase = .Paused
	sfx(.UI, 0.6, 0, 0.8)
}

resume :: proc() {
	g.phase = .Playing
	g.fire_lock = true
	sfx(.UI, 0.6, 0, 1.2)
}

on_blur :: proc() {
	if g.phase == .Playing && !g.dying {
		pause()
	}
}

// The ship's reactor blows: ships vaporise, rocks are flung outward.
death_shockwave :: proc() {
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		switch e.kind {
		case .Asteroid:
			e.ambient = true
			e.hot = 1
			e.vel = norm(e.pos) * rand_range(10, 22)
		case .Boss:
			e.dead = true
			explode(e.pos, 1, .Boss)
		case .Drone, .Fighter:
			e.dead = true
			explode(e.pos, 2, .Ship)
		case .Bolt, .Nova:
			e.dead = true
			explode(e.pos, 1, .Bolt)
		}
	}
	g.missile_n = 0
	g.bullet_n = 0
	emit(.Ring, {}, {}, {1, 0.8, 0.6, 1}, {1, 0.2, 0.1, 0}, 2, 160, 1.2)
	emit(.Flare, g.fwd * 6, {}, {1, 0.9, 0.8, 1}, {1, 0.3, 0.2, 0}, 10, 60, 0.9)
}

// ---- input ----------------------------------------------------------------------------------

handle_input :: proc() {
	if rl.IsKeyPressed(.M) {
		set_muted(!g.muted)
	}
	if !rl.IsMouseButtonDown(.LEFT) {
		g.fire_lock = false
	}
	clicked := rl.IsMouseButtonPressed(.LEFT)
	confirm := clicked || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE)
	toggle := rl.IsKeyPressed(.P) || rl.IsKeyPressed(.ESCAPE)
	switch g.phase {
	case .Title:
		if confirm && g.phase_t > 0.4 {
			sfx(.UI)
			start_game()
		}
	case .Playing:
		if toggle && !g.dying {
			pause()
		}
	case .Paused:
		if toggle || clicked {
			resume()
		}
	case .Game_Over:
		if confirm && g.phase_t > 1.8 {
			sfx(.UI)
			start_game()
		}
	}
}

// ---- simulation -----------------------------------------------------------------------------

update_bullets :: proc(dt: f32) {
	i := 0
	for i < g.bullet_n {
		b := &g.bullets[i]
		b.life -= dt
		b.prev = b.pos
		b.pos += b.vel * dt
		hit: ^Entity = nil
		best_t: f32 = 2
		for j in 0 ..< g.ent_n {
			e := &g.ents[j]
			if !is_target(e) {
				continue
			}
			ok, t := segment_sphere(b.prev, b.pos, e.pos, e.radius)
			if ok && t < best_t {
				best_t = t
				hit = e
			}
		}
		if hit != nil {
			at := b.prev + (b.pos - b.prev) * best_t
			hit_entity(hit, 1, at, norm(b.vel))
			b.life = 0
		} else if randf() < 0.6 && length(b.pos - b.origin) > 8 {
			col := Vec4{0.3, 0.85, 1, 0.5}
			if b.side == 1 {
				col = {0.5, 0.6, 1, 0.5}
			}
			emit(.Glow, b.pos - norm(b.vel) * 2, {}, col, {0.2, 0.3, 1, 0}, 0.45, 0.1, 0.14)
		}
		if b.life <= 0 {
			g.bullets[i] = g.bullets[g.bullet_n - 1]
			g.bullet_n -= 1
			continue
		}
		i += 1
	}
}

update_play :: proc(dt, real_dt: f32) {
	if g.dying {
		g.dead_t += real_dt
		if g.dead_t > 2.4 {
			enter_game_over()
		}
	} else {
		update_weapons(dt)
		update_lock(dt)
		update_shield(dt)
		update_waves(dt)
		g.combo_t -= dt
		if g.combo_t <= 0 {
			g.combo = 0
		}
	}
	update_bullets(dt)
	update_missiles(dt)
	update_entities(dt)
	sweep_entities()
}

collect_frame_lights :: proc() {
	frame_light_n = 0
	for i in 0 ..< g.light_n {
		l := &g.lights[i]
		k := l.life / l.max_life
		push_frame_light(l.pos, l.col * k, l.radius * (0.6 + 0.4 * k))
	}
	for i in 0 ..< g.missile_n {
		m := &g.missiles[i]
		flick := 0.85 + 0.15 * math.sin(m.age * 50 + m.seed)
		push_frame_light(m.pos - norm(m.vel), Vec3{1, 0.55, 0.2} * (2.2 * flick), 18)
	}
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		#partial switch e.kind {
		case .Asteroid:
			if e.molten {
				push_frame_light(e.pos, Vec3{1, 0.4, 0.1} * 1.2, e.radius * 3.5)
			}
		case .Bolt:
			push_frame_light(e.pos, Vec3{1, 0.2, 0.4} * 1.6, 14)
		case .Nova:
			push_frame_light(e.pos, Vec3{1, 0.3, 0.8} * 2.5, 30)
		case .Boss:
			push_frame_light(e.pos + e.fwd * 6, Vec3{1, 0.2, 0.3} * (1.5 + e.charge * 3), 45)
		case .Fighter:
			if e.charge > 0 {
				push_frame_light(e.pos + e.fwd * 4, Vec3{1, 0.3, 0.2} * (e.charge * 2.5), 16)
			}
		}
	}
}

music_level :: proc() -> f32 {
	switch g.phase {
	case .Title:
		return 0.14
	case .Paused:
		return 0.05
	case .Game_Over:
		return 0.08
	case .Playing:
		if g.dying {
			return 0.05
		}
		v: f32 = 0.35
		v += min(f32(hostiles_alive()), 16) / 16 * 0.3
		if g.level >= 3 {
			v += 0.1
		}
		boss := find_entity(g.boss_id)
		if boss != nil && boss.kind == .Boss {
			v += 0.3
		}
		if g.wave_state == .Cleared {
			v = 0.3
		}
		return clamp01(v)
	}
	return 0.1
}

frame :: proc() {
	real_dt := min(rl.GetFrameTime(), 0.05)
	g.real_time += real_dt
	g.phase_t += real_dt
	ensure_targets()
	handle_input()

	g.slowmo = max(g.slowmo - real_dt, 0)
	target_scale: f32 = 1
	if g.slowmo > 0 {
		target_scale = 0.28
	}
	g.time_scale = damp(g.time_scale, target_scale, 9, real_dt)
	dt := real_dt * g.time_scale
	if g.phase == .Paused {
		dt = 0
	}
	g.time += dt

	g.pal = palette_lerp(g.pal, g.pal_target, 1 - math.exp(-1.1 * real_dt))
	update_camera(real_dt)
	update_aim()

	switch g.phase {
	case .Title, .Game_Over:
		update_bullets(dt)
		update_missiles(dt)
		update_entities(dt)
		sweep_entities()
	case .Playing:
		update_play(dt, real_dt)
	case .Paused:
	}
	if g.phase != .Paused {
		update_particles(dt)
		update_debris(dt)
		update_lights(dt)
		update_floaters(dt)
		for &m in g.damage_marks {
			m.life = max(m.life - dt, 0)
		}
		g.shield_hit = max(g.shield_hit - dt * 1.6, 0)
		g.hitmarker = max(g.hitmarker - real_dt * 6, 0)
		g.ammo_flash = max(g.ammo_flash - real_dt * 2, 0)
		g.hurt = max(g.hurt - real_dt * 1.8, 0)
	}
	g.flash.a = max(g.flash.a - real_dt * 2.2, 0)
	g.aberr = damp(g.aberr, 0, 3.5, real_dt)
	g.shown_score = damp(g.shown_score, f32(g.score), 9, real_dt)
	if abs(g.shown_score - f32(g.score)) < 0.5 {
		g.shown_score = f32(g.score)
	}

	g.music_t -= real_dt
	if g.music_t <= 0 {
		g.music_t = 0.25
		music_intensity(music_level())
	}

	collect_frame_lights()
	render()
	free_all(context.temp_allocator)
}
