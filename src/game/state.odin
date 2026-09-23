package game

import rl "vendor:raylib"

MAX_ENTITIES     :: 256
MAX_BULLETS      :: 256
MAX_MISSILES     :: 24
MAX_PARTICLES    :: 9000
MAX_DEBRIS       :: 320
MAX_LIGHTS       :: 64
SHADER_LIGHTS    :: 8
MAX_FLOATERS     :: 48
MAX_STARS        :: 2400
MAX_DAMAGE_MARKS :: 8
MAX_QUEUE        :: 160
MISSILE_TRAIL    :: 36
N_ROCKS          :: 6
N_MOLTEN         :: 3
N_CHUNKS         :: 4

PLAYER_RADIUS :: f32(3.2)
MAX_AMMO      :: 5
BASE_FOV      :: f32(66)
SPAWN_DIST    :: f32(155)
STAR_DIST     :: f32(1400)
MAX_TURN      :: f32(2.4)
BULLET_SPEED  :: f32(270)
FIRE_INTERVAL :: f32(0.075)
RADAR_RANGE   :: f32(175)

SUN_DIR :: Vec3{0.85, 0.32, 0.42}
PLANET_DIR :: Vec3{-0.5, -0.4, 0.77}

Phase :: enum u8 {
	Title,
	Playing,
	Paused,
	Game_Over,
}

Wave_State :: enum u8 {
	Intro,
	Active,
	Cleared,
}

Entity_Kind :: enum u8 {
	Asteroid,
	Drone,
	Fighter,
	Boss,
	Bolt,
	Nova,
}

Entity :: struct {
	kind:       Entity_Kind,
	id:         u32,
	dead:       bool,
	pos, vel:   Vec3,
	fwd:        Vec3,
	rot:        Quat,
	spin_axis:  Vec3,
	spin:       f32,
	radius:     f32,
	hp, max_hp: f32,
	tier:       int,
	mesh:       int,
	molten:     bool,
	flash:      f32,
	hot:        f32,
	age:        f32,
	timer:      f32,
	charge:     f32,
	state:      int,
	phase:      f32,
	orbit_ang:  f32,
	orbit_rad:  f32,
	orbit_h:    f32,
	orbit_dir:  f32,
	warp:       f32,
	attack:     int,
	fx_acc:     f32,
	ambient:    bool,
}

Bullet :: struct {
	pos, prev, vel: Vec3,
	origin:         Vec3,
	life:           f32,
	side:           int,
}

Missile :: struct {
	pos, vel:  Vec3,
	target:    u32,
	aim:       Vec3,
	age:       f32,
	trail:     [MISSILE_TRAIL]Vec3,
	trail_n:   int,
	trail_acc: f32,
	smoke_acc: f32,
	seed:      f32,
}

Particle_Kind :: enum u8 {
	Glow,
	Spark,
	Smoke,
	Ring,
	Flare,
	Ember,
}

Particle :: struct {
	pos, vel:       Vec3,
	c0, c1:         Vec4,
	s0, s1:         f32,
	life, max_life: f32,
	drag:           f32,
	rot, rot_speed: f32,
	stretch:        f32,
	kind:           Particle_Kind,
}

Debris :: struct {
	pos, vel:       Vec3,
	rot:            Quat,
	spin_axis:      Vec3,
	spin:           f32,
	scale:          f32,
	life, max_life: f32,
	mesh:           int,
	metal:          bool,
	tint:           Vec3,
	hot:            f32,
	smoke_acc:      f32,
}

Light :: struct {
	pos:            Vec3,
	col:            Vec3,
	radius:         f32,
	life, max_life: f32,
}

Frame_Light :: struct {
	pos:    Vec3,
	col:    Vec3,
	radius: f32,
	weight: f32,
}

Floater :: struct {
	pos:            Vec3,
	text:           [32]u8,
	n:              int,
	col:            rl.Color,
	life, max_life: f32,
	size:           f32,
}

Star :: struct {
	dir:   Vec3,
	size:  f32,
	col:   Vec3,
	phase: f32,
	speed: f32,
}

Damage_Mark :: struct {
	dir:  Vec3,
	life: f32,
}

Palette :: struct {
	neb1, neb2, neb3:         Vec3,
	sun:                      Vec3,
	amb_top, amb_bot:         Vec3,
	rim:                      Vec3,
	fog:                      Vec3,
	planet_a, planet_b, atmo: Vec3,
}

Game :: struct {
	phase:          Phase,
	time:           f32,
	real_time:      f32,
	phase_t:        f32,
	time_scale:     f32,
	slowmo:         f32,
	muted:          bool,

	// camera
	yaw, yaw_vel:   f32,
	roll:           f32,
	trauma:         f32,
	fov_kick:       f32,
	cam, rcam:      rl.Camera3D,
	fwd, right, up: Vec3,
	rfwd, rright:   Vec3,
	rup:            Vec3,
	tan_half:       f32,
	aspect:         f32,
	mouse:          Vec2,
	aim_dir:        Vec3,
	aim_point:      Vec3,
	aim_hit:        u32,

	// player
	hull, shield:   f32,
	shield_delay:   f32,
	shield_hit:     f32,
	shield_hit_dir: Vec3,
	heat:           f32,
	overheated:     bool,
	fire_cd:        f32,
	gun_side:       int,
	recoil:         [2]f32,
	muzzle:         [2]f32,
	spread:         f32,
	ammo:           int,
	ammo_charge:    f32,
	ammo_flash:     f32,
	missile_cd:     f32,
	missile_side:   int,
	fire_lock:      bool,
	lock_id:        u32,
	lock_t:         f32,
	lock_beeped:    bool,
	hitmarker:      f32,
	hurt:           f32,
	damage_marks:   [MAX_DAMAGE_MARKS]Damage_Mark,
	dying:          bool,
	dead_t:         f32,

	// scoring
	score:          int,
	shown_score:    f32,
	best:           int,
	new_best:       bool,
	combo:          int,
	combo_t:        f32,
	kills:          int,
	shots, hits:    int,

	// waves
	level:          int,
	start_level:    int,
	wave_state:     Wave_State,
	wave_t:         f32,
	spawn_t:        f32,
	spawn_interval: f32,
	queue:          [MAX_QUEUE]Entity_Kind,
	queue_n:        int,
	queue_i:        int,
	boss_id:        u32,

	// look
	pal:            Palette,
	pal_target:     Palette,
	flash:          Vec4,
	aberr:          f32,
	music_t:        f32,

	// pools
	ents:           [MAX_ENTITIES]Entity,
	ent_n:          int,
	next_id:        u32,
	bullets:        [MAX_BULLETS]Bullet,
	bullet_n:       int,
	missiles:       [MAX_MISSILES]Missile,
	missile_n:      int,
	parts:          [MAX_PARTICLES]Particle,
	part_n:         int,
	debris:         [MAX_DEBRIS]Debris,
	debris_n:       int,
	lights:         [MAX_LIGHTS]Light,
	light_n:        int,
	floaters:       [MAX_FLOATERS]Floater,
	floater_n:      int,
}

g: Game
stars: [MAX_STARS]Star

PALETTES := [?]Palette {
	{ 	// violet rift
		neb1 = {0.46, 0.10, 0.70},
		neb2 = {0.06, 0.52, 0.92},
		neb3 = {0.06, 0.02, 0.14},
		sun = {1.00, 0.86, 0.72},
		amb_top = {0.16, 0.12, 0.30},
		amb_bot = {0.04, 0.03, 0.10},
		rim = {0.30, 0.30, 0.95},
		fog = {0.07, 0.04, 0.14},
		planet_a = {0.88, 0.58, 0.46},
		planet_b = {0.36, 0.18, 0.36},
		atmo = {0.45, 0.65, 1.00},
	},
	{ 	// crimson veil
		neb1 = {0.80, 0.14, 0.12},
		neb2 = {1.00, 0.55, 0.14},
		neb3 = {0.14, 0.02, 0.04},
		sun = {1.00, 0.76, 0.52},
		amb_top = {0.26, 0.10, 0.08},
		amb_bot = {0.07, 0.02, 0.03},
		rim = {1.00, 0.36, 0.20},
		fog = {0.14, 0.04, 0.04},
		planet_a = {0.95, 0.80, 0.55},
		planet_b = {0.55, 0.22, 0.12},
		atmo = {1.00, 0.55, 0.30},
	},
	{ 	// emerald drift
		neb1 = {0.04, 0.58, 0.46},
		neb2 = {0.62, 0.90, 0.22},
		neb3 = {0.01, 0.09, 0.08},
		sun = {0.90, 1.00, 0.82},
		amb_top = {0.08, 0.20, 0.17},
		amb_bot = {0.02, 0.05, 0.05},
		rim = {0.30, 1.00, 0.70},
		fog = {0.03, 0.10, 0.09},
		planet_a = {0.60, 0.85, 0.80},
		planet_b = {0.14, 0.34, 0.40},
		atmo = {0.50, 1.00, 0.80},
	},
	{ 	// deep azure
		neb1 = {0.10, 0.25, 0.90},
		neb2 = {0.75, 0.30, 0.95},
		neb3 = {0.02, 0.04, 0.14},
		sun = {0.85, 0.92, 1.00},
		amb_top = {0.10, 0.14, 0.32},
		amb_bot = {0.02, 0.03, 0.10},
		rim = {0.45, 0.60, 1.00},
		fog = {0.03, 0.05, 0.14},
		planet_a = {0.80, 0.86, 1.00},
		planet_b = {0.20, 0.30, 0.60},
		atmo = {0.60, 0.80, 1.00},
	},
	{ 	// solar storm
		neb1 = {0.95, 0.32, 0.04},
		neb2 = {1.00, 0.85, 0.30},
		neb3 = {0.16, 0.05, 0.01},
		sun = {1.00, 0.70, 0.40},
		amb_top = {0.30, 0.14, 0.05},
		amb_bot = {0.08, 0.03, 0.01},
		rim = {1.00, 0.55, 0.15},
		fog = {0.16, 0.06, 0.02},
		planet_a = {0.30, 0.20, 0.20},
		planet_b = {0.08, 0.05, 0.06},
		atmo = {1.00, 0.45, 0.15},
	},
	{ 	// pink nova
		neb1 = {0.95, 0.20, 0.58},
		neb2 = {0.30, 0.45, 1.00},
		neb3 = {0.12, 0.02, 0.12},
		sun = {1.00, 0.85, 0.95},
		amb_top = {0.26, 0.10, 0.24},
		amb_bot = {0.06, 0.02, 0.08},
		rim = {1.00, 0.40, 0.85},
		fog = {0.13, 0.04, 0.12},
		planet_a = {0.95, 0.75, 0.90},
		planet_b = {0.40, 0.20, 0.55},
		atmo = {1.00, 0.60, 0.95},
	},
}

palette_for_level :: proc(level: int) -> Palette {
	return PALETTES[max(level - 1, 0) % len(PALETTES)]
}

palette_lerp :: proc(a, b: Palette, t: f32) -> Palette {
	r: Palette
	r.neb1 = lerp3(a.neb1, b.neb1, t)
	r.neb2 = lerp3(a.neb2, b.neb2, t)
	r.neb3 = lerp3(a.neb3, b.neb3, t)
	r.sun = lerp3(a.sun, b.sun, t)
	r.amb_top = lerp3(a.amb_top, b.amb_top, t)
	r.amb_bot = lerp3(a.amb_bot, b.amb_bot, t)
	r.rim = lerp3(a.rim, b.rim, t)
	r.fog = lerp3(a.fog, b.fog, t)
	r.planet_a = lerp3(a.planet_a, b.planet_a, t)
	r.planet_b = lerp3(a.planet_b, b.planet_b, t)
	r.atmo = lerp3(a.atmo, b.atmo, t)
	return r
}
