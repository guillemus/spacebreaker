package game

import "core:math"
import rl "vendor:raylib"

// ---- camera ---------------------------------------------------------------------------------

// Mouse x beyond this fraction of half-width starts turning the camera.
TURN_DEADZONE :: f32(0.3)

// Desktop test harness: overrides the OS mouse position when set.
debug_mouse: Maybe(Vec2)

update_camera :: proc(real_dt: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	g.aspect = sw / max(sh, 1)
	g.mouse = rl.GetMousePosition()
	if dm, ok := debug_mouse.?; ok {
		g.mouse = dm
	}

	turn: f32 = 0
	if g.phase == .Playing && !g.dying {
		nx := clamp(g.mouse.x / sw * 2 - 1, -1, 1)
		t := clamp01((abs(nx) - TURN_DEADZONE) / (1 - TURN_DEADZONE))
		turn = math.pow(t, 1.4)
		if nx < 0 {
			turn = -turn
		}
		if !rl.IsCursorOnScreen() {
			turn = 0
		}
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
			turn = -1
		}
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
			turn = 1
		}
	} else if g.phase == .Title {
		turn = 0.035
	} else if g.phase == .Game_Over {
		turn = 0.02
	}

	g.yaw_vel = damp(g.yaw_vel, -turn * MAX_TURN, 7, real_dt)
	g.yaw += g.yaw_vel * real_dt
	g.roll = damp(g.roll, -g.yaw_vel * 0.07, 5, real_dt)
	g.fov_kick = damp(g.fov_kick, 0, 5, real_dt)
	g.trauma = max(g.trauma - real_dt * 1.1, 0)

	fwd := Vec3{math.sin(g.yaw), 0, math.cos(g.yaw)}
	right := norm(cross(fwd, {0, 1, 0}))
	up := cross(right, fwd)
	g.fwd = fwd
	g.right = right
	g.up = up
	fovy := BASE_FOV + g.fov_kick
	g.cam = rl.Camera3D {
		position   = {0, 0, 0},
		target     = fwd,
		up         = up,
		fovy       = fovy,
		projection = .PERSPECTIVE,
	}
	g.tan_half = math.tan(fovy * math.RAD_PER_DEG * 0.5)

	// render camera: bank + trauma shake
	shake := g.trauma * g.trauma
	t := g.real_time
	yaw_s := shake * 0.05 * (math.sin(t * 37.3) * 0.6 + math.sin(t * 21.7 + 1.3) * 0.4)
	pitch_s := shake * 0.04 * (math.sin(t * 41.1 + 0.7) * 0.6 + math.sin(t * 17.9 + 2.1) * 0.4)
	roll_s := shake * 0.06 * math.sin(t * 29.3 + 0.3)
	pos_s :=
		Vec3{math.sin(t * 53.1), math.sin(t * 47.7 + 1.1), math.sin(t * 43.3 + 2.3)} *
		(shake * 0.25)
	rf := norm(fwd + right * yaw_s + up * pitch_s)
	rr := norm(cross(rf, {0, 1, 0}))
	ru := cross(rr, rf)
	roll := g.roll + roll_s
	ru2 := ru * math.cos(roll) + rr * math.sin(roll)
	rr2 := norm(cross(rf, ru2))
	g.rfwd = rf
	g.rright = rr2
	g.rup = ru2
	g.rcam = rl.Camera3D {
		position   = pos_s,
		target     = pos_s + rf,
		up         = ru2,
		fovy       = fovy,
		projection = .PERSPECTIVE,
	}
}

update_aim :: proc() {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	nx := g.mouse.x / sw * 2 - 1
	ny := 1 - g.mouse.y / sh * 2
	g.aim_dir = norm(g.fwd + g.right * (nx * g.tan_half * g.aspect) + g.up * (ny * g.tan_half))
	best: f32 = 120
	g.aim_hit = 0
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) {
			continue
		}
		ok, t := ray_sphere(g.cam.position, g.aim_dir, e.pos, e.radius * 1.05)
		if ok && t > 2 && t < best {
			best = t
			g.aim_hit = e.id
		}
	}
	g.aim_point = g.cam.position + g.aim_dir * best
}

// ---- weapons --------------------------------------------------------------------------------

update_weapons :: proc(dt: f32) {
	g.fire_cd -= dt
	g.missile_cd -= dt
	for s in 0 ..< 2 {
		g.recoil[s] = max(g.recoil[s] - dt * 7, 0)
		g.muzzle[s] = max(g.muzzle[s] - dt * 14, 0)
	}
	g.spread = max(g.spread - dt * 2.5, 0)

	// fire_lock swallows the click that started/resumed the game until the button is released
	firing := (rl.IsMouseButtonDown(.LEFT) && !g.fire_lock) || rl.IsKeyDown(.SPACE)
	if g.overheated {
		g.heat -= dt * 0.55
		for side in 0 ..< 2 {
			if randf() < 0.5 {
				_, tip, z := gun_transform(side)
				emit(
					.Smoke,
					tip - z * 0.5,
					g.up * rand_range(1, 2.5) + rand_unit() * 0.4,
					{0.8, 0.85, 0.9, 0.22},
					{0.6, 0.6, 0.7, 0},
					0.1,
					0.7,
					rand_range(0.5, 0.9),
					1,
				)
			}
		}
		if g.heat <= 0.3 {
			g.overheated = false
		}
	} else {
		if firing && g.fire_cd <= 0 {
			fire_bullet()
			g.fire_cd = FIRE_INTERVAL
		}
		cool: f32 = 0.8
		if firing {
			cool = 0.3
		}
		g.heat = max(g.heat - dt * cool, 0)
		if g.heat >= 1 {
			g.heat = 1
			g.overheated = true
			sfx(.Overheat)
		}
	}
	if !firing && g.fire_cd < 0 {
		g.fire_cd = 0
	}

	if rl.IsMouseButtonPressed(.RIGHT) || rl.IsKeyPressed(.F) {
		fire_missile()
	}
}

fire_bullet :: proc() {
	side := g.gun_side
	g.gun_side = 1 - side
	_, tip, z := gun_transform(side)
	to_aim := g.aim_point - tip
	jitter := 0.002 + g.spread * 0.01
	dir := norm(to_aim + rand_unit() * (length(to_aim) * jitter))
	if g.bullet_n < MAX_BULLETS {
		g.bullets[g.bullet_n] = Bullet {
			pos    = tip,
			prev   = tip,
			origin = tip,
			vel    = dir * BULLET_SPEED,
			life   = 1.1,
			side   = side,
		}
		g.bullet_n += 1
	}
	g.recoil[side] = 1
	g.muzzle[side] = 1
	g.spread = min(g.spread + 0.22, 1)
	g.heat += 0.042
	g.shots += 1
	add_light(tip + z * 5, Vec3{0.4, 0.85, 1.0} * 1.5, 12, 0.07)
	for _ in 0 ..< 3 {
		emit(
			.Spark,
			tip + z * 0.2,
			norm(z + rand_unit() * 0.35) * rand_range(8, 20),
			{0.7, 0.95, 1, 1},
			{0.2, 0.5, 1, 0},
			0.018,
			0.005,
			rand_range(0.06, 0.14),
			3,
			0.012,
		)
	}
	pan: f32 = -0.35
	if side == 1 {
		pan = 0.35
	}
	sfx(.Shoot, 0.8, pan, rand_range(0.94, 1.06))
}

// Entity closest to a direction from the player, within a cone.
best_target_in_cone :: proc(dir: Vec3, min_dot: f32) -> u32 {
	best: u32 = 0
	best_score: f32 = -1
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) || e.kind == .Bolt {
			continue
		}
		d := dot(norm(e.pos), dir)
		if d > min_dot && d > best_score {
			best_score = d
			best = e.id
		}
	}
	return best
}

fire_missile :: proc() {
	if g.missile_cd > 0 {
		return
	}
	if g.ammo <= 0 {
		sfx(.Empty)
		g.missile_cd = 0.6
		add_floater(g.aim_point, "NO MISSILES", {255, 90, 90, 255}, 0.8)
		return
	}
	if g.missile_n >= MAX_MISSILES {
		return
	}
	g.ammo -= 1
	side := g.missile_side
	g.missile_side = 1 - side
	sgn: f32 = -1
	if side == 1 {
		sgn = 1
	}
	target := g.lock_id
	if target == 0 {
		target = best_target_in_cone(g.aim_dir, 0.94)
	}
	pos := g.cam.position - g.up * 1.3 + g.fwd * 3.2 + g.right * (sgn * 1.1)
	vel := g.fwd * 26 - g.up * 2 + g.right * (sgn * 9)
	m := &g.missiles[g.missile_n]
	g.missile_n += 1
	m^ = Missile {
		pos    = pos,
		vel    = vel,
		target = target,
		aim    = g.cam.position + g.aim_dir * 160,
		seed   = rand_range(0, 100),
	}
	g.missile_cd = 0.2
	g.fov_kick += 2.5
	add_trauma(0.12)
	sfx(.Missile, 1, sgn * 0.3)
	for _ in 0 ..< 10 {
		emit(
			.Smoke,
			pos + rand_unit() * 0.3,
			rand_unit() * 2.5 - g.fwd * 1.5,
			{0.7, 0.7, 0.75, 0.3},
			{0.4, 0.4, 0.45, 0},
			0.2,
			1.2,
			rand_range(0.5, 0.9),
			2,
		)
	}
	emit(.Glow, pos, {}, {1, 0.8, 0.5, 1}, {1, 0.4, 0.1, 0}, 0.5, 1.2, 0.1)
}

// Nearest hostile roughly ahead of a missile.
acquire_target :: proc(pos, dir: Vec3) -> u32 {
	best: u32 = 0
	best_d: f32 = 1e9
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) {
			continue
		}
		to := e.pos - pos
		d := length(to)
		if dot(to / max(d, 0.01), dir) < 0.35 {
			continue
		}
		if d < best_d {
			best_d = d
			best = e.id
		}
	}
	return best
}

update_missiles :: proc(dt: f32) {
	i := 0
	for i < g.missile_n {
		m := &g.missiles[i]
		m.age += dt
		t := find_entity(m.target)
		if t == nil && m.age > 0.2 {
			m.target = acquire_target(m.pos, norm(m.vel))
			t = find_entity(m.target)
		}
		desired := norm(m.aim - m.pos)
		if t != nil {
			lead := length(t.pos - m.pos) / max(length(m.vel), 1)
			desired = norm(t.pos + t.vel * (lead * 0.6) - m.pos)
		}
		speed := min(28 + m.age * 150, 125)
		d := norm(m.vel)
		if m.age > 0.12 {
			k := min(7.5 * dt, 1)
			d = norm(d + (desired - d) * k)
		}
		wob := perp(d) * (math.sin(m.age * 17 + m.seed) * 0.02)
		m.vel = norm(d + wob) * speed
		prev := m.pos
		m.pos += m.vel * dt

		m.trail_acc += dt
		if m.trail_acc >= 0.016 {
			m.trail_acc = 0
			if m.trail_n < MISSILE_TRAIL {
				m.trail[m.trail_n] = m.pos
				m.trail_n += 1
			} else {
				for k in 0 ..< MISSILE_TRAIL - 1 {
					m.trail[k] = m.trail[k + 1]
				}
				m.trail[MISSILE_TRAIL - 1] = m.pos
			}
		}
		// smoke along the path
		m.smoke_acc += length(m.pos - prev)
		for m.smoke_acc > 0.9 {
			m.smoke_acc -= 0.9
			p := m.pos - d * (1 + m.smoke_acc)
			emit(
				.Smoke,
				p,
				rand_unit() * 0.6,
				{0.75, 0.72, 0.72, 0.32},
				{0.35, 0.33, 0.36, 0},
				0.35,
				rand_range(1.6, 2.6),
				rand_range(0.9, 1.5),
				1.2,
			)
			emit(
				.Glow,
				p,
				-d * 4 + rand_unit(),
				{1, 0.6, 0.2, 0.6},
				{1, 0.2, 0.05, 0},
				0.6,
				0.2,
				0.18,
				2,
			)
		}

		boom := m.age > 5 || length(m.pos) > 300
		for j in 0 ..< g.ent_n {
			e := &g.ents[j]
			if !is_target(e) {
				continue
			}
			if length(e.pos - m.pos) < e.radius + 1.6 {
				boom = true
				break
			}
		}
		if boom {
			missile_explode(m.pos)
			g.missiles[i] = g.missiles[g.missile_n - 1]
			g.missile_n -= 1
			continue
		}
		i += 1
	}
}

MISSILE_BLAST :: f32(17)

missile_explode :: proc(pos: Vec3) {
	explode(pos, 1, .Missile)
	sfx_at(.Explode_L, pos, 1.2, 0.85)
	add_trauma(0.45, pos, true)
	g.aberr += 0.012
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) {
			continue
		}
		d := length(e.pos - pos) - e.radius
		if d >= MISSILE_BLAST {
			continue
		}
		dmg := 22 * (1 - clamp01(d / MISSILE_BLAST) * 0.5)
		if e.kind == .Boss {
			dmg = 18
		}
		away := norm(e.pos - pos)
		e.flash = 1
		e.hp -= dmg
		if e.kind == .Asteroid {
			e.hot = 1
			e.vel += away * 6
		}
		if e.hp <= 0 {
			kill_entity(e, away, true)
		}
	}
}

// ---- lock-on --------------------------------------------------------------------------------

update_lock :: proc(dt: f32) {
	u := ui_scale()
	best: u32 = 0
	best_score: f32 = 1e9
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !is_target(e) || e.kind == .Bolt {
			continue
		}
		sp, ok := project(e.pos)
		if !ok {
			continue
		}
		d := length2(sp - g.mouse)
		if d > 120 * u + projected_radius(e.pos, e.radius) {
			continue
		}
		score := d + length(e.pos) * 0.3
		if score < best_score {
			best_score = score
			best = e.id
		}
	}
	if best != g.lock_id {
		g.lock_id = best
		g.lock_t = 0
		g.lock_beeped = false
	} else if best != 0 {
		g.lock_t = min(g.lock_t + dt * 3.2, 1)
		if g.lock_t >= 1 && !g.lock_beeped {
			g.lock_beeped = true
			if g.ammo > 0 {
				sfx(.Lock)
			}
		}
	}
}

// ---- damage ---------------------------------------------------------------------------------

damage_player :: proc(amount: f32, from: Vec3) {
	if g.dying || g.phase != .Playing {
		return
	}
	dir := norm(from)
	left := amount
	if g.shield > 0 {
		absorbed := min(g.shield, left)
		g.shield -= absorbed
		left -= absorbed
		g.shield_hit = 1
		g.shield_hit_dir = dir
		sfx(.Shield_Hit, 1, clamp(dot(dir, g.right), -1, 1) * 0.6)
		if g.shield <= 0 {
			add_floater(g.aim_point, "SHIELD DOWN", {255, 90, 90, 255}, 1.1)
		}
	}
	if left > 0 {
		g.hull -= left
		g.hurt = 1
		g.aberr += 0.02
		sfx(.Hull_Hit, 1, clamp(dot(dir, g.right), -1, 1) * 0.6)
		g.flash = {1, 0.15, 0.1, 0.25}
	}
	g.shield_delay = 3
	add_trauma(0.35 + amount * 0.012)
	g.combo = 0
	// damage direction marker
	slot := 0
	for k in 0 ..< MAX_DAMAGE_MARKS {
		if g.damage_marks[k].life < g.damage_marks[slot].life {
			slot = k
		}
	}
	g.damage_marks[slot] = {dir, 1.4}
	if g.hull <= 0 {
		g.hull = 0
		start_death()
	}
}

update_shield :: proc(dt: f32) {
	if g.shield_delay > 0 {
		g.shield_delay -= dt
		return
	}
	if g.shield < 100 {
		g.shield = min(g.shield + dt * 16, 100)
	}
}

start_death :: proc() {
	g.dying = true
	g.dead_t = 0
	g.slowmo = 1.6
	sfx(.Game_Over)
	sfx(.Mega)
	for _ in 0 ..< 6 {
		explode(g.fwd * 7 + rand_unit() * 4, 2.5, .Ship)
	}
	g.flash = {1, 0.5, 0.3, 0.8}
	g.aberr += 0.05
	add_trauma(1)
	death_shockwave()
}
