package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

ASTEROID_RADIUS := [3]f32{6.2, 3.5, 1.9}
ASTEROID_HP := [3]f32{7, 3, 1}
ASTEROID_POINTS := [3]int{20, 50, 100}
ASTEROID_CHARGE := [3]f32{0.34, 0.25, 0.2}
ASTEROID_DAMAGE := [3]f32{28, 16, 9}

new_entity :: proc(kind: Entity_Kind, pos: Vec3) -> ^Entity {
	if g.ent_n >= MAX_ENTITIES {
		return nil
	}
	e := &g.ents[g.ent_n]
	g.ent_n += 1
	e^ = {}
	g.next_id += 1
	e.id = g.next_id
	e.kind = kind
	e.pos = pos
	e.rot = rand_quat()
	e.spin_axis = rand_unit()
	e.fwd = norm(-pos)
	e.phase = rand_range(0, math.TAU)
	return e
}

find_entity :: proc(id: u32) -> ^Entity {
	if id == 0 {
		return nil
	}
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if e.id == id && !e.dead {
			return e
		}
	}
	return nil
}

sweep_entities :: proc() {
	i := 0
	for i < g.ent_n {
		if g.ents[i].dead {
			g.ents[i] = g.ents[g.ent_n - 1]
			g.ent_n -= 1
			continue
		}
		i += 1
	}
}

hostiles_alive :: proc() -> int {
	n := 0
	for i in 0 ..< g.ent_n {
		e := &g.ents[i]
		if !e.dead && !e.ambient {
			n += 1
		}
	}
	return n
}

// Targetable by player weapons.
is_target :: proc(e: ^Entity) -> bool {
	if e.dead || e.ambient {
		return false
	}
	if e.kind == .Boss && e.state == 2 {
		return false
	}
	return true
}

asteroid_speed :: proc() -> f32 {
	return min(8.5 + f32(g.level) * 1.25, 27)
}

// Horizontal-ish spawn direction, optionally biased to where the player is looking.
spawn_dir :: proc(front_bias: f32) -> Vec3 {
	ang: f32
	if randf() < front_bias {
		ang = g.yaw + rand_range(-1.1, 1.1)
	} else {
		ang = rand_range(0, math.TAU)
	}
	el := rand_range(-0.2, 0.22)
	return {math.sin(ang) * math.cos(el), math.sin(el), math.cos(ang) * math.cos(el)}
}

spawn_asteroid :: proc(tier: int, pos, vel: Vec3, molten: bool = false, ambient: bool = false) -> ^Entity {
	e := new_entity(.Asteroid, pos)
	if e == nil {
		return nil
	}
	e.tier = tier
	e.radius = ASTEROID_RADIUS[tier] * rand_range(0.85, 1.15)
	e.hp = ASTEROID_HP[tier] + f32(g.level / 4) * f32(2 - tier) * 0.5
	e.max_hp = e.hp
	e.vel = vel
	e.mesh = rand_int(0, 60)
	e.molten = molten
	e.spin = rand_range(0.15, 0.8) * (1 + f32(tier) * 0.8)
	e.ambient = ambient
	return e
}

spawn_wave_asteroid :: proc() {
	dir := spawn_dir(0.55)
	pos := dir * (SPAWN_DIST * rand_range(0.95, 1.1))
	target := rand_unit() * 1.5
	vel := norm(target - pos) * (asteroid_speed() * rand_range(0.85, 1.15))
	molten := randf() < 0.1 + f32(g.level) * 0.01
	spawn_asteroid(0, pos, vel, molten)
}

spawn_drone_pack :: proc() {
	dir := spawn_dir(0.35)
	base := dir * (SPAWN_DIST * 0.95)
	count := 3
	if g.level >= 6 {
		count = 4
	}
	for _ in 0 ..< count {
		e := new_entity(.Drone, base + rand_unit() * 7)
		if e == nil {
			return
		}
		e.radius = 1.7
		e.hp = 2
		e.max_hp = 2
		e.vel = norm(-e.pos) * 15
		e.warp = 1
	}
	emit(.Ring, base, {}, {1, 0.4, 0.9, 1}, {0.5, 0.1, 1, 0}, 2, 26, 0.6)
	sfx_at(.Warp, base, 0.8)
}

spawn_fighter :: proc() {
	dir := spawn_dir(0.4)
	pos := dir * (SPAWN_DIST * 0.85)
	e := new_entity(.Fighter, pos)
	if e == nil {
		return
	}
	e.radius = 3.2
	e.hp = 7 + f32(g.level) * 0.5
	e.max_hp = e.hp
	e.orbit_rad = rand_range(50, 70)
	e.orbit_h = rand_range(-7, 11)
	e.orbit_dir = rand_sign()
	e.orbit_ang = math.atan2(pos.x, pos.z)
	e.timer = rand_range(2.5, 4)
	e.warp = 1
	e.vel = norm(-pos) * 30
	emit(.Ring, pos, {}, {0.6, 0.85, 1, 1}, {0.2, 0.4, 1, 0}, 2, 30, 0.6)
	sfx_at(.Warp, pos)
}

spawn_boss :: proc() {
	ang := g.yaw + rand_range(-0.5, 0.5)
	pos := Vec3{math.sin(ang) * 210, 12, math.cos(ang) * 210}
	e := new_entity(.Boss, pos)
	if e == nil {
		return
	}
	tier := f32(g.level / 5 - 1)
	e.radius = 11
	e.hp = 170 + tier * 80
	e.max_hp = e.hp
	e.orbit_rad = 90
	e.orbit_h = 6
	e.orbit_dir = rand_sign()
	e.orbit_ang = math.atan2(pos.x, pos.z)
	e.timer = 4.5
	e.warp = 1
	e.vel = norm(-pos) * 20
	g.boss_id = e.id
	emit(.Ring, pos, {}, {1, 0.4, 0.4, 1}, {1, 0.1, 0.2, 0}, 5, 120, 1.0)
	emit(.Flare, pos, {}, {1, 0.9, 0.9, 1}, {1, 0.2, 0.2, 0}, 40, 120, 0.9)
	sfx(.Warp, 1, 0, 0.6)
}

fire_bolt :: proc(from: Vec3, dir: Vec3, speed: f32) {
	e := new_entity(.Bolt, from)
	if e == nil {
		return
	}
	e.radius = 1.1
	e.hp = 1
	e.max_hp = 1
	e.vel = dir * speed
	e.fwd = dir
	emit(.Glow, from, {}, {1, 0.7, 0.8, 1}, {1, 0.1, 0.4, 0}, 2, 6, 0.18)
	add_light(from, Vec3{1, 0.3, 0.45} * 2.5, 18, 0.18)
	sfx_at(.Enemy_Fire, from, 0.9, rand_range(0.9, 1.1))
}

spawn_kind :: proc(kind: Entity_Kind) {
	#partial switch kind {
	case .Asteroid:
		spawn_wave_asteroid()
	case .Drone:
		spawn_drone_pack()
	case .Fighter:
		spawn_fighter()
	case .Boss:
		spawn_boss()
	}
}

// ---- per-kind behaviour ---------------------------------------------------------------------

update_entities :: proc(dt: f32) {
	n := g.ent_n
	for i in 0 ..< n {
		e := &g.ents[i]
		if e.dead {
			continue
		}
		e.age += dt
		e.flash = max(e.flash - dt * 7, 0)
		switch e.kind {
		case .Asteroid:
			update_asteroid(e, dt)
		case .Drone:
			e.warp = max(e.warp - dt * 1.4, 0)
			update_drone(e, dt)
		case .Fighter:
			e.warp = max(e.warp - dt * 1.2, 0)
			update_fighter(e, dt)
		case .Boss:
			e.warp = max(e.warp - dt * 0.5, 0)
			update_boss(e, dt)
		case .Bolt, .Nova:
			update_projectile(e, dt)
		}
		if e.dead || e.ambient {
			continue
		}
		dist := length(e.pos)
		if dist > 320 {
			e.dead = true
			continue
		}
		if e.kind != .Boss && !g.dying && g.phase == .Playing && dist < PLAYER_RADIUS + e.radius * 0.75 {
			player_collide(e)
		}
	}
}

update_asteroid :: proc(e: ^Entity, dt: f32) {
	e.rot = quat_mul(quat_axis(e.spin_axis, e.spin * dt), e.rot)
	e.hot = max(e.hot - dt * 0.45, 0)
	if e.ambient {
		e.pos += e.vel * dt
		return
	}
	speed := max(length(e.vel), 1)
	want := asteroid_speed() * (1 + f32(e.tier) * 0.2)
	desired := norm(-e.pos) * max(speed, want * 0.75)
	e.vel += (desired - e.vel) * min(0.3 * dt, 1)
	e.pos += e.vel * dt
	if e.molten {
		e.fx_acc += dt
		if e.fx_acc > 0.08 {
			e.fx_acc = 0
			emit(.Ember, e.pos + rand_unit() * e.radius * 0.9, rand_unit() * 2 - e.vel * 0.1, {1, 0.55, 0.15, 1}, {1, 0.15, 0.02, 0}, 0.4, 0.1, rand_range(0.6, 1.2), 0.5)
		}
	}
}

update_drone :: proc(e: ^Entity, dt: f32) {
	e.phase += dt * 3.4
	dist := length(e.pos)
	to := norm(-e.pos)
	side := perp(to)
	vert := cross(side, to)
	spd := 19 + f32(g.level) * 0.9
	if dist < 45 {
		spd *= 1.7
	}
	wig := 10 * clamp01((dist - 12) / 60)
	desired := to * spd + side * (math.sin(e.phase) * wig) + vert * (math.cos(e.phase * 0.7) * wig * 0.6)
	e.vel = damp3(e.vel, desired, 3, dt)
	e.pos += e.vel * dt
	e.fwd = norm(e.vel)
	e.fx_acc += dt
	if e.fx_acc > 0.035 {
		e.fx_acc = 0
		emit(.Glow, e.pos - e.fwd * 1.6, -e.fwd * 3, {1, 0.3, 0.85, 0.55}, {0.5, 0.1, 0.9, 0}, 0.8, 0.2, 0.4)
	}
}

update_fighter :: proc(e: ^Entity, dt: f32) {
	dist := length(e.pos)
	if e.state == 0 {
		e.vel = damp3(e.vel, norm(-e.pos) * 32, 2, dt)
		if dist < e.orbit_rad + 6 {
			e.state = 1
			e.orbit_ang = math.atan2(e.pos.x, e.pos.z)
		}
	} else {
		e.orbit_ang += e.orbit_dir * (0.2 + f32(g.level) * 0.008) * dt
		r := e.orbit_rad + math.sin(e.age * 0.45) * 10
		target := Vec3{math.sin(e.orbit_ang) * r, e.orbit_h + math.sin(e.age * 0.8) * 4, math.cos(e.orbit_ang) * r}
		desired := (target - e.pos) * 1.4
		if length(desired) > 38 {
			desired = norm(desired) * 38
		}
		e.vel = damp3(e.vel, desired, 2.2, dt)
		e.timer -= dt
		if e.timer < 0.9 {
			if e.charge == 0 {
				sfx_at(.Charge, e.pos, 0.8)
			}
			e.charge = max(clamp01(1 - e.timer / 0.9), 0.01)
		}
		if e.timer <= 0 {
			muzzle := e.pos + e.fwd * (e.radius * 1.9)
			fire_bolt(muzzle, norm(rand_unit() * 1.2 - muzzle), 30 + f32(g.level) * 1.5)
			e.timer = max(1.5, rand_range(2.6, 4.4) - f32(g.level) * 0.08)
			e.charge = 0
		}
	}
	e.pos += e.vel * dt
	face := norm(e.vel)
	if e.charge > 0 {
		face = norm(-e.pos)
	}
	e.fwd = norm(damp3(e.fwd, face, 4, dt))
	e.fx_acc += dt
	if e.fx_acc > 0.03 {
		e.fx_acc = 0
		x, y, z := look_basis(e.fwd, {0, 1, 0})
		s := e.radius * 0.62
		for sx in ([2]f32{-0.8, 0.8}) {
			emit(.Glow, e.pos + (x * sx - y * 0.07 - z * 1.8) * s, -z * 6 + e.vel * 0.3, {1, 0.55, 0.2, 0.5}, {1, 0.2, 0.05, 0}, 0.7, 0.2, 0.3)
		}
	}
}

update_projectile :: proc(e: ^Entity, dt: f32) {
	e.pos += e.vel * dt
	e.fx_acc += dt
	if e.fx_acc > 0.025 {
		e.fx_acc = 0
		if e.kind == .Nova {
			emit(.Glow, e.pos + rand_unit() * e.radius * 0.5, rand_unit() * 1.5, {1, 0.3, 0.8, 0.7}, {0.5, 0.05, 0.6, 0}, e.radius * 1.2, e.radius * 0.3, 0.5)
		} else {
			emit(.Glow, e.pos, rand_unit() * 0.6, {1, 0.25, 0.45, 0.6}, {0.6, 0.05, 0.3, 0}, 0.9, 0.2, 0.3)
		}
	}
}

update_boss :: proc(e: ^Entity, dt: f32) {
	if e.state == 2 {
		boss_dying(e, dt)
		return
	}
	dist := length(e.pos)
	if e.state == 0 {
		want := 24 * clamp01((dist - e.orbit_rad) / 40 + 0.15)
		e.vel = damp3(e.vel, norm(-e.pos) * want, 1.5, dt)
		if dist < e.orbit_rad + 4 {
			e.state = 1
			e.orbit_ang = math.atan2(e.pos.x, e.pos.z)
		}
	} else {
		e.orbit_ang += e.orbit_dir * 0.075 * dt
		target := Vec3{math.sin(e.orbit_ang) * e.orbit_rad, e.orbit_h + math.sin(e.age * 0.3) * 6, math.cos(e.orbit_ang) * e.orbit_rad}
		e.vel = damp3(e.vel, (target - e.pos) * 0.8, 1.5, dt)
		e.timer -= dt
		rage := e.hp < e.max_hp * 0.5
		if e.timer < 1.1 {
			e.charge = clamp01(1 - e.timer / 1.1)
		}
		if e.timer <= 0 {
			boss_attack(e, rage)
			e.attack = (e.attack + 1) % 3
			e.timer = 3.4
			if rage {
				e.timer = 2.4
			}
			e.charge = 0
		}
	}
	e.pos += e.vel * dt
	e.fwd = norm(damp3(e.fwd, norm(-e.pos), 2, dt))
	e.fx_acc += dt
	if e.hp < e.max_hp * 0.5 && e.fx_acc > 0.06 {
		// damaged hull leaks fire
		e.fx_acc = 0
		p := e.pos + rand_unit() * e.radius * 0.7
		emit(.Glow, p, rand_unit() * 3, {1, 0.6, 0.2, 0.8}, {0.6, 0.1, 0.05, 0}, 1.5, 3, 0.5, 1)
		emit(.Smoke, p, rand_unit() * 2, {0.2, 0.18, 0.2, 0.4}, {0.1, 0.1, 0.1, 0}, 1.5, 5, 1.5, 0.6)
	}
}

boss_attack :: proc(e: ^Entity, rage: bool) {
	z := e.fwd
	switch e.attack {
	case 0:
		n := 3
		if rage {
			n = 5
		}
		for _ in 0 ..< n {
			d := new_entity(.Drone, e.pos + rand_unit() * 6 + z * 5)
			if d == nil {
				break
			}
			d.radius = 1.7
			d.hp = 2
			d.max_hp = 2
			d.vel = norm(z + rand_unit() * 0.7) * 26
			d.warp = 0.6
		}
		sfx_at(.Warp, e.pos, 0.9, 1.3)
	case 1:
		n := 7
		if rage {
			n = 11
		}
		base := norm(-e.pos)
		side := perp(base)
		for k in 0 ..< n {
			t := f32(k) / f32(n - 1) * 2 - 1
			dir := norm(base + side * (t * 0.22) + Vec3{0, rand_range(-0.03, 0.03), 0})
			fire_bolt(e.pos + z * 7 + side * (t * 4), dir, 26 + f32(g.level) * 0.8)
		}
	case 2:
		nv := new_entity(.Nova, e.pos + z * 7)
		if nv != nil {
			nv.radius = 2.4
			nv.hp = 6
			nv.max_hp = 6
			nv.vel = norm(-nv.pos) * 13
		}
		emit(.Ring, e.pos + z * 7, {}, {1, 0.4, 0.8, 1}, {0.6, 0.1, 0.5, 0}, 2, 30, 0.5)
		sfx_at(.Enemy_Fire, e.pos, 1.2, 0.5)
	}
}

boss_start_death :: proc(e: ^Entity) {
	e.state = 2
	e.timer = 3.0
	e.charge = 0
	g.slowmo = 0.6
	sfx(.Explode_L, 1, 0, 0.7)
	register_kill(e.pos, 5000, 5)
	add_floater(e.pos + Vec3{0, 14, 0}, "MOTHERSHIP DOWN", {255, 120, 120, 255}, 1.4)
	// drones lose their controller
	for i in 0 ..< g.ent_n {
		o := &g.ents[i]
		if !o.dead && (o.kind == .Drone || o.kind == .Bolt || o.kind == .Nova) {
			kill_entity(o, norm(o.pos - e.pos), true)
		}
	}
}

boss_dying :: proc(e: ^Entity, dt: f32) {
	e.timer -= dt
	e.vel *= math.exp(-1.5 * dt)
	e.pos += e.vel * dt
	e.flash = 0.35 + 0.35 * math.sin(e.age * 34)
	e.fx_acc += dt
	if e.fx_acc > 0.1 {
		e.fx_acc = 0
		p := e.pos + rand_unit() * e.radius * 0.8
		explode(p, rand_range(1.5, 3), .Ship)
		sfx_at(.Explode_S, p, 0.9, rand_range(0.7, 1.1))
		add_trauma(0.1)
	}
	if e.timer <= 0 {
		e.dead = true
		explode(e.pos, 1, .Boss)
		sfx(.Mega)
		add_trauma(1)
		g.flash = {1, 0.9, 0.8, 0.85}
		g.aberr += 0.03
		g.slowmo = 1.2
		g.ammo = MAX_AMMO
		g.ammo_charge = 0
		g.ammo_flash = 1
	}
}

// ---- damage & kills -------------------------------------------------------------------------

hit_entity :: proc(e: ^Entity, dmg: f32, at, dir: Vec3) {
	n := norm(at - e.pos)
	impact_fx(at, n, dir, e.kind)
	e.flash = 1
	e.hp -= dmg
	g.hits += 1
	g.hitmarker = 1
	if e.kind == .Asteroid {
		e.hot = min(e.hot + 0.2, 1)
		e.vel += dir * (2.4 / e.radius)
	}
	sfx_at(.Hit, at, 0.6, rand_range(0.9, 1.15))
	if e.hp <= 0 {
		kill_entity(e, dir, false)
	}
}

kill_entity :: proc(e: ^Entity, dir: Vec3, by_missile: bool) {
	if e.dead {
		return
	}
	if e.kind == .Boss {
		if e.state != 2 {
			boss_start_death(e)
		}
		return
	}
	e.dead = true
	points := 0
	charge: f32 = 0
	switch e.kind {
	case .Asteroid:
		points = ASTEROID_POINTS[e.tier]
		charge = ASTEROID_CHARGE[e.tier]
		if e.molten {
			points *= 2
			charge += 0.5
		}
		tint := Vec3{1, 1, 1}
		if e.molten {
			tint = {0.6, 0.5, 0.5}
		}
		explode(e.pos, e.radius * 0.8, .Rock, tint)
		if e.tier == 0 {
			sfx_at(.Explode_L, e.pos, 0.9, rand_range(0.9, 1.1))
			add_trauma(0.18, e.pos, true)
		} else {
			sfx_at(.Explode_S, e.pos, 0.9, rand_range(0.9, 1.2) + f32(e.tier) * 0.2)
			add_trauma(0.08, e.pos, true)
		}
		if e.tier < 2 && !by_missile {
			to_player := norm(-e.pos)
			n := 2
			if e.tier == 0 && randf() < 0.4 {
				n = 3
			}
			for k in 0 ..< n {
				r := rand_unit()
				r = norm(r - to_player * dot(r, to_player))
				spawn_asteroid(e.tier + 1, e.pos + r * (e.radius * 0.5), e.vel * 0.55 + r * rand_range(5, 11) + dir * 2, e.molten && k == 0)
			}
		}
	case .Drone:
		points = 150
		charge = 0.5
		explode(e.pos, 1.6, .Ship)
		sfx_at(.Explode_S, e.pos, 1, 1.3)
		add_trauma(0.08, e.pos, true)
	case .Fighter:
		points = 400
		charge = 1
		explode(e.pos, 3, .Ship)
		sfx_at(.Explode_L, e.pos, 1, 1.2)
		add_trauma(0.2, e.pos, true)
	case .Bolt:
		points = 25
		charge = 0.06
		explode(e.pos, 1, .Bolt)
		sfx_at(.Pop, e.pos, 0.8, rand_range(0.9, 1.2))
	case .Nova:
		points = 120
		charge = 0.3
		explode(e.pos, 2.5, .Bolt)
		sfx_at(.Explode_S, e.pos, 0.9, 1.4)
	case .Boss:
	}
	register_kill(e.pos, points, charge)
}

combo_mult :: proc() -> int {
	return min(1 + g.combo / 5, 8)
}

register_kill :: proc(pos: Vec3, points: int, charge: f32) {
	g.combo += 1
	g.combo_t = 2.6
	mult := combo_mult()
	pts := points * mult
	g.score += pts
	g.kills += 1
	col := rl.Color{230, 245, 255, 255}
	if mult >= 4 {
		col = {255, 150, 60, 255}
	} else if mult >= 2 {
		col = {255, 220, 90, 255}
	}
	add_floater(pos, fmt.tprintf("+%d", pts), col, 0.8 + min(f32(points) / 600, 1) * 0.5)
	if g.combo % 5 == 0 && mult >= 2 {
		add_floater(pos + Vec3{0, 4, 0}, fmt.tprintf("x%d CHAIN", mult), {255, 170, 60, 255}, 1.2)
	}
	add_ammo_charge(charge, pos)
}

add_ammo_charge :: proc(c: f32, at: Vec3) {
	if g.ammo >= MAX_AMMO {
		g.ammo_charge = 0
		return
	}
	g.ammo_charge += c
	for g.ammo_charge >= 1 && g.ammo < MAX_AMMO {
		g.ammo_charge -= 1
		g.ammo += 1
		g.ammo_flash = 1
		sfx(.Ammo)
		add_floater(at + Vec3{0, 5, 0}, "+1 MISSILE", {255, 200, 90, 255}, 0.9)
	}
	if g.ammo >= MAX_AMMO {
		g.ammo_charge = 0
	}
}

player_collide :: proc(e: ^Entity) {
	dmg: f32
	blast := Blast.Ship
	switch e.kind {
	case .Asteroid:
		dmg = ASTEROID_DAMAGE[e.tier]
		blast = .Rock
	case .Drone:
		dmg = 14
	case .Fighter:
		dmg = 25
	case .Bolt:
		dmg = 9
		blast = .Bolt
	case .Nova:
		dmg = 24
		blast = .Bolt
	case .Boss:
		return
	}
	e.dead = true
	explode(e.pos, e.radius * 0.5, blast)
	sfx_at(.Explode_S, e.pos, 1, 0.8)
	damage_player(dmg, e.pos)
}

// ---- waves ----------------------------------------------------------------------------------

is_boss_level :: proc(level: int) -> bool {
	return level % 5 == 0
}

queue_push :: proc(k: Entity_Kind) {
	if g.queue_n < MAX_QUEUE {
		g.queue[g.queue_n] = k
		g.queue_n += 1
	}
}

build_queue :: proc(level: int) {
	g.queue_n = 0
	g.queue_i = 0
	n_ast := min(3 + level * 2, 26)
	n_packs := 0
	if level >= 2 {
		n_packs = min(level - 1, 9)
	}
	n_fighters := 0
	if level >= 3 {
		n_fighters = min((level - 1) / 2, 8)
	}
	start := 0
	if is_boss_level(level) {
		n_ast /= 2
		n_packs /= 3
		n_fighters = min(n_fighters, 1)
		queue_push(.Boss)
		start = 1
	}
	// open with a couple of rocks so the wave ramps in
	for _ in 0 ..< min(2, n_ast) {
		queue_push(.Asteroid)
	}
	start += min(2, n_ast)
	for _ in 2 ..< max(n_ast, 2) {
		queue_push(.Asteroid)
	}
	for _ in 0 ..< n_packs {
		queue_push(.Drone)
	}
	for _ in 0 ..< n_fighters {
		queue_push(.Fighter)
	}
	for i := g.queue_n - 1; i > start; i -= 1 {
		j := rand_int(start, i + 1)
		g.queue[i], g.queue[j] = g.queue[j], g.queue[i]
	}
	g.spawn_interval = max(0.85, 2.5 - f32(level) * 0.13)
}

start_wave :: proc(level: int) {
	g.level = level
	g.wave_state = .Intro
	g.wave_t = 0
	g.pal_target = palette_for_level(level)
	build_queue(level)
	if is_boss_level(level) {
		sfx(.Boss)
	} else {
		sfx(.Wave)
	}
}

update_waves :: proc(dt: f32) {
	switch g.wave_state {
	case .Intro:
		g.wave_t += dt
		if g.wave_t >= 2.6 {
			g.wave_state = .Active
			g.spawn_t = 0
		}
	case .Active:
		g.spawn_t -= dt
		alive := hostiles_alive()
		if g.queue_i < g.queue_n && alive == 0 && g.spawn_t > 0.5 {
			g.spawn_t = 0.5
		}
		if g.queue_i < g.queue_n && g.spawn_t <= 0 {
			k := g.queue[g.queue_i]
			g.queue_i += 1
			spawn_kind(k)
			g.spawn_t = g.spawn_interval * rand_range(0.7, 1.3)
			if k == .Boss {
				g.spawn_t = 6
			}
		}
		if g.queue_i >= g.queue_n && alive == 0 {
			g.wave_state = .Cleared
			g.wave_t = 0
			g.score += 250 * g.level
			g.hull = min(g.hull + 15, 100)
			g.shield = 100
			sfx(.Clear)
		}
	case .Cleared:
		g.wave_t += dt
		if g.wave_t >= 3.8 {
			start_wave(g.level + 1)
		}
	}
}

// ---- title backdrop -------------------------------------------------------------------------

spawn_ambient_field :: proc() {
	for _ in 0 ..< 18 {
		ang := rand_range(0, math.TAU)
		dist := rand_range(35, 150)
		pos := Vec3{math.sin(ang) * dist, rand_range(-18, 18), math.cos(ang) * dist}
		tangent := norm(cross({0, 1, 0}, pos))
		tier := rand_int(0, 3)
		spawn_asteroid(tier, pos, tangent * rand_range(1, 4) + rand_unit() * 0.5, randf() < 0.2, true)
	}
}
