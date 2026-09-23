package game

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Vec3 :: rl.Vector3
Vec4 :: [4]f32
Quat :: rl.Quaternion

rng_state: u32 = 0x2545F491

rand_u32 :: proc() -> u32 {
	x := rng_state
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	rng_state = x
	return x
}

randf :: proc() -> f32 {
	return f32(rand_u32() >> 8) / 16777216.0
}

rand_range :: proc(lo, hi: f32) -> f32 {
	return lo + (hi - lo) * randf()
}

// Random int in [lo, hi).
rand_int :: proc(lo, hi: int) -> int {
	if hi <= lo {
		return lo
	}
	return lo + int(rand_u32() % u32(hi - lo))
}

rand_sign :: proc() -> f32 {
	if rand_u32() & 1 == 0 {
		return -1
	}
	return 1
}

rand_unit :: proc() -> Vec3 {
	z := rand_range(-1, 1)
	a := rand_range(0, math.TAU)
	r := math.sqrt(max(1 - z * z, 0))
	return {r * math.cos(a), r * math.sin(a), z}
}

rand_quat :: proc() -> Quat {
	return linalg.quaternion_angle_axis_f32(rand_range(0, math.TAU), rand_unit())
}

norm :: proc(v: Vec3) -> Vec3 {
	l := linalg.length(v)
	if l < 1e-6 {
		return {0, 0, 1}
	}
	return v / l
}

dot :: proc(a, b: Vec3) -> f32 {
	return linalg.dot(a, b)
}

cross :: proc(a, b: Vec3) -> Vec3 {
	return linalg.cross(a, b)
}

length :: proc(v: Vec3) -> f32 {
	return linalg.length(v)
}

// Frame-rate independent exponential approach.
damp :: proc(a, b, rate, dt: f32) -> f32 {
	return b + (a - b) * math.exp(-rate * dt)
}

damp3 :: proc(a, b: Vec3, rate, dt: f32) -> Vec3 {
	k := math.exp(-rate * dt)
	return b + (a - b) * k
}

lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

lerp3 :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return a + (b - a) * t
}

lerp4 :: proc(a, b: Vec4, t: f32) -> Vec4 {
	return a + (b - a) * t
}

clamp01 :: proc(x: f32) -> f32 {
	return clamp(x, 0, 1)
}

smooth :: proc(e0, e1, x: f32) -> f32 {
	t := clamp01((x - e0) / (e1 - e0))
	return t * t * (3 - 2 * t)
}

ease_out :: proc(t: f32) -> f32 {
	u := 1 - clamp01(t)
	return 1 - u * u * u
}

to_color :: proc(c: Vec4) -> rl.Color {
	return {u8(clamp01(c.r) * 255), u8(clamp01(c.g) * 255), u8(clamp01(c.b) * 255), u8(clamp01(c.a) * 255)}
}

rgba :: proc(c: Vec3, a: f32) -> rl.Color {
	return to_color({c.x, c.y, c.z, a})
}

fade :: proc(c: rl.Color, a: f32) -> rl.Color {
	return {c.r, c.g, c.b, u8(clamp01(a) * f32(c.a))}
}

rotate :: proc(q: Quat, v: Vec3) -> Vec3 {
	return linalg.quaternion128_mul_vector3(q, v)
}

quat_mul :: proc(a, b: Quat) -> Quat {
	return a * b
}

quat_axis :: proc(axis: Vec3, angle: f32) -> Quat {
	return linalg.quaternion_angle_axis_f32(angle, axis)
}

// Column basis x/y/z + translation, the layout raylib expects for DrawMesh transforms.
transform :: proc(pos, x, y, z: Vec3) -> rl.Matrix {
	return rl.Matrix {
		x.x, y.x, z.x, pos.x,
		x.y, y.y, z.y, pos.y,
		x.z, y.z, z.z, pos.z,
		0, 0, 0, 1,
	}
}

transform_q :: proc(pos: Vec3, q: Quat, s: f32) -> rl.Matrix {
	return transform(pos, rotate(q, {s, 0, 0}), rotate(q, {0, s, 0}), rotate(q, {0, 0, s}))
}

// Right-handed basis whose +Z looks along fwd.
look_basis :: proc(fwd, up_hint: Vec3) -> (x, y, z: Vec3) {
	z = norm(fwd)
	hint := up_hint
	if abs(dot(z, norm(hint))) > 0.995 {
		hint = {1, 0, 0}
	}
	x = norm(cross(hint, z))
	y = cross(z, x)
	return
}

// Returns a vector perpendicular to v.
perp :: proc(v: Vec3) -> Vec3 {
	if abs(v.y) < 0.9 {
		return norm(cross(v, {0, 1, 0}))
	}
	return norm(cross(v, {1, 0, 0}))
}

// Segment p0->p1 against sphere; returns hit and parametric t in [0,1].
segment_sphere :: proc(p0, p1, c: Vec3, r: f32) -> (bool, f32) {
	d := p1 - p0
	m := p0 - c
	a := dot(d, d)
	b := dot(m, d)
	cc := dot(m, m) - r * r
	if cc <= 0 {
		return true, 0
	}
	if a < 1e-9 {
		return false, 0
	}
	disc := b * b - a * cc
	if disc < 0 {
		return false, 0
	}
	t := (-b - math.sqrt(disc)) / a
	if t < 0 || t > 1 {
		return false, 0
	}
	return true, t
}

// Ray (unit dir) against sphere; returns distance.
ray_sphere :: proc(o, d, c: Vec3, r: f32) -> (bool, f32) {
	m := o - c
	b := dot(m, d)
	cc := dot(m, m) - r * r
	if cc > 0 && b > 0 {
		return false, 0
	}
	disc := b * b - cc
	if disc < 0 {
		return false, 0
	}
	t := -b - math.sqrt(disc)
	if t < 0 {
		t = 0
	}
	return true, t
}

hsv :: proc(h, s, v: f32) -> Vec3 {
	c := rl.ColorFromHSV(h, s, v)
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
}
