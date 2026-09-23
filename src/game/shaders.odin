package game

// Shaders are written once in GLSL ES 1.00 style; the prelude maps them to GLSL 330 on desktop.
when ODIN_OS == .JS {
	VS_PRE :: "#version 100\n"
	FS_PRE :: "#version 100\n#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n#define TEX texture2D\n#define FRAG_OUT gl_FragColor\n"
} else {
	VS_PRE :: "#version 330\n#define attribute in\n#define varying out\n"
	FS_PRE :: "#version 330\n#define varying in\n#define TEX texture\nout vec4 fragOut;\n#define FRAG_OUT fragOut\n"
}

NOISE_GLSL :: `
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
	               mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
	           mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
	               mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}
`

// ---- lit meshes: asteroids, ships, guns, debris -------------------------------------------

LIT_VS ::
	VS_PRE +
	`
attribute vec3 vertexPosition;
attribute vec3 vertexNormal;
attribute vec4 vertexColor;
uniform mat4 mvp;
uniform mat4 matModel;
varying vec3 vPos;
varying vec3 vNrm;
varying vec4 vCol;
varying vec3 vObj;
void main() {
	vPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
	vNrm = (matModel * vec4(vertexNormal, 0.0)).xyz;
	vCol = vertexColor;
	vObj = vertexPosition;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

LIT_FS ::
	FS_PRE +
	`
varying vec3 vPos;
varying vec3 vNrm;
varying vec4 vCol;
varying vec3 vObj;
uniform vec4 colDiffuse;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
uniform vec3 uAmbTop;
uniform vec3 uAmbBot;
uniform vec3 uRimCol;
uniform vec4 uFlash;
uniform vec3 uEmissive;
uniform vec3 uFogCol;
uniform vec2 uFog;
uniform float uTime;
uniform vec3 uLPos[8];
uniform vec4 uLCol[8];
void main() {
	vec3 N = normalize(vNrm);
	if (!gl_FrontFacing) N = -N;
	vec3 V = normalize(uCamPos - vPos);
	vec3 base = vCol.rgb * colDiffuse.rgb;
	float emis = 1.0 - vCol.a;
	float ndl = dot(N, uSunDir);
	float diff = max(ndl, 0.0);
	vec3 H = normalize(uSunDir + V);
	float spec = pow(max(dot(N, H), 0.0), 28.0) * 0.45 * step(0.0, ndl);
	vec3 amb = mix(uAmbBot, uAmbTop, N.y * 0.5 + 0.5);
	// two-tone fill: nebula-coloured bounce opposite the sun + a soft camera-side key
	vec3 fill = uRimCol * 1.3 * max(-ndl, 0.0) + uAmbTop * 0.9 * max(dot(N, V), 0.0);
	vec3 col = base * (uSunCol * diff * 1.25 + amb * 1.5 + fill) + uSunCol * spec * colDiffuse.a;
	for (int i = 0; i < 8; i++) {
		vec3 L = uLPos[i] - vPos;
		float d = length(L);
		float att = max(1.0 - d / uLCol[i].w, 0.0);
		att *= att;
		float nl = max(dot(N, L / max(d, 0.001)), 0.0) * 0.85 + 0.15;
		col += (base + 0.12) * uLCol[i].rgb * att * nl;
	}
	float fres = 1.0 - max(dot(N, V), 0.0);
	float rim = fres * fres * fres;
	col += uRimCol * rim * 0.9;
	float pulse = 0.85 + 0.15 * sin(uTime * 7.0 + vObj.x * 3.0 + vObj.y * 2.0);
	col = mix(col, vCol.rgb * (1.7 * pulse) + 0.08, emis);
	col += uEmissive * (0.35 + 0.9 * fres);
	col = mix(col, uFlash.rgb, uFlash.a);
	float fog = smoothstep(uFog.x, uFog.y, length(uCamPos - vPos));
	col = mix(col, uFogCol, fog * 0.92);
	FRAG_OUT = vec4(col, 1.0);
}
`

// ---- deflector bubble around the player ----------------------------------------------------

SHIELD_FS ::
	FS_PRE +
	`
varying vec3 vPos;
varying vec3 vNrm;
varying vec4 vCol;
varying vec3 vObj;
uniform vec3 uCamPos;
uniform vec3 uHitDir;
uniform float uHit;
uniform float uIdle;
uniform float uTime;
uniform vec3 uShieldCol;
float hexDist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.73))), p.x);
}
void main() {
	vec3 dir = normalize(vPos - uCamPos);
	float lon = atan(dir.z, dir.x);
	float lat = asin(clamp(dir.y, -1.0, 1.0));
	vec2 uv = vec2(lon, lat) * 5.5;
	vec2 r = vec2(1.0, 1.73);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	float edge = smoothstep(0.07, 0.0, 0.5 - hexDist(gv));
	float d = acos(clamp(dot(dir, uHitDir), -1.0, 1.0));
	float waveFront = (1.0 - uHit) * 2.6;
	float ring = exp(-pow((d - waveFront) * 5.0, 2.0)) * uHit;
	float local = exp(-d * 2.2) * uHit;
	float shimmer = 0.5 + 0.5 * sin(uTime * 3.0 + lat * 9.0 + lon * 4.0);
	float intensity = edge * (ring * 2.4 + local * 1.4 + uIdle * shimmer * 0.25) + local * 0.35 + ring * 0.4;
	FRAG_OUT = vec4(uShieldCol * intensity, 1.0);
}
`

// ---- gas giant ------------------------------------------------------------------------------

PLANET_FS ::
	FS_PRE +
	`
varying vec3 vPos;
varying vec3 vNrm;
varying vec4 vCol;
varying vec3 vObj;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uColA;
uniform vec3 uColB;
uniform vec3 uAtmo;
uniform float uTime;
` +
	NOISE_GLSL +
	`
void main() {
	vec3 N = normalize(vNrm);
	vec3 V = normalize(uCamPos - vPos);
	vec3 o = normalize(vObj);
	float warp = fbm(o * 3.0 + vec3(uTime * 0.004, 0.0, 0.0));
	float band = sin(o.y * 16.0 + warp * 5.0) * 0.5 + 0.5;
	float band2 = sin(o.y * 43.0 + warp * 9.0) * 0.5 + 0.5;
	vec3 base = mix(uColB, uColA, band * 0.65 + band2 * 0.35);
	base *= 0.75 + 0.5 * fbm(o * 9.0 + warp);
	float storm = smoothstep(0.08, 0.0, length(o - normalize(vec3(0.5, -0.25, 0.8))) - 0.12);
	base = mix(base, uColA * 1.3, storm * 0.6);
	float ndl = dot(N, uSunDir);
	float lit = smoothstep(-0.25, 0.55, ndl);
	vec3 col = base * (lit * 0.78 + 0.012);
	float fres = 1.0 - max(dot(N, V), 0.0);
	col += uAtmo * pow(fres, 2.2) * smoothstep(-0.45, 0.35, ndl) * 0.85;
	FRAG_OUT = vec4(col, 1.0);
}
`

// ---- background nebula, rendered at half resolution ----------------------------------------

NEBULA_FS ::
	FS_PRE +
	`
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform vec3 uRight;
uniform vec3 uUp;
uniform vec3 uFwd;
uniform vec2 uTan;
uniform float uTime;
uniform vec3 uCol1;
uniform vec3 uCol2;
uniform vec3 uCol3;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
` +
	NOISE_GLSL +
	`
void main() {
	vec2 ndc = vec2(fragTexCoord.x * 2.0 - 1.0, 1.0 - fragTexCoord.y * 2.0);
	vec3 dir = normalize(uFwd + uRight * ndc.x * uTan.x + uUp * ndc.y * uTan.y);
	vec3 p = dir * 2.3;
	float n1 = fbm(p + vec3(0.0, uTime * 0.006, 0.0));
	float n2 = fbm(p * 1.8 + vec3(n1 * 2.2) + vec3(5.2, 1.3, 2.8));
	float dust = fbm(p * 3.4 + vec3(n2 * 1.5));
	float bandY = dir.y * 2.4 + (n1 - 0.5) * 1.6;
	float band = exp(-bandY * bandY);
	float neb = smoothstep(0.32, 0.86, n2) * (0.3 + 0.7 * band);
	vec3 col = uCol3 * (0.35 + 0.65 * band);
	col += mix(uCol1, uCol2, smoothstep(0.3, 0.75, n1)) * neb * 0.8;
	col += uCol2 * pow(smoothstep(0.5, 0.95, n2 * (0.4 + 0.6 * band)), 2.0) * 0.75;
	col *= 1.0 - smoothstep(0.45, 0.78, dust) * 0.75 * band;
	float sd = max(dot(dir, uSunDir), 0.0);
	col += uSunCol * (pow(sd, 22.0) * 0.35 + pow(sd, 4.0) * 0.07);
	FRAG_OUT = vec4(col, 1.0);
}
`

// ---- bloom chain ----------------------------------------------------------------------------

BRIGHT_FS ::
	FS_PRE +
	`
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 uTexel;
uniform float uThreshold;
void main() {
	vec2 o = uTexel * 0.5;
	vec3 c = TEX(texture0, fragTexCoord + vec2(-o.x, -o.y)).rgb;
	c += TEX(texture0, fragTexCoord + vec2(o.x, -o.y)).rgb;
	c += TEX(texture0, fragTexCoord + vec2(-o.x, o.y)).rgb;
	c += TEX(texture0, fragTexCoord + vec2(o.x, o.y)).rgb;
	c *= 0.25;
	float l = max(c.r, max(c.g, c.b));
	float k = smoothstep(uThreshold, uThreshold + 0.4, l);
	FRAG_OUT = vec4(c * k, 1.0);
}
`

DOWN_FS ::
	FS_PRE +
	`
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 uTexel;
void main() {
	vec2 uv = fragTexCoord;
	vec2 o = uTexel;
	vec3 s = TEX(texture0, uv).rgb * 4.0;
	s += TEX(texture0, uv - o).rgb;
	s += TEX(texture0, uv + o).rgb;
	s += TEX(texture0, uv + vec2(o.x, -o.y)).rgb;
	s += TEX(texture0, uv - vec2(o.x, -o.y)).rgb;
	FRAG_OUT = vec4(s * 0.125, 1.0);
}
`

UP_FS ::
	FS_PRE +
	`
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 uTexel;
uniform float uGain;
void main() {
	vec2 uv = fragTexCoord;
	vec2 o = uTexel;
	vec3 s = TEX(texture0, uv + vec2(-o.x * 2.0, 0.0)).rgb;
	s += TEX(texture0, uv + vec2(-o.x, o.y)).rgb * 2.0;
	s += TEX(texture0, uv + vec2(0.0, o.y * 2.0)).rgb;
	s += TEX(texture0, uv + vec2(o.x, o.y)).rgb * 2.0;
	s += TEX(texture0, uv + vec2(o.x * 2.0, 0.0)).rgb;
	s += TEX(texture0, uv + vec2(o.x, -o.y)).rgb * 2.0;
	s += TEX(texture0, uv + vec2(0.0, -o.y * 2.0)).rgb;
	s += TEX(texture0, uv + vec2(-o.x, -o.y)).rgb * 2.0;
	FRAG_OUT = vec4(s * (uGain / 12.0), 1.0);
}
`

// ---- final composite: bloom, chromatic aberration, vignette, grain, flashes ----------------

COMPOSITE_FS ::
	FS_PRE +
	`
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform sampler2D uBloom;
uniform float uTime;
uniform float uBloomStr;
uniform float uAberr;
uniform float uDamage;
uniform vec4 uFlash;
uniform vec2 uRes;
uniform float uGrain;
uniform float uDesat;
void main() {
	vec2 uv = fragTexCoord;
	vec2 cd = uv - 0.5;
	float r2 = dot(cd, cd);
	vec2 off = cd * uAberr * (0.35 + r2 * 2.5);
	vec3 col;
	col.r = TEX(texture0, uv + off).r;
	col.g = TEX(texture0, uv).g;
	col.b = TEX(texture0, uv - off).b;
	vec3 bloom;
	bloom.r = TEX(uBloom, uv + off * 1.5).r;
	bloom.g = TEX(uBloom, uv).g;
	bloom.b = TEX(uBloom, uv - off * 1.5).b;
	col += bloom * uBloomStr;
	vec3 over = max(col - 1.0, 0.0);
	col += dot(over, vec3(0.3333)) * 0.7;
	col = col * (1.0 + col * 0.08) / (1.0 + col * 0.18);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), uDesat);
	float vig = smoothstep(0.25, 0.95, sqrt(r2) * 1.35);
	col *= 1.0 - vig * 0.55;
	col = mix(col, vec3(0.75, 0.02, 0.05), vig * uDamage);
	col *= 0.965 + 0.035 * sin(uv.y * uRes.y * 2.094);
	float grain = fract(sin(dot(uv * uRes + fract(uTime * 7.13) * 91.7, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) * uGrain;
	col = mix(col, uFlash.rgb, uFlash.a);
	FRAG_OUT = vec4(col, 1.0);
}
`
