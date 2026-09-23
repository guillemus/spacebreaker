package game

import "core:math"
import "core:math/noise"
import rl "vendor:raylib"

RGBA8 :: [4]u8

Mesh_Builder :: struct {
	pos: [dynamic]Vec3,
	nrm: [dynamic]Vec3,
	col: [dynamic]RGBA8,
}

mb_destroy :: proc(b: ^Mesh_Builder) {
	delete(b.pos)
	delete(b.nrm)
	delete(b.col)
}

// Flat-shaded triangle. Alpha < 255 marks the face as emissive in the lit shader.
mb_tri :: proc(b: ^Mesh_Builder, p0, p1, p2: Vec3, c: RGBA8) {
	n := cross(p1 - p0, p2 - p0)
	l := length(n)
	if l < 1e-9 {
		return
	}
	n /= l
	append(&b.pos, p0, p1, p2)
	append(&b.nrm, n, n, n)
	append(&b.col, c, c, c)
}

// Triangle wound so its normal points away from `inside`.
mb_tri_out :: proc(b: ^Mesh_Builder, p0, p1, p2: Vec3, c: RGBA8, inside: Vec3) {
	n := cross(p1 - p0, p2 - p0)
	if dot(n, (p0 + p1 + p2) / 3 - inside) < 0 {
		mb_tri(b, p0, p2, p1, c)
	} else {
		mb_tri(b, p0, p1, p2, c)
	}
}

mb_quad_out :: proc(b: ^Mesh_Builder, p0, p1, p2, p3: Vec3, c: RGBA8, inside: Vec3) {
	mb_tri_out(b, p0, p1, p2, c, inside)
	mb_tri_out(b, p0, p2, p3, c, inside)
}

bit_sign :: proc(i, bit: int) -> f32 {
	if i & bit != 0 {
		return 1
	}
	return -1
}

// Oriented box: center plus half-extent axes.
mb_box :: proc(b: ^Mesh_Builder, center, ax, ay, az: Vec3, c: RGBA8) {
	corners: [8]Vec3
	for i in 0 ..< 8 {
		corners[i] = center + ax * bit_sign(i, 1) + ay * bit_sign(i, 2) + az * bit_sign(i, 4)
	}
	faces := [6][4]int {
		{0, 1, 3, 2},
		{4, 5, 7, 6},
		{0, 1, 5, 4},
		{2, 3, 7, 6},
		{0, 2, 6, 4},
		{1, 3, 7, 5},
	}
	for f in faces {
		mb_quad_out(b, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], c, center)
	}
}

// N-sided prism along +Z from z0 to z1.
mb_prism :: proc(
	b: ^Mesh_Builder,
	sides: int,
	radius, z0, z1: f32,
	offset: Vec3,
	c_side, c_cap: RGBA8,
) {
	center := offset + Vec3{0, 0, (z0 + z1) * 0.5}
	for i in 0 ..< sides {
		a0 := f32(i) / f32(sides) * math.TAU
		a1 := f32(i + 1) / f32(sides) * math.TAU
		p0 := offset + Vec3{math.cos(a0) * radius, math.sin(a0) * radius, z0}
		p1 := offset + Vec3{math.cos(a1) * radius, math.sin(a1) * radius, z0}
		p2 := offset + Vec3{math.cos(a1) * radius, math.sin(a1) * radius, z1}
		p3 := offset + Vec3{math.cos(a0) * radius, math.sin(a0) * radius, z1}
		mb_quad_out(b, p0, p1, p2, p3, c_side, center)
		mb_tri_out(b, offset + Vec3{0, 0, z0}, p0, p1, c_cap, center)
		mb_tri_out(b, offset + Vec3{0, 0, z1}, p3, p2, c_cap, center)
	}
}

mb_upload :: proc(b: ^Mesh_Builder) -> rl.Mesh {
	n := len(b.pos)
	mesh: rl.Mesh
	mesh.vertexCount = i32(n)
	mesh.triangleCount = i32(n / 3)
	mesh.vertices = cast([^]f32)rl.MemAlloc(u32(n * 3 * size_of(f32)))
	mesh.normals = cast([^]f32)rl.MemAlloc(u32(n * 3 * size_of(f32)))
	mesh.texcoords = cast([^]f32)rl.MemAlloc(u32(n * 2 * size_of(f32)))
	mesh.colors = cast([^]u8)rl.MemAlloc(u32(n * 4))
	for i in 0 ..< n {
		p := b.pos[i]
		nn := b.nrm[i]
		c := b.col[i]
		mesh.vertices[i * 3 + 0] = p.x
		mesh.vertices[i * 3 + 1] = p.y
		mesh.vertices[i * 3 + 2] = p.z
		mesh.normals[i * 3 + 0] = nn.x
		mesh.normals[i * 3 + 1] = nn.y
		mesh.normals[i * 3 + 2] = nn.z
		mesh.colors[i * 4 + 0] = c[0]
		mesh.colors[i * 4 + 1] = c[1]
		mesh.colors[i * 4 + 2] = c[2]
		mesh.colors[i * 4 + 3] = c[3]
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

// ---- icosphere ------------------------------------------------------------------------------

ico_subdivide :: proc(out: ^[dynamic][3]Vec3, a, b, c: Vec3, level: int) {
	if level == 0 {
		append(out, [3]Vec3{a, b, c})
		return
	}
	ab := norm((a + b) * 0.5)
	bc := norm((b + c) * 0.5)
	ca := norm((c + a) * 0.5)
	ico_subdivide(out, a, ab, ca, level - 1)
	ico_subdivide(out, b, bc, ab, level - 1)
	ico_subdivide(out, c, ca, bc, level - 1)
	ico_subdivide(out, ab, bc, ca, level - 1)
}

ico_sphere :: proc(level: int) -> [dynamic][3]Vec3 {
	t := (1 + math.sqrt(f32(5))) / 2
	v := [12]Vec3 {
		{-1, t, 0},
		{1, t, 0},
		{-1, -t, 0},
		{1, -t, 0},
		{0, -1, t},
		{0, 1, t},
		{0, -1, -t},
		{0, 1, -t},
		{t, 0, -1},
		{t, 0, 1},
		{-t, 0, -1},
		{-t, 0, 1},
	}
	f := [20][3]int {
		{0, 11, 5},
		{0, 5, 1},
		{0, 1, 7},
		{0, 7, 10},
		{0, 10, 11},
		{1, 5, 9},
		{5, 11, 4},
		{11, 10, 2},
		{10, 7, 6},
		{7, 1, 8},
		{3, 9, 4},
		{3, 4, 2},
		{3, 2, 6},
		{3, 6, 8},
		{3, 8, 9},
		{4, 9, 5},
		{2, 4, 11},
		{6, 2, 10},
		{8, 6, 7},
		{9, 8, 1},
	}
	tris: [dynamic][3]Vec3
	for face in f {
		ico_subdivide(&tris, norm(v[face[0]]), norm(v[face[1]]), norm(v[face[2]]), level)
	}
	return tris
}

// ---- asteroids ------------------------------------------------------------------------------

Crater :: struct {
	dir:   Vec3,
	size:  f32,
	depth: f32,
}

noise3 :: proc(seed: i64, p: Vec3, freq: f32) -> f32 {
	return noise.noise_3d_improve_xy(seed, {f64(p.x * freq), f64(p.y * freq), f64(p.z * freq)})
}

rock_height :: proc(seed: i64, d: Vec3, craters: []Crater, rough: f32) -> f32 {
	h :=
		1 +
		0.24 * noise3(seed, d, 1.1) +
		0.10 * noise3(seed + 1, d, 2.7) * rough +
		0.04 * noise3(seed + 2, d, 6.0) * rough
	for c in craters {
		a := math.acos(clamp(dot(d, c.dir), -1, 1)) / c.size
		if a < 1 {
			h -= c.depth * (1 - a * a)
		} else if a < 1.35 {
			k := (a - 1) / 0.35
			h += c.depth * 0.35 * math.sin(k * math.PI)
		}
	}
	return h
}

make_rock :: proc(seed: i64, level: int, molten: bool, rough: f32) -> rl.Mesh {
	tris := ico_sphere(level)
	defer delete(tris)
	b: Mesh_Builder
	defer mb_destroy(&b)

	craters: [5]Crater
	for &c in craters {
		c = {rand_unit(), rand_range(0.25, 0.55), rand_range(0.05, 0.12)}
	}
	stretch := Vec3{rand_range(0.8, 1.2), rand_range(0.72, 1.05), rand_range(0.85, 1.3)}
	base := Vec3{0.56, 0.51, 0.47}
	switch seed % 3 {
	case 1:
		base = {0.47, 0.48, 0.54}
	case 2:
		base = {0.60, 0.49, 0.40}
	}
	if molten {
		base = {0.22, 0.19, 0.19}
	}

	for tri in tris {
		p: [3]Vec3
		h: [3]f32
		for k in 0 ..< 3 {
			h[k] = rock_height(seed, tri[k], craters[:], rough)
			p[k] = tri[k] * h[k] * stretch
		}
		centroid := norm(tri[0] + tri[1] + tri[2])
		avg := (h[0] + h[1] + h[2]) / 3
		shade := 0.7 + 0.3 * noise3(seed + 7, centroid, 2.5)
		shade *= 0.85 + 0.25 * clamp01((avg - 0.85) * 2.5)
		c := base * shade
		col := RGBA8{u8(clamp01(c.x) * 255), u8(clamp01(c.y) * 255), u8(clamp01(c.z) * 255), 255}
		if molten {
			vein := noise3(seed + 11, centroid, 3.3)
			if avg < 0.97 || abs(vein) < 0.12 {
				heat := clamp01(1.15 - avg) + 0.3
				col = {
					255,
					u8(clamp01(0.30 + heat * 0.35) * 255),
					u8(clamp01(0.05 + heat * 0.1) * 255),
					20,
				}
			}
		} else if noise3(seed + 19, centroid, 4.0) > 0.62 {
			// rare mineral glints
			col = {140, 200, 225, 236}
		}
		mb_tri_out(&b, p[0], p[1], p[2], col, {0, 0, 0})
	}
	return mb_upload(&b)
}

// ---- enemies --------------------------------------------------------------------------------

make_drone :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	dark := RGBA8{40, 36, 52, 255}
	plate := RGBA8{120, 40, 110, 255}
	blade := RGBA8{210, 60, 190, 255}
	glow := RGBA8{255, 70, 220, 0}

	nose := Vec3{0, 0, 1.7}
	tail := Vec3{0, 0, -1.1}
	ring := [4]Vec3{{0.95, 0, 0}, {0, 0.95, 0}, {-0.95, 0, 0}, {0, -0.95, 0}}
	for i in 0 ..< 4 {
		a := ring[i]
		c := ring[(i + 1) % 4]
		col := dark
		if i % 2 == 0 {
			col = plate
		}
		mb_tri(&b, nose, a, c, col)
		mb_tri(&b, tail, c, a, dark)
	}
	for i in 0 ..< 4 {
		ang := f32(i) * math.PI * 0.5 + math.PI * 0.25
		d := Vec3{math.cos(ang), math.sin(ang), 0}
		base0 := d * 0.45 + Vec3{0, 0, 0.5}
		base1 := d * 0.45 + Vec3{0, 0, -0.7}
		tip := d * 2.0 + Vec3{0, 0, -1.0}
		mb_tri(&b, base0, base1, tip, blade)
	}
	// glowing eye
	eye_c := Vec3{0, 0, 1.25}
	for i in 0 ..< 6 {
		a0 := f32(i) / 6 * math.TAU
		a1 := f32(i + 1) / 6 * math.TAU
		p0 := eye_c + Vec3{math.cos(a0) * 0.32, math.sin(a0) * 0.32, 0.1}
		p1 := eye_c + Vec3{math.cos(a1) * 0.32, math.sin(a1) * 0.32, 0.1}
		mb_tri(&b, eye_c + Vec3{0, 0, 0.3}, p0, p1, glow)
	}
	// engine
	mb_prism(&b, 6, 0.35, -1.35, -1.05, {}, dark, glow)
	return mb_upload(&b)
}

make_fighter :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	hull := RGBA8{58, 62, 76, 255}
	hull_dark := RGBA8{34, 36, 46, 255}
	accent := RGBA8{215, 40, 52, 255}
	canopy := RGBA8{90, 230, 255, 60}
	engine := RGBA8{255, 130, 40, 0}

	N := Vec3{0, 0.05, 2.9}
	C := Vec3{0, 0.55, 0.4}
	Lw := Vec3{-2.7, -0.1, -1.3}
	Rw := Vec3{2.7, -0.1, -1.3}
	Lb := Vec3{-0.9, 0.12, -1.5}
	Rb := Vec3{0.9, 0.12, -1.5}
	T := Vec3{0, 0.42, -1.35}
	B := Vec3{0, -0.45, -0.5}
	Bl := Vec3{-0.72, -0.25, -1.5}
	Br := Vec3{0.72, -0.25, -1.5}

	// top
	mb_tri(&b, C, N, Lw, hull)
	mb_tri(&b, C, Rw, N, hull)
	mb_tri(&b, C, Lw, Lb, hull_dark)
	mb_tri(&b, C, Rb, Rw, hull_dark)
	mb_tri(&b, C, Lb, T, hull)
	mb_tri(&b, C, T, Rb, hull)
	// bottom
	mb_tri(&b, B, Lw, N, hull_dark)
	mb_tri(&b, B, N, Rw, hull_dark)
	mb_tri(&b, B, Bl, Lw, hull_dark)
	mb_tri(&b, B, Rw, Br, hull_dark)
	mb_tri(&b, B, Br, Bl, hull_dark)
	// rear
	mb_tri(&b, Lw, Bl, Lb, hull_dark)
	mb_tri(&b, Rw, Rb, Br, hull_dark)
	mb_tri(&b, Lb, Bl, Br, engine)
	mb_tri(&b, Lb, Br, Rb, engine)
	mb_tri(&b, Lb, Rb, T, hull_dark)
	// wing tip accents
	mb_tri(&b, Lw, Lw + Vec3{0.9, 0.03, 0.9}, Lw + Vec3{0.6, 0.06, -0.05}, accent)
	mb_tri(&b, Rw, Rw + Vec3{-0.6, 0.06, -0.05}, Rw + Vec3{-0.9, 0.03, 0.9}, accent)
	// fin
	mb_tri(&b, T, Vec3{0, 1.35, -2.0}, Vec3{0, 0.5, -0.2}, accent)
	// canopy
	mb_tri(
		&b,
		C + Vec3{0, 0.04, 0},
		C + Vec3{-0.28, -0.12, 0.8},
		C + Vec3{0.28, -0.12, 0.8},
		canopy,
	)
	// cannons
	mb_box(&b, {-1.25, -0.12, 0.5}, {0.09, 0, 0}, {0, 0.09, 0}, {0, 0, 0.9}, hull_dark)
	mb_box(&b, {1.25, -0.12, 0.5}, {0.09, 0, 0}, {0, 0.09, 0}, {0, 0, 0.9}, hull_dark)
	return mb_upload(&b)
}

make_boss_hull :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	metal := RGBA8{64, 60, 74, 255}
	dark := RGBA8{30, 28, 38, 255}
	red := RGBA8{150, 30, 45, 255}
	lamp := RGBA8{255, 60, 70, 0}

	SEG :: 14
	r_in := f32(4.2)
	r_out := f32(9.5)
	th := f32(1.3)
	for i in 0 ..< SEG {
		a0 := f32(i) / SEG * math.TAU
		a1 := f32(i + 1) / SEG * math.TAU
		d0 := Vec3{math.cos(a0), math.sin(a0), 0}
		d1 := Vec3{math.cos(a1), math.sin(a1), 0}
		outer := r_out
		if i % 2 == 0 {
			outer = r_out + 0.8
		}
		fz := Vec3{0, 0, th}
		bz := Vec3{0, 0, -th * 0.8}
		i0 := d0 * r_in
		i1 := d1 * r_in
		o0 := d0 * outer
		o1 := d1 * outer
		inside := (d0 + d1) * 0.5 * ((r_in + outer) * 0.5)
		col := metal
		if i % 2 == 0 {
			col = red
		}
		mb_quad_out(&b, i0 + fz * 0.6, o0 + fz, o1 + fz, i1 + fz * 0.6, col, inside)
		mb_quad_out(&b, i0 + bz, o0 + bz, o1 + bz, i1 + bz, dark, inside)
		mb_quad_out(&b, o0 + fz, o0 + bz, o1 + bz, o1 + fz, metal, inside)
		mb_quad_out(&b, i0 + fz * 0.6, i0 + bz, i1 + bz, i1 + fz * 0.6, dark, inside)
		// running lamps on the rim
		mid := (d0 + d1) * 0.5
		lp := mid * (outer + 0.02)
		lx := norm(cross(mid, {0, 0, 1})) * 0.35
		mb_tri(&b, lp + lx + fz * 0.2, lp - lx + fz * 0.2, lp + fz * 0.7, lamp)
	}
	// forward prongs
	for s in 0 ..< 3 {
		ang := f32(s) / 3 * math.TAU + math.PI * 0.5
		d := Vec3{math.cos(ang), math.sin(ang), 0}
		c := d * 7.5 + Vec3{0, 0, 2.6}
		side := norm(cross(d, {0, 0, 1}))
		mb_box(&b, c, side * 0.55, d * 0.55, {0, 0, 2.4}, metal)
		mb_box(&b, c + Vec3{0, 0, 2.5}, side * 0.3, d * 0.3, {0, 0, 0.35}, lamp)
	}
	// rear engines
	for s in 0 ..< 4 {
		ang := f32(s) / 4 * math.TAU + math.PI * 0.25
		d := Vec3{math.cos(ang), math.sin(ang), 0}
		mb_prism(&b, 8, 1.0, -3.6, -1.0, d * 6.2, dark, RGBA8{255, 120, 60, 0})
	}
	return mb_upload(&b)
}

make_boss_core :: proc() -> rl.Mesh {
	tris := ico_sphere(2)
	defer delete(tris)
	b: Mesh_Builder
	defer mb_destroy(&b)
	for tri in tris {
		p: [3]Vec3
		for k in 0 ..< 3 {
			n := noise3(77, tri[k], 2.2)
			p[k] = tri[k] * (1 + 0.18 * n)
		}
		centroid := norm(tri[0] + tri[1] + tri[2])
		v := noise3(91, centroid, 3.0)
		col := RGBA8{255, 50, 70, 0}
		if v > 0.1 {
			col = RGBA8{60, 20, 30, 255}
		}
		mb_tri_out(&b, p[0], p[1], p[2], col, {0, 0, 0})
	}
	return mb_upload(&b)
}

// ---- player view-model cannon ---------------------------------------------------------------

make_gun :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	metal := RGBA8{92, 96, 110, 255}
	dark := RGBA8{36, 38, 48, 255}
	stripe := RGBA8{150, 80, 30, 255}
	glow := RGBA8{120, 235, 255, 0}

	// shroud
	mb_box(&b, {0, -0.01, 0.3}, {0.1, 0, 0}, {0, 0.09, 0}, {0, 0, 0.34}, dark)
	mb_box(&b, {0, 0.09, 0.28}, {0.035, 0, 0}, {0, 0.018, 0}, {0, 0, 0.26}, stripe)
	for i in 0 ..< 3 {
		z := 0.12 + f32(i) * 0.14
		mb_box(&b, {0, 0, z}, {0.12, 0, 0}, {0, 0.07, 0}, {0, 0, 0.025}, metal)
	}
	// barrel
	mb_prism(&b, 6, 0.06, 0.6, 1.55, {}, metal, dark)
	// muzzle ring
	mb_prism(&b, 6, 0.1, 1.5, 1.6, {}, dark, glow)
	// energy coil
	mb_prism(&b, 6, 0.09, 0.95, 1.05, {}, glow, glow)
	return mb_upload(&b)
}

make_missile :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	body := RGBA8{210, 214, 222, 255}
	band := RGBA8{230, 60, 50, 255}
	dark := RGBA8{50, 52, 60, 255}
	mb_prism(&b, 6, 0.14, -0.7, 0.5, {}, body, dark)
	mb_prism(&b, 6, 0.15, 0.15, 0.3, {}, band, band)
	// nose cone
	for i in 0 ..< 6 {
		a0 := f32(i) / 6 * math.TAU
		a1 := f32(i + 1) / 6 * math.TAU
		p0 := Vec3{math.cos(a0) * 0.14, math.sin(a0) * 0.14, 0.5}
		p1 := Vec3{math.cos(a1) * 0.14, math.sin(a1) * 0.14, 0.5}
		mb_tri_out(&b, p0, p1, {0, 0, 0.85}, band, {0, 0, 0.55})
	}
	for i in 0 ..< 4 {
		ang := f32(i) * math.PI * 0.5
		d := Vec3{math.cos(ang), math.sin(ang), 0}
		mb_tri(
			&b,
			d * 0.12 + Vec3{0, 0, -0.2},
			d * 0.12 + Vec3{0, 0, -0.7},
			d * 0.4 + Vec3{0, 0, -0.75},
			dark,
		)
	}
	return mb_upload(&b)
}

make_shard :: proc() -> rl.Mesh {
	b: Mesh_Builder
	defer mb_destroy(&b)
	metal := RGBA8{80, 80, 96, 255}
	edge := RGBA8{255, 140, 60, 40}
	p := [4]Vec3{{0, 0, 1.0}, {0.6, 0, -0.5}, {-0.5, 0.2, -0.4}, {0.05, -0.35, -0.2}}
	c := (p[0] + p[1] + p[2] + p[3]) / 4
	mb_tri_out(&b, p[0], p[1], p[2], metal, c)
	mb_tri_out(&b, p[0], p[2], p[3], metal, c)
	mb_tri_out(&b, p[0], p[3], p[1], edge, c)
	mb_tri_out(&b, p[1], p[3], p[2], metal, c)
	return mb_upload(&b)
}
