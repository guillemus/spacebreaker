package game

import "core:math"
import rl "vendor:raylib"

emit :: proc(
	kind: Particle_Kind,
	pos, vel: Vec3,
	c0, c1: Vec4,
	s0, s1, life: f32,
	drag: f32 = 0,
	stretch: f32 = 0,
) {
	if g.part_n >= MAX_PARTICLES || life <= 0 {
		return
	}
	g.parts[g.part_n] = Particle {
		pos       = pos,
		vel       = vel,
		c0        = c0,
		c1        = c1,
		s0        = s0,
		s1        = s1,
		life      = life,
		max_life  = life,
		drag      = drag,
		rot       = rand_range(0, math.TAU),
		rot_speed = rand_range(-1.5, 1.5),
		stretch   = stretch,
		kind      = kind,
	}
	g.part_n += 1
}

update_particles :: proc(dt: f32) {
	i := 0
	for i < g.part_n {
		p := &g.parts[i]
		p.life -= dt
		if p.life <= 0 {
			g.parts[i] = g.parts[g.part_n - 1]
			g.part_n -= 1
			continue
		}
		if p.drag > 0 {
			p.vel *= math.exp(-p.drag * dt)
		}
		p.pos += p.vel * dt
		p.rot += p.rot_speed * dt
		i += 1
	}
}

add_light :: proc(pos, col: Vec3, radius, life: f32) {
	if g.light_n >= MAX_LIGHTS {
		return
	}
	g.lights[g.light_n] = {pos, col, radius, life, life}
	g.light_n += 1
}

update_lights :: proc(dt: f32) {
	i := 0
	for i < g.light_n {
		l := &g.lights[i]
		l.life -= dt
		if l.life <= 0 {
			g.lights[i] = g.lights[g.light_n - 1]
			g.light_n -= 1
			continue
		}
		i += 1
	}
}

add_trauma :: proc(amount: f32, at: Vec3 = {}, use_pos: bool = false) {
	k := amount
	if use_pos {
		k *= 1 / (1 + length(at) * 0.015)
	}
	g.trauma = min(g.trauma + k, 1)
}

add_floater :: proc(pos: Vec3, text: string, col: rl.Color, size: f32 = 1) {
	if g.floater_n >= MAX_FLOATERS {
		return
	}
	f := &g.floaters[g.floater_n]
	g.floater_n += 1
	f.pos = pos
	f.n = min(len(text), len(f.text) - 1)
	copy(f.text[:], text[:f.n])
	f.text[f.n] = 0
	f.col = col
	f.life = 1.3
	f.max_life = 1.3
	f.size = size
}

update_floaters :: proc(dt: f32) {
	i := 0
	for i < g.floater_n {
		f := &g.floaters[i]
		f.life -= dt
		if f.life <= 0 {
			g.floaters[i] = g.floaters[g.floater_n - 1]
			g.floater_n -= 1
			continue
		}
		f.pos.y += dt * 4
		i += 1
	}
}

spawn_debris :: proc(pos, vel: Vec3, scale: f32, metal: bool, tint: Vec3, hot: f32) {
	if g.debris_n >= MAX_DEBRIS {
		return
	}
	life := rand_range(1.8, 3.6)
	g.debris[g.debris_n] = Debris {
		pos       = pos,
		vel       = vel,
		rot       = rand_quat(),
		spin_axis = rand_unit(),
		spin      = rand_range(2, 8),
		scale     = scale,
		life      = life,
		max_life  = life,
		mesh      = rand_int(0, N_CHUNKS),
		metal     = metal,
		tint      = tint,
		hot       = hot,
	}
	g.debris_n += 1
}

update_debris :: proc(dt: f32) {
	i := 0
	for i < g.debris_n {
		d := &g.debris[i]
		d.life -= dt
		if d.life <= 0 {
			g.debris[i] = g.debris[g.debris_n - 1]
			g.debris_n -= 1
			continue
		}
		d.pos += d.vel * dt
		d.vel *= math.exp(-0.25 * dt)
		d.rot = quat_mul(quat_axis(d.spin_axis, d.spin * dt), d.rot)
		d.hot = max(d.hot - dt * 0.6, 0)
		d.smoke_acc += dt
		if d.hot > 0.2 && d.smoke_acc > 0.05 {
			d.smoke_acc = 0
			emit(
				.Ember,
				d.pos,
				d.vel * 0.2 + rand_unit() * 0.5,
				{1.0, 0.6, 0.2, 0.9 * d.hot},
				{1.0, 0.2, 0.05, 0},
				d.scale * 0.5,
				d.scale * 0.2,
				rand_range(0.3, 0.6),
				1,
			)
			if d.metal {
				emit(
					.Smoke,
					d.pos,
					rand_unit() * 0.4,
					{0.25, 0.22, 0.24, 0.35},
					{0.1, 0.1, 0.12, 0},
					d.scale * 0.6,
					d.scale * 2.4,
					rand_range(0.8, 1.4),
					0.5,
				)
			}
		}
		i += 1
	}
}

// ---- explosion recipes ----------------------------------------------------------------------

Blast :: enum {
	Rock,
	Ship,
	Missile,
	Bolt,
	Boss,
	Impact,
}

explode :: proc(pos: Vec3, scale: f32, kind: Blast, tint: Vec3 = {1, 1, 1}) {
	s := scale
	switch kind {
	case .Rock:
		emit(.Glow, pos, {}, {1, 0.95, 0.85, 1}, {1, 0.5, 0.2, 0}, s * 2.2, s * 4.5, 0.16)
		emit(.Flare, pos, {}, {1, 0.9, 0.7, 1}, {1, 0.4, 0.1, 0}, s * 3, s * 7, 0.22)
		for _ in 0 ..< int(8 + s * 3) {
			emit(
				.Glow,
				pos + rand_unit() * s * 0.4,
				rand_unit() * rand_range(2, 9) * s * 0.5,
				{1, 0.78, 0.4, 0.9},
				{0.55, 0.1, 0.04, 0},
				s * rand_range(0.5, 1.0),
				s * rand_range(1.2, 2.0),
				rand_range(0.3, 0.75),
				3,
			)
		}
		for _ in 0 ..< int(10 + s * 4) {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(18, 50),
				{1, 0.9, 0.6, 1},
				{1, 0.35, 0.1, 0},
				0.16,
				0.05,
				rand_range(0.3, 0.8),
				1.8,
				0.045,
			)
		}
		for _ in 0 ..< int(5 + s * 2) {
			emit(
				.Smoke,
				pos + rand_unit() * s * 0.6,
				rand_unit() * rand_range(1, 4) * s * 0.4,
				{0.34, 0.31, 0.3, 0.32},
				{0.16, 0.15, 0.17, 0},
				s * 0.6,
				s * 2.0,
				rand_range(1.2, 2.4),
				1.2,
			)
		}
		for _ in 0 ..< 10 {
			emit(
				.Ember,
				pos + rand_unit() * s * 0.5,
				rand_unit() * rand_range(3, 12),
				{1, 0.65, 0.25, 1},
				{1, 0.25, 0.05, 0},
				0.3,
				0.1,
				rand_range(0.8, 1.8),
				0.8,
			)
		}
		emit(.Ring, pos, {}, {1, 0.75, 0.45, 0.8}, {1, 0.3, 0.1, 0}, s * 0.6, s * 5.5, 0.45)
		for _ in 0 ..< int(3 + s * 0.8) {
			spawn_debris(
				pos + rand_unit() * s * 0.5,
				rand_unit() * rand_range(4, 16),
				s * rand_range(0.14, 0.3),
				false,
				tint,
				rand_range(0.3, 1),
			)
		}
		add_light(pos, Vec3{1.0, 0.6, 0.3} * 3.5, 22 + s * 6, 0.5)
	case .Ship:
		emit(.Glow, pos, {}, {1, 1, 1, 1}, {0.5, 0.7, 1, 0}, s * 3, s * 6, 0.18)
		emit(.Flare, pos, {}, {0.8, 0.9, 1, 1}, {0.4, 0.5, 1, 0}, s * 5, s * 10, 0.3)
		for _ in 0 ..< int(14 + s * 3) {
			emit(
				.Glow,
				pos + rand_unit() * s * 0.3,
				rand_unit() * rand_range(3, 12) * s * 0.5,
				{1, 0.7, 0.35, 1},
				{0.6, 0.08, 0.1, 0},
				s * rand_range(0.6, 1.1),
				s * rand_range(1.4, 2.4),
				rand_range(0.35, 0.9),
				2.5,
			)
		}
		for _ in 0 ..< int(20 + s * 5) {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(25, 70),
				{0.7, 0.9, 1, 1},
				{0.3, 0.4, 1, 0},
				0.14,
				0.05,
				rand_range(0.3, 0.9),
				1.5,
				0.04,
			)
		}
		for _ in 0 ..< int(6 + s * 2) {
			emit(
				.Smoke,
				pos + rand_unit() * s * 0.5,
				rand_unit() * rand_range(1, 4),
				{0.2, 0.18, 0.22, 0.55},
				{0.08, 0.08, 0.1, 0},
				s * 0.7,
				s * 2.6,
				rand_range(1.3, 2.4),
				1,
			)
		}
		emit(.Ring, pos, {}, {0.6, 0.85, 1, 0.9}, {0.3, 0.4, 1, 0}, s * 0.5, s * 7, 0.5)
		for _ in 0 ..< int(4 + s) {
			spawn_debris(
				pos,
				rand_unit() * rand_range(8, 22),
				s * rand_range(0.3, 0.6),
				true,
				{1, 1, 1},
				1,
			)
		}
		add_light(pos, Vec3{0.8, 0.7, 1.0} * 4, 28 + s * 6, 0.55)
	case .Missile:
		emit(.Glow, pos, {}, {1, 1, 0.95, 1}, {1, 0.6, 0.3, 0}, 10, 26, 0.2)
		emit(.Flare, pos, {}, {1, 0.95, 0.8, 1}, {1, 0.5, 0.2, 0}, 18, 40, 0.35)
		for _ in 0 ..< 36 {
			emit(
				.Glow,
				pos + rand_unit() * 2,
				rand_unit() * rand_range(6, 26),
				{1, 0.8, 0.4, 1},
				{0.7, 0.12, 0.05, 0},
				rand_range(2.5, 5),
				rand_range(6, 11),
				rand_range(0.4, 1.0),
				2.8,
			)
		}
		for _ in 0 ..< 60 {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(35, 95),
				{1, 0.95, 0.7, 1},
				{1, 0.4, 0.1, 0},
				0.22,
				0.06,
				rand_range(0.4, 1.1),
				1.4,
				0.05,
			)
		}
		for _ in 0 ..< 18 {
			emit(
				.Smoke,
				pos + rand_unit() * 4,
				rand_unit() * rand_range(2, 7),
				{0.3, 0.26, 0.26, 0.5},
				{0.12, 0.1, 0.12, 0},
				rand_range(4, 7),
				rand_range(12, 18),
				rand_range(1.6, 3.0),
				1.1,
			)
		}
		for _ in 0 ..< 20 {
			emit(
				.Ember,
				pos + rand_unit() * 3,
				rand_unit() * rand_range(8, 30),
				{1, 0.7, 0.3, 1},
				{1, 0.2, 0.05, 0},
				0.5,
				0.15,
				rand_range(1, 2.2),
				1,
			)
		}
		emit(.Ring, pos, {}, {1, 0.85, 0.6, 1}, {1, 0.35, 0.1, 0}, 3, 38, 0.55)
		emit(.Ring, pos, {}, {0.6, 0.8, 1, 0.6}, {0.2, 0.3, 1, 0}, 2, 24, 0.35)
		add_light(pos, Vec3{1.0, 0.65, 0.3} * 6, 70, 0.7)
	case .Bolt:
		emit(.Glow, pos, {}, {1, 0.6, 0.8, 1}, {1, 0.1, 0.4, 0}, s * 2, s * 5, 0.2)
		for _ in 0 ..< 12 {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(15, 40),
				{1, 0.5, 0.8, 1},
				{1, 0.1, 0.4, 0},
				0.12,
				0.04,
				rand_range(0.2, 0.5),
				2,
				0.04,
			)
		}
		emit(.Ring, pos, {}, {1, 0.4, 0.7, 0.8}, {1, 0.1, 0.4, 0}, s * 0.5, s * 5, 0.3)
		add_light(pos, Vec3{1.0, 0.3, 0.6} * 2.5, 16, 0.3)
	case .Boss:
		emit(.Glow, pos, {}, {1, 1, 1, 1}, {1, 0.5, 0.3, 0}, 30, 90, 0.5)
		emit(.Flare, pos, {}, {1, 0.95, 0.9, 1}, {1, 0.4, 0.3, 0}, 60, 160, 0.8)
		for _ in 0 ..< 90 {
			emit(
				.Glow,
				pos + rand_unit() * 6,
				rand_unit() * rand_range(10, 45),
				{1, 0.75, 0.4, 1},
				{0.7, 0.1, 0.1, 0},
				rand_range(4, 8),
				rand_range(10, 20),
				rand_range(0.8, 2.0),
				1.6,
			)
		}
		for _ in 0 ..< 160 {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(40, 140),
				{1, 0.95, 0.8, 1},
				{1, 0.3, 0.2, 0},
				0.35,
				0.08,
				rand_range(0.6, 1.8),
				0.9,
				0.05,
			)
		}
		for _ in 0 ..< 40 {
			emit(
				.Smoke,
				pos + rand_unit() * 8,
				rand_unit() * rand_range(3, 10),
				{0.3, 0.24, 0.26, 0.6},
				{0.1, 0.08, 0.1, 0},
				rand_range(8, 12),
				rand_range(22, 34),
				rand_range(2.5, 4.5),
				0.8,
			)
		}
		for _ in 0 ..< 60 {
			emit(
				.Ember,
				pos + rand_unit() * 6,
				rand_unit() * rand_range(10, 50),
				{1, 0.7, 0.3, 1},
				{1, 0.2, 0.05, 0},
				0.9,
				0.2,
				rand_range(1.5, 3.5),
				0.6,
			)
		}
		emit(.Ring, pos, {}, {1, 0.9, 0.7, 1}, {1, 0.3, 0.2, 0}, 5, 140, 1.1)
		emit(.Ring, pos, {}, {0.7, 0.8, 1, 0.8}, {0.3, 0.3, 1, 0}, 4, 90, 0.8)
		for _ in 0 ..< 30 {
			spawn_debris(
				pos + rand_unit() * 5,
				rand_unit() * rand_range(10, 35),
				rand_range(0.8, 2.2),
				true,
				{1, 1, 1},
				1,
			)
		}
		add_light(pos, Vec3{1.0, 0.7, 0.5} * 8, 160, 1.4)
	case .Impact:
		emit(.Glow, pos, {}, {1, 0.9, 0.8, 1}, {1, 0.3, 0.1, 0}, s * 1.5, s * 3, 0.14)
		for _ in 0 ..< 8 {
			emit(
				.Spark,
				pos,
				rand_unit() * rand_range(10, 30),
				{1, 0.8, 0.5, 1},
				{1, 0.3, 0.1, 0},
				0.1,
				0.04,
				rand_range(0.2, 0.5),
				2,
				0.04,
			)
		}
	}
}

// Sparks and dust where a plasma bolt meets something.
impact_fx :: proc(pos, normal, bullet_dir: Vec3, kind: Entity_Kind) {
	reflect := norm(bullet_dir - normal * (2 * dot(bullet_dir, normal)))
	emit(.Glow, pos, {}, {0.8, 0.95, 1, 1}, {0.3, 0.6, 1, 0}, 0.8, 2.2, 0.1)
	for _ in 0 ..< 7 {
		v := norm(reflect + rand_unit() * 0.7 + normal * 0.4) * rand_range(12, 38)
		col := Vec4{1, 0.85, 0.5, 1}
		if kind != .Asteroid {
			col = {0.6, 0.9, 1, 1}
		}
		emit(.Spark, pos, v, col, {1, 0.3, 0.1, 0}, 0.09, 0.03, rand_range(0.15, 0.4), 2.5, 0.035)
	}
	if kind == .Asteroid {
		for _ in 0 ..< 2 {
			emit(
				.Smoke,
				pos,
				normal * rand_range(1, 4) + rand_unit(),
				{0.4, 0.35, 0.32, 0.45},
				{0.2, 0.18, 0.18, 0},
				0.4,
				1.6,
				rand_range(0.6, 1.1),
				1.5,
			)
		}
		emit(
			.Ember,
			pos,
			normal * rand_range(4, 10) + rand_unit() * 3,
			{1, 0.6, 0.2, 1},
			{1, 0.2, 0.05, 0},
			0.18,
			0.05,
			rand_range(0.4, 0.9),
			1,
		)
	}
	add_light(pos, Vec3{0.4, 0.8, 1.0} * 1.6, 9, 0.08)
}
