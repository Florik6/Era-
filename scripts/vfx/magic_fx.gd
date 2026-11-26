class_name MagicFX
## Per-school spell visuals: palettes, small shaders, procedural textures and
## the phase builders charge → release → projectile/trail → impact → linger.
## Everything is assembled from the pooled primitives of VFXManager, so counts
## follow Settings (particles / fx / lights / decals). Gameplay never reads
## anything from here — removing every visual leaves the rules unchanged.

const PAL := {
	"fire": [Color(1.0, 0.92, 0.6), Color(1.0, 0.48, 0.12), Color(0.55, 0.1, 0.02), Color(1.0, 0.72, 0.3)],
	"ice": [Color(0.92, 0.98, 1.0), Color(0.55, 0.88, 1.0), Color(0.2, 0.45, 0.9), Color(0.8, 0.95, 1.0)],
	"lightning": [Color(0.96, 0.97, 1.0), Color(0.6, 0.7, 1.0), Color(0.38, 0.32, 0.95), Color(0.85, 0.9, 1.0)],
	"dark": [Color(0.9, 0.62, 1.0), Color(0.6, 0.18, 0.9), Color(0.16, 0.02, 0.24), Color(0.8, 0.35, 1.0)],
	"time": [Color(0.86, 1.0, 0.97), Color(0.35, 1.0, 0.85), Color(0.1, 0.42, 0.62), Color(0.7, 1.0, 0.95)],
	"energy": [Color(0.86, 0.97, 1.0), Color(0.3, 0.85, 1.0), Color(0.1, 0.3, 0.75), Color(0.6, 0.95, 1.0)],
	"earth": [Color(0.85, 0.78, 0.65), Color(0.6, 0.5, 0.38), Color(0.3, 0.25, 0.2), Color(1.0, 0.85, 0.6)],
	"phys": [Color(1.0, 0.97, 0.9), Color(1.0, 0.85, 0.6), Color(0.5, 0.45, 0.4), Color(1.0, 0.9, 0.7)],
}
## Rune-circle styles of the "rune" shader.
const RUNE := {"sigil": 0, "clock": 1, "summon": 2, "fire": 3, "frost": 4, "stars": 5, "rift": 6, "storm": 7}

static var _shaders := {}
static var _smats := {}
static var _pm := {}
static var _meshes := {}
static var _tex := {}
static var _ramps := {}
static var _curves := {}

# ======================================================================= shaders
const SH_TELEGRAPH := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float progress = 0.0;
uniform int shape = 0;
uniform float half_arc = 3.14159;
uniform float aspect = 1.0;
uniform float done = 0.0;
void fragment() {
	vec2 p = UV;
	float inside; float edge; float fill; float front; float coord;
	if (shape == 2) {
		float ax = abs(p.x);
		inside = step(ax, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
		edge = max(smoothstep(0.8, 1.0, ax), max(1.0 - smoothstep(0.0, 0.05 / aspect, p.y), smoothstep(1.0 - 0.05 / aspect, 1.0, p.y)));
		coord = p.y;
	} else {
		float d = length(p);
		inside = step(d, 1.0);
		edge = smoothstep(0.9, 1.0, d);
		if (shape == 1) {
			float ang = abs(atan(p.x, -p.y));
			inside *= step(ang, half_arc);
			float side = (half_arc - ang) * max(d, 0.05);
			edge = max(edge, 1.0 - smoothstep(0.0, 0.07, side));
		}
		coord = d;
	}
	fill = step(coord, progress);
	front = (1.0 - smoothstep(0.0, 0.05, abs(coord - progress))) * step(0.02, progress);
	float stripes = step(0.5, fract((p.x + p.y) * 4.0 - TIME * 1.2));
	float pulse = 0.7 + 0.3 * sin(TIME * 12.0 + progress * 6.0);
	float a = inside * (0.14 + fill * (0.26 + 0.08 * stripes) + edge * 0.62 * pulse + front * 0.55 + done * 0.5);
	ALBEDO = mix(col.rgb, vec3(1.0, 0.96, 0.85), clamp(front * 0.6 + edge * 0.2 + done * 0.6, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.92) * col.a;
}
"""

const SH_FRESNEL := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.9, 1.0, 0.5);
uniform float power = 2.0;
uniform float glint = 0.0;
uniform float bands = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float g = 0.0;
	if (glint > 0.0) {
		vec3 c = floor(wp * 14.0);
		float h = fract(sin(dot(c, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		g = step(1.0 - glint * 0.06, h) * (0.6 + 0.4 * sin(TIME * 6.0 + h * 40.0));
	}
	float b = 0.0;
	if (bands > 0.0) { b = smoothstep(0.8, 1.0, sin(wp.y * bands - TIME * 3.0)); }
	ALBEDO = mix(col.rgb, vec3(1.0), clamp(f * 0.6 + g, 0.0, 1.0));
	ALPHA = clamp(col.a * (0.35 + f) + g + b * 0.3 * col.a, 0.0, 1.0);
}
"""

const SH_RUNE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.7, 0.3, 1.0, 1.0);
uniform int style = 0;
uniform float spin = 0.6;
uniform float intensity = 1.0;
float ring(float d, float r, float w) { return 1.0 - smoothstep(0.0, w, abs(d - r)); }
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a; vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(0.0, w, length(pa - ba * h));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	if (d > 1.0) { discard; }
	float t = TIME * spin;
	float a = atan(p.y, p.x);
	float v = 0.0;
	if (style == 0) {
		v += ring(d, 0.93, 0.035) + ring(d, 0.74, 0.025);
		float s = fract((a + t) * 16.0 / (2.0 * PI));
		v += step(0.77, d) * step(d, 0.9) * step(0.2, s) * step(s, 0.5) * 0.8;
		for (int i = 0; i < 5; i++) {
			float g0 = -t * 0.7 + float(i) * 2.0 * PI / 5.0;
			float g1 = g0 + 4.0 * PI / 5.0;
			v += seg(p, vec2(cos(g0), sin(g0)) * 0.72, vec2(cos(g1), sin(g1)) * 0.72, 0.03) * 0.8;
		}
	} else if (style == 1) {
		v += ring(d, 0.93, 0.035) + ring(d, 0.6, 0.02) * 0.6 + ring(d, 0.08, 0.05);
		float tk = fract(a * 12.0 / (2.0 * PI) + 0.5);
		v += step(0.76, d) * step(d, 0.89) * (1.0 - smoothstep(0.0, 0.09, abs(tk - 0.5)));
		vec2 h1 = vec2(cos(t * 2.2), sin(t * 2.2));
		vec2 h2 = vec2(cos(-t * 0.35), sin(-t * 0.35));
		v += seg(p, vec2(0.0), h1 * 0.78, 0.03) + seg(p, vec2(0.0), h2 * 0.5, 0.05);
	} else if (style == 2) {
		v += ring(d, 0.94, 0.03) + ring(d, 0.82, 0.02) + ring(d, 0.45, 0.02) * 0.7;
		for (int i = 0; i < 6; i++) {
			float g0 = t + float(i) * PI / 3.0;
			float g1 = g0 + 2.0 * PI / 3.0;
			v += seg(p, vec2(cos(g0), sin(g0)) * 0.82, vec2(cos(g1), sin(g1)) * 0.82, 0.025) * 0.7;
		}
		float s = fract((a - t * 0.5) * 24.0 / (2.0 * PI));
		v += step(0.84, d) * step(d, 0.92) * step(0.4, s) * step(s, 0.6);
	} else if (style == 3) {
		float fl = 0.75 + 0.18 * sin(a * 9.0 + t * 3.0) + 0.06 * sin(a * 23.0 - t * 5.0);
		v += (1.0 - smoothstep(0.0, 0.12, abs(d - fl))) * 0.8 + ring(d, 0.95, 0.04);
		v += (1.0 - smoothstep(0.2, fl, d)) * 0.35;
	} else if (style == 4) {
		float arms = pow(abs(cos(a * 3.0 + t * 0.3)), 40.0);
		float twig = pow(abs(cos(a * 9.0 + t * 0.3)), 30.0) * step(0.45, d) * step(d, 0.75);
		v += arms * (1.0 - d) * 1.4 + twig * 0.6 + ring(d, 0.93, 0.03) + ring(d, 0.3, 0.02) * 0.6;
	} else if (style == 5) {
		for (int i = 0; i < 5; i++) {
			float g = t * 3.0 + float(i) * 2.0 * PI / 5.0;
			vec2 c = vec2(cos(g), sin(g)) * 0.68;
			v += (1.0 - smoothstep(0.0, 0.2, length(p - c))) * 1.2;
		}
		v += ring(d, 0.68, 0.03) * 0.3;
	} else if (style == 6) {
		float sp = fract((a + d * 5.0 - t * 2.0) * 3.0 / (2.0 * PI));
		v += (1.0 - smoothstep(0.0, 0.18, abs(sp - 0.5))) * smoothstep(0.1, 0.4, d) * (1.0 - smoothstep(0.8, 1.0, d));
		v += ring(d, 0.95, 0.04) + (1.0 - smoothstep(0.0, 0.25, d)) * 0.8;
	} else {
		v += ring(d, 0.93, 0.03);
		for (int i = 0; i < 3; i++) {
			float g = t + float(i) * 2.0 * PI / 3.0;
			vec2 dir = vec2(cos(g), sin(g));
			vec2 nrm = vec2(-dir.y, dir.x);
			vec2 a0 = dir * 0.15; vec2 a1 = dir * 0.45 + nrm * 0.12; vec2 a2 = dir * 0.62 - nrm * 0.1; vec2 a3 = dir * 0.92;
			v += seg(p, a0, a1, 0.025) + seg(p, a1, a2, 0.025) + seg(p, a2, a3, 0.025);
		}
	}
	ALBEDO = col.rgb;
	ALPHA = clamp(v, 0.0, 1.0) * col.a * intensity;
}
"""

const SH_ORB := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 c_core : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform vec4 c_edge : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float wobble = 0.12;
uniform float speed = 4.0;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}
void vertex() {
	float n = noise(VERTEX * 3.5 + vec3(0.0, -TIME * speed, TIME * speed * 0.3));
	VERTEX += NORMAL * (n - 0.5) * wobble * 2.0;
}
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	ALBEDO = mix(c_core.rgb, c_edge.rgb, f);
	ALPHA = clamp(1.0 - f * 0.6, 0.0, 1.0) * c_core.a;
}
"""

const SH_BEAM := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float flow = 0.0;
uniform float grain = 0.0;
void fragment() {
	float e = 1.0 - abs(UV.y * 2.0 - 1.0);
	float a = pow(clamp(e, 0.0, 1.0), 1.6);
	if (grain > 0.0) {
		float n = fract(sin(floor(UV.x * 6.0 - TIME * flow) * 12.9898) * 43758.5453);
		a *= mix(1.0, 0.45 + n, grain);
	}
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
"""

const SH_COLUMN := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 0.6);
uniform float bands = 6.0;
void fragment() {
	float side = pow(abs(dot(NORMAL, VIEW)), 1.4);
	float up = UV.y;
	float a = pow(up, 1.8) * side;
	a *= 0.75 + 0.25 * sin(UV.y * bands * 6.2831 + TIME * 4.0);
	ALBEDO = mix(col.rgb, vec3(1.0), 0.25 * up);
	ALPHA = clamp(a * col.a, 0.0, 1.0);
}
"""

const SH_DISTORT := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.3, 0.25);
uniform float strength = 0.025;
uniform int billboard = 1;
void vertex() {
	if (billboard == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	if (d > 1.0) { discard; }
	float rg = smoothstep(0.5, 0.78, d) * (1.0 - smoothstep(0.78, 1.0, d));
	vec2 off = normalize(p + vec2(0.0001)) * rg * strength * (0.7 + 0.3 * sin(TIME * 3.0));
	vec3 c = textureLod(scr, SCREEN_UV - off, 0.0).rgb;
	ALBEDO = mix(c, tint.rgb, rg * tint.a);
	ALPHA = clamp(rg * 1.6, 0.0, 1.0);
}
"""

static func shader(nm: String) -> Shader:
	if _shaders.has(nm):
		return _shaders[nm]
	var s := Shader.new()
	match nm:
		"telegraph": s.code = SH_TELEGRAPH
		"fresnel": s.code = SH_FRESNEL
		"rune": s.code = SH_RUNE
		"orb": s.code = SH_ORB
		"beam": s.code = SH_BEAM
		"column": s.code = SH_COLUMN
		"distort": s.code = SH_DISTORT
	_shaders[nm] = s
	return s

## Shader material; cached when `key` is non-empty (shared by all users).
static func smat(nm: String, params: Dictionary, key: String = "") -> ShaderMaterial:
	if key != "" and _smats.has(key):
		return _smats[key]
	var m := ShaderMaterial.new()
	m.shader = shader(nm)
	for k in params:
		m.set_shader_parameter(k, params[k])
	if key != "":
		_smats[key] = m
	return m

static func rune_mat(style: String, c: Color, spin: float = 0.6, intensity: float = 1.0) -> ShaderMaterial:
	var key := "rune|%s|%s|%.2f|%.2f" % [style, c.to_html(true), spin, intensity]
	var fresh := not _smats.has(key)
	var m := smat("rune", {"col": c, "style": int(RUNE.get(style, 0)), "spin": spin, "intensity": intensity}, key)
	if fresh:
		m.render_priority = -1
	return m

static func orb_mat(sch: String) -> ShaderMaterial:
	var core: Color = pal(sch, 0)
	var edge: Color = pal(sch, 1)
	var wob := 0.12
	var spd := 4.0
	match sch:
		"dark":
			core = Color(0.45, 0.08, 0.6)
			edge = Color(0.9, 0.5, 1.0)
			wob = 0.2
			spd = 2.0
		"lightning", "energy":
			wob = 0.22
			spd = 9.0
		"time":
			wob = 0.06
			spd = 1.5
	return smat("orb", {"c_core": core, "c_edge": edge, "wobble": wob, "speed": spd}, "orb|" + sch)

static func overlay_mat(kind: String) -> Material:
	var m: ShaderMaterial = null
	match kind:
		"freeze": m = smat("fresnel", {"col": Color(0.62, 0.9, 1.0, 0.55), "power": 1.5, "glint": 1.0}, "ov|freeze")
		"stasis": m = smat("fresnel", {"col": Color(0.4, 1.0, 0.85, 0.4), "power": 2.0, "bands": 7.0}, "ov|stasis")
		"curse": m = smat("fresnel", {"col": Color(0.55, 0.15, 0.85, 0.22), "power": 2.5}, "ov|curse")
		"timeslow": m = smat("fresnel", {"col": Color(0.4, 1.0, 0.85, 0.16), "power": 3.0, "bands": 4.0}, "ov|timeslow")
	if m:
		m.set_meta("fx_overlay", true)
	return m

static func ice_mat() -> StandardMaterial3D:
	if _pm.has("_ice"):
		return _pm["_ice"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.92, 1.0, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.roughness = 0.08
	m.emission_enabled = true
	m.emission = Color(0.35, 0.7, 1.0)
	m.emission_energy_multiplier = 0.9
	m.rim_enabled = true
	m.rim = 0.8
	_pm["_ice"] = m
	return m

## Additive camera-facing glow sprite material for one colour.
static func glow_mat(c: Color) -> StandardMaterial3D:
	var key := "_glow" + c.to_html(true)
	if _pm.has(key):
		return _pm[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = tex("soft")
	m.albedo_color = c
	m.no_depth_test = false
	m.disable_fog = true
	_pm[key] = m
	return m

# ===================================================== particle materials / meshes
static func pmat(kind: String) -> Material:
	if _pm.has(kind):
		return _pm[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	match kind:
		"add", "star", "flame", "ringv":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.billboard_keep_scale = true
			m.albedo_texture = tex({"add": "soft", "star": "star", "flame": "flame", "ringv": "ring"}[kind])
		"mix":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			m.disable_fog = false
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.billboard_keep_scale = true
			m.albedo_texture = tex("smoke")
			m.roughness = 1.0
		"streak":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"shard":
			m.emission_enabled = true
			m.emission = Color(0.25, 0.5, 0.8)
		"chunk":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.disable_fog = false
			m.roughness = 1.0
		"ringflat":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_texture = tex("ring")
	_pm[kind] = m
	return m

static func pmesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"streak":
			var b := BoxMesh.new()
			b.size = Vector3(0.07, 1.0, 0.07)
			mesh = b
		"shard":
			var pr := PrismMesh.new()
			pr.size = Vector3(0.45, 1.0, 0.25)
			mesh = pr
		"chunk":
			var c := BoxMesh.new()
			c.size = Vector3(1, 0.7, 0.9)
			mesh = c
		"ringflat", "plane":
			var pl := PlaneMesh.new()
			pl.size = Vector2(1, 1)
			mesh = pl
		"hemi":
			var h := SphereMesh.new()
			h.radius = 1.0
			h.height = 1.0
			h.is_hemisphere = true
			h.radial_segments = 24
			h.rings = 8
			mesh = h
		"column":
			var cy := CylinderMesh.new()
			cy.top_radius = 1.0
			cy.bottom_radius = 1.0
			cy.height = 1.0
			cy.radial_segments = 12
			cy.rings = 1
			cy.cap_top = false
			cy.cap_bottom = false
			mesh = cy
		_:
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			mesh = q
	_meshes[kind] = mesh
	return mesh

static func ramp(nm: String) -> Gradient:
	if _ramps.has(nm):
		return _ramps[nm]
	var g := Gradient.new()
	var offs: Array = [0.0, 1.0]
	var cols: Array = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
	match nm:
		"late":
			offs = [0.0, 0.55, 1.0]
			cols = [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
		"pop":
			offs = [0.0, 0.12, 1.0]
			cols = [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
		"smoke":
			offs = [0.0, 0.15, 1.0]
			cols = [Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)]
		"fire":
			offs = [0.0, 0.15, 0.45, 0.78, 1.0]
			cols = [Color(1, 1, 0.85, 1), Color(1, 0.78, 0.32, 1), Color(1, 0.4, 0.08, 0.9), Color(0.5, 0.09, 0.03, 0.5), Color(0.1, 0.05, 0.04, 0)]
		"ice":
			offs = [0.0, 1.0]
			cols = [Color(1, 1, 1, 1), Color(0.5, 0.85, 1, 0)]
		"dark":
			offs = [0.0, 0.4, 1.0]
			cols = [Color(1, 0.8, 1, 1), Color(0.6, 0.2, 0.9, 0.8), Color(0.15, 0.0, 0.25, 0)]
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	_ramps[nm] = g
	return g

static func curve(nm: String) -> Curve:
	if _curves.has(nm):
		return _curves[nm]
	var c := Curve.new()
	match nm:
		"grow":
			c.add_point(Vector2(0, 0.15))
			c.add_point(Vector2(0.35, 0.8))
			c.add_point(Vector2(1, 1))
		"puff":
			c.add_point(Vector2(0, 0.35))
			c.add_point(Vector2(0.4, 0.85))
			c.add_point(Vector2(1, 1))
		"flash":
			c.add_point(Vector2(0, 0.5))
			c.add_point(Vector2(0.15, 1))
			c.add_point(Vector2(1, 0.1))
		"pop":
			c.add_point(Vector2(0, 1))
			c.add_point(Vector2(0.7, 0.9))
			c.add_point(Vector2(1, 0))
		_:
			c.add_point(Vector2(0, 1))
			c.add_point(Vector2(1, 0))
	_curves[nm] = c
	return c

# ======================================================================= textures
static func tex(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var t: Texture2D = null
	match kind:
		"soft":
			t = _radial([0.0, 0.22, 0.55, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		"ring":
			t = _radial([0.0, 0.62, 0.82, 0.9, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		"trail":
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 1)])
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill_from = Vector2(0, 0)
			gt.fill_to = Vector2(0, 1)
			gt.width = 8
			gt.height = 32
			t = gt
		_:
			t = ImageTexture.create_from_image(_img(kind))
	_tex[kind] = t
	return t

static func _radial(offs: Array, cols: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

static func _dot(img: Image, p: Vector2, r: float, c: Color) -> void:
	var sz := img.get_width()
	var ri := int(ceil(r))
	for y in range(int(p.y) - ri, int(p.y) + ri + 1):
		if y < 0 or y >= sz:
			continue
		for x in range(int(p.x) - ri, int(p.x) + ri + 1):
			if x < 0 or x >= sz:
				continue
			var d := Vector2(x, y).distance_to(p)
			if d > r:
				continue
			var a := c.a * (1.0 - smoothstep(r * 0.5, r, d))
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))

## Procedural textures: particles (smoke, star, flame) and decals (scorch,
## frost, crack, blood, oil, footprint, hole).
static func _img(kind: String) -> Image:
	var sz := 128 if kind in ["crack", "frost"] else 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var nz := FastNoiseLite.new()
	nz.seed = absi(kind.hash()) % 10000
	nz.frequency = 0.09 * 64.0 / sz
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(kind.hash())
	var h := sz * 0.5
	match kind:
		"crack":
			for b in 9:
				var ang := TAU * b / 9.0 + rng.randf_range(-0.3, 0.3)
				var p := Vector2(h, h)
				var steps := rng.randi_range(16, 28)
				for s in steps:
					ang += rng.randf_range(-0.4, 0.4)
					p += Vector2(cos(ang), sin(ang)) * 2.1
					var k := float(s) / steps
					_dot(img, p, 2.0 * (1.0 - k) + 0.7, Color(0.05, 0.04, 0.035, 0.95 - 0.45 * k))
					if rng.randf() < 0.09:
						var p2 := p
						var a2 := ang + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.5, 1.1)
						for s2 in 9:
							a2 += rng.randf_range(-0.3, 0.3)
							p2 += Vector2(cos(a2), sin(a2)) * 2.0
							_dot(img, p2, 0.8, Color(0.06, 0.05, 0.04, 0.6))
			for y in sz:
				for x in sz:
					var d := Vector2(x - h, y - h).length() / h
					var a := (1.0 - smoothstep(0.05, 0.28, d + nz.get_noise_2d(x, y) * 0.08)) * 0.85
					if a > img.get_pixel(x, y).a:
						img.set_pixel(x, y, Color(0.07, 0.06, 0.05, a))
		_:
			for y in sz:
				for x in sz:
					var u := (x - h + 0.5) / h
					var v := (y - h + 0.5) / h
					var d := sqrt(u * u + v * v)
					var n := nz.get_noise_2d(x, y) * 0.5 + 0.5
					var c := Color(1, 1, 1, 0)
					match kind:
						"smoke":
							c.a = clampf((1.0 - smoothstep(0.25, 1.0, d)) * (0.4 + 0.8 * n) - 0.08, 0.0, 1.0)
						"star":
							var core := pow(clampf(1.0 - d, 0.0, 1.0), 3.0) * 0.8
							var cross := clampf(1.0 - absf(u) * 12.0, 0.0, 1.0) * pow(clampf(1.0 - absf(v), 0.0, 1.0), 2.0)
							cross += clampf(1.0 - absf(v) * 12.0, 0.0, 1.0) * pow(clampf(1.0 - absf(u), 0.0, 1.0), 2.0)
							c.a = clampf(core + cross, 0.0, 1.0)
						"flame":
							var t := 1.0 - (v * 0.5 + 0.5)
							var w := 0.85 * pow(sin(PI * clampf(t * 0.98, 0.0, 1.0)), 0.7) * (1.0 - t * 0.5)
							var shape := 1.0 - smoothstep(w * 0.35, w + 0.001, absf(u + (n - 0.5) * 0.3 * t))
							c.a = clampf(shape * (0.7 + 0.45 * n) * smoothstep(0.0, 0.15, t), 0.0, 1.0)
						"scorch":
							var a := (1.0 - smoothstep(0.3, 1.0, d + (n - 0.5) * 0.45)) * 0.9
							c = Color(0.03, 0.025, 0.02, a).lerp(Color(0.2, 0.11, 0.05, a * 0.8), smoothstep(0.3, 0.9, d))
						"frost":
							var ang := atan2(v, u)
							var arms := pow(absf(cos(ang * 3.0)), 22.0) * (1.0 - smoothstep(0.55, 1.0, d))
							var twig := pow(absf(cos(ang * 9.0 + d * 2.0)), 26.0) * smoothstep(0.25, 0.5, d) * (1.0 - smoothstep(0.7, 0.95, d))
							var base := (1.0 - smoothstep(0.35, 1.0, d + (n - 0.5) * 0.5)) * 0.42
							var speck := 0.6 if rng.randf() < 0.012 and d < 0.9 else 0.0
							c = Color(0.85, 0.95, 1.0, clampf(base + arms * 0.85 + twig * 0.5 + speck, 0.0, 0.95))
						"blood":
							c = Color(0.3, 0.02, 0.02, 0.0)
						"oil":
							c = Color(0.04, 0.04, 0.05, (1.0 - smoothstep(0.45, 0.95, d + (n - 0.5) * 0.4)) * 0.85)
						"footprint":
							var e := (u / 0.38) * (u / 0.38) + (v / 0.8) * (v / 0.8)
							c = Color(0.12, 0.1, 0.08, (1.0 - smoothstep(0.7, 1.0, e)) * 0.45)
						"hole":
							c = Color(0.05, 0.05, 0.05, 0.9 * (1.0 - smoothstep(0.14, 0.22, d)) + 0.35 * (1.0 - smoothstep(0.22, 0.55, d + (n - 0.5) * 0.2)))
					img.set_pixel(x, y, c)
			if kind == "blood":
				for i in 6:
					var bp := Vector2(h + rng.randf_range(-0.45, 0.45) * h, h + rng.randf_range(-0.45, 0.45) * h)
					if i == 0:
						bp = Vector2(h, h)
					_dot(img, bp, rng.randf_range(0.12, 0.32) * h if i > 0 else 0.4 * h, Color(0.32, 0.02, 0.02, 0.85))
	return img

# ======================================================================= helpers
static func mgr():
	return VFX._m()

static func school(s: String) -> String:
	match s:
		"fire", "ice", "lightning", "dark", "energy", "earth":
			return s
		"time", "spacetime", "space":
			return "time"
		"frost", "cold":
			return "ice"
		"shadow", "necro", "curse", "poison":
			return "dark"
		"electric", "storm":
			return "lightning"
	return ""

static func pal(sch: String, i: int) -> Color:
	var p: Array = PAL.get(sch, PAL["phys"])
	return p[clampi(i, 0, 3)]

## Guess the school from an effect colour (bosses / items pass colours only).
static func school_from_color(c: Color) -> String:
	var best := "phys"
	var bd := 0.3
	for k in ["fire", "ice", "lightning", "dark", "time", "energy"]:
		var e: Color = Combat.element_color(k)
		var d := absf(e.r - c.r) + absf(e.g - c.g) + absf(e.b - c.b)
		if d < bd:
			bd = d
			best = k
	if best == "phys":
		if c.r > 0.8 and c.g < 0.5 and c.b < 0.35:
			return "fire"
		if absf(c.r - c.g) < 0.3 and c.b < c.r and c.r < 0.92:
			return "earth"
	return best

## School of a projectile from its kind and damage info ("" = mundane).
static func proj_school(kind: String, info: Dictionary) -> String:
	match kind:
		"fireball":
			return "fire"
		"magic":
			var s := school(str(info.get("school", "")))
			if s == "":
				s = school(str(info.get("dtype", "")))
			return s if s != "" else "energy"
		"spark":
			return "lightning"
	return ""

static func ground_y(p: Vector3) -> float:
	if Game.world and is_instance_valid(Game.world) and Game.world.has_method("ground_height"):
		var gh: float = Game.world.ground_height(p)
		if absf(gh - p.y) < 2.5:
			return gh
	return p.y

static func ground_point(p: Vector3) -> Vector3:
	return Vector3(p.x, ground_y(p), p.z)

static func hand_node(a) -> Node3D:
	if a == null or not is_instance_valid(a):
		return null
	var rig = a.get("rig")
	if rig == null or not is_instance_valid(rig):
		return null
	if rig.has_method("weapon_tip"):
		var wt = rig.weapon_tip()
		if is_instance_valid(wt) and wt is Node3D:
			return wt
	var wn = rig.get("weapon_node")
	if is_instance_valid(wn) and wn is Node3D and wn.has_meta("tip") and str(rig.get("weapon_cat")) in ["staff", "wand"]:
		var tp = wn.get_meta("tip")
		if is_instance_valid(tp) and tp is Node3D:
			return tp
	var jd = rig.get("j")
	if jd is Dictionary and jd.has("hand_r"):
		var hn = jd["hand_r"]
		if is_instance_valid(hn) and hn is Node3D:
			return hn
	return null

static func hand_pos(a) -> Vector3:
	var n := hand_node(a)
	if n:
		return n.global_position
	return a.chest() + a.facing * 0.6

## Node that sticks to another node for a while (charge glows, beams).
class Follow extends Node3D:
	var target: Node3D = null
	var life := 1.0
	var offset := Vector3.ZERO
	func _process(dt: float) -> void:
		life -= dt
		if life <= 0.0:
			queue_free()
			return
		if target != null and is_instance_valid(target) and target.is_inside_tree():
			global_position = target.global_position + offset

static func _quad(parent: Node3D, mat: Material, size: float, pos: Vector3 = Vector3.ZERO, flat: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = pmesh("plane" if flat else "quad")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = Vector3.ONE * size
	parent.add_child(mi)
	return mi

## Flat animated rune circle on the ground; returns it (null without VFX).
static func ground_rune(pos: Vector3, style: String, c: Color, r: float, life: float, spin: float = 0.6, intensity: float = 1.0, parent: Node3D = null) -> MeshInstance3D:
	var mg = mgr()
	if mg == null:
		return null
	var host: Node3D = parent if parent != null else mg
	var mi := _quad(host, rune_mat(style, c, spin, intensity), 0.1)
	if parent == null:
		mi.global_position = ground_point(pos) + Vector3(0, 0.07, 0)
	else:
		mi.position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * r * 2.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if life > 0.0:
		tw.tween_interval(maxf(0.0, life - 0.5))
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.28).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	return mi

static func rune_style_for(sch: String) -> String:
	match sch:
		"fire": return "fire"
		"ice": return "frost"
		"lightning": return "storm"
		"dark": return "sigil"
		"time": return "clock"
	return "summon"

# ============================================================ phase 1: charge
## Gathering energy at the caster's hand/staff tip for `dur` seconds.
static func charge(a, sch: String, dur: float, big: bool = false) -> void:
	var mg = mgr()
	if mg == null or a == null or not is_instance_valid(a) or not a.is_inside_tree():
		return
	if Game.player and is_instance_valid(Game.player) and a.global_position.distance_to(Game.player.global_position) > 45.0:
		return
	sch = school(sch)
	if sch == "":
		sch = "energy"
	var c0 := pal(sch, 0)
	var c1 := pal(sch, 1)
	var f := Follow.new()
	f.life = dur + 0.1
	f.target = hand_node(a)
	mg.add_child(f)
	f.global_position = hand_pos(a)
	var e: CPUParticles3D = mg.make_emitter({"n": 16, "life": 0.3, "mat": "add", "col": c1, "size": 0.16, "v0": 0.0, "v1": 0.2, "shape": "sphere", "rad": 0.7, "radial": -10.0, "grav": Vector3.ZERO, "curve": "grow", "ramp": "pop", "local": true, "expl": 0.0})
	if e:
		f.add_child(e)
		e.emitting = true
	var g := MeshInstance3D.new()
	g.mesh = pmesh("quad")
	g.material_override = glow_mat(c0)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(g)
	g.scale = Vector3.ONE * 0.05
	g.create_tween().tween_property(g, "scale", Vector3.ONE * (0.85 if big else 0.6), maxf(0.05, dur)).set_ease(Tween.EASE_OUT)
	var e2: CPUParticles3D = null
	match sch:
		"fire":
			e2 = mg.make_emitter({"n": 10, "life": 0.45, "mat": "add", "ramp": "fire", "size": 0.3, "v0": 0.4, "v1": 1.2, "dir": Vector3.UP, "spread": 25.0, "grav": Vector3(0, 2.5, 0), "curve": "shrink", "local": false, "expl": 0.0, "shape": "sphere", "rad": 0.12})
		"ice":
			e2 = mg.make_emitter({"n": 6, "life": 0.5, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.12, "v0": 0.0, "v1": 0.1, "shape": "sphere", "rad": 0.35, "tan": 9.0, "grav": Vector3.ZERO, "curve": "pop", "local": true, "expl": 0.0, "ang": 200.0})
		"lightning":
			for i in 3:
				mg.get_tree().create_timer(dur * (0.2 + 0.3 * i), false).timeout.connect(func():
					if is_instance_valid(f):
						var o := Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.5), randf_range(-0.6, 0.6))
						mg.bolt(f.global_position, f.global_position + o, c1, 0.07, 0.025, 0))
		"dark":
			e2 = mg.make_emitter({"n": 8, "life": 0.7, "mat": "mix", "col": Color(0.22, 0.04, 0.32, 0.85), "ramp": "smoke", "size": 0.45, "v0": 0.2, "v1": 0.6, "grav": Vector3(0, 0.8, 0), "curve": "puff", "local": false, "expl": 0.0, "shape": "sphere", "rad": 0.25})
		"time":
			e2 = mg.make_emitter({"n": 3, "life": 0.35, "mat": "ringv", "col": c1, "size": 0.9, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "shrink", "ramp": "pop", "local": true, "expl": 0.0, "exact": true})
	if e2:
		f.add_child(e2)
		e2.emitting = true
	if big:
		ground_rune(a.global_position, rune_style_for(sch), c1, 1.4, dur + 0.45, 1.2, 0.9)

# ============================================================ phase 2: release
static func release(pos: Vector3, dir: Vector3, sch: String) -> void:
	var mg = mgr()
	if mg == null:
		return
	sch = school(sch)
	var c0 := pal(sch, 0)
	var c1 := pal(sch, 1)
	mg.glow(pos, c0, 0.9, 0.15)
	match sch:
		"fire":
			mg.emit(pos, {"n": 14, "life": 0.35, "mat": "add", "ramp": "fire", "size": 0.5, "v0": 2.0, "v1": 5.0, "dir": dir, "spread": 35.0, "grav": Vector3(0, 2, 0), "damp": 6.0, "curve": "shrink"})
		"ice":
			mg.emit(pos, {"n": 12, "life": 0.45, "mat": "add", "col": Color(0.9, 0.97, 1.0), "ramp": "ice", "size": 0.35, "v0": 1.5, "v1": 4.0, "dir": dir, "spread": 50.0, "grav": Vector3(0, -1, 0), "damp": 4.0, "curve": "shrink"})
			mg.emit(pos, {"n": 5, "life": 0.4, "mat": "shard", "col": Color(0.8, 0.95, 1.0, 0.9), "size": 0.12, "v0": 3.0, "v1": 6.0, "dir": dir, "spread": 40.0, "grav": Vector3(0, -8, 0), "ang": 300.0})
		"lightning":
			for i in 2:
				mg.bolt(pos, pos + (dir + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.4), randf_range(-0.5, 0.5))).normalized() * 0.9, c1, 0.08, 0.025, 0)
			mg.emit(pos, {"n": 10, "life": 0.18, "mat": "streak", "col": c0, "size": 0.3, "v0": 5.0, "v1": 9.0, "dir": dir, "spread": 60.0, "grav": Vector3.ZERO})
		"dark":
			mg.emit(pos, {"n": 10, "life": 0.7, "mat": "mix", "col": Color(0.2, 0.04, 0.3, 0.85), "ramp": "smoke", "size": 0.6, "v0": 1.0, "v1": 2.5, "dir": dir, "spread": 50.0, "grav": Vector3(0, 0.6, 0), "damp": 3.0, "curve": "puff"})
		"time":
			mg.shock_v(pos, 0.9, c1, 0.3, dir)
	return

# ============================================== phase 3: projectile dressing
## Builds a school-specific body + trails on a projectile. Returns false when
## the projectile should keep its plain mesh.
static func dress_projectile(p: Node3D, sch: String, kind: String, color: Color) -> bool:
	var mg = mgr()
	if mg == null:
		return false
	var fx: int = mg.fx
	var big := kind == "fireball"
	var core := MeshInstance3D.new()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trails: Array = []
	match sch:
		"fire":
			core.mesh = MeshLib.sphere(0.38 if big else 0.26, 12, 8)
			core.material_override = orb_mat("fire")
			trails.append({"n": 26 if big else 16, "life": 0.42, "mat": "add", "ramp": "fire", "size": 0.75 if big else 0.5, "v0": 0.2, "v1": 0.8, "grav": Vector3(0, 1.8, 0), "shape": "sphere", "rad": 0.15, "curve": "shrink"})
			trails.append({"n": 8, "life": 0.5, "mat": "streak", "col": pal("fire", 3), "size": 0.18, "v0": 1.0, "v1": 2.5, "grav": Vector3(0, -3, 0), "curve": "shrink"})
			if fx >= 1:
				trails.append({"n": 8, "life": 0.9, "mat": "mix", "col": Color(0.22, 0.2, 0.18, 0.55), "ramp": "smoke", "size": 0.8, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, 1.2, 0), "curve": "puff"})
			mg.attach_light(p, pal("fire", 1), 1.6, 5.0, Vector3.ZERO)
		"ice":
			core.mesh = MeshLib.prism(Vector3(0.24, 0.8, 0.24))
			core.material_override = ice_mat()
			core.rotation_degrees = Vector3(-90, 0, 0)
			var gl := MeshInstance3D.new()
			gl.mesh = pmesh("quad")
			gl.material_override = glow_mat(pal("ice", 1))
			gl.scale = Vector3.ONE * 0.8
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.add_child(gl)
			trails.append({"n": 18, "life": 0.5, "mat": "add", "col": pal("ice", 1), "ramp": "ice", "size": 0.32, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, -0.5, 0), "curve": "shrink"})
			trails.append({"n": 10, "life": 0.9, "mat": "add", "col": Color(1, 1, 1, 0.9), "size": 0.08, "v0": 0.3, "v1": 1.0, "grav": Vector3(0, -1.5, 0), "shape": "sphere", "rad": 0.2})
			if fx >= 1:
				trails.append({"n": 5, "life": 0.5, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.85), "size": 0.1, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, -6, 0), "ang": 300.0})
		"lightning", "energy":
			core.mesh = MeshLib.sphere(0.2, 10, 6)
			core.material_override = orb_mat(sch)
			trails.append({"n": 14, "life": 0.12, "mat": "streak", "col": pal(sch, 0), "size": 0.32, "v0": 4.0, "v1": 9.0, "spread": 180.0, "grav": Vector3.ZERO})
			trails.append({"n": 14, "life": 0.25, "mat": "add", "col": pal(sch, 1), "size": 0.4, "v0": 0.0, "v1": 0.2, "grav": Vector3.ZERO, "curve": "shrink"})
			if sch == "lightning":
				mg.attach_light(p, pal(sch, 1), 1.2, 4.0, Vector3.ZERO)
		"dark":
			core.mesh = MeshLib.sphere(0.26, 12, 8)
			core.material_override = orb_mat("dark")
			trails.append({"n": 14, "life": 0.7, "mat": "mix", "col": Color(0.24, 0.05, 0.34, 0.8), "ramp": "smoke", "size": 0.55, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, 0.6, 0), "curve": "puff"})
			trails.append({"n": 10, "life": 0.55, "mat": "add", "col": pal("dark", 3), "size": 0.13, "v0": 0.2, "v1": 0.6, "tan": 6.0, "shape": "sphere", "rad": 0.3, "grav": Vector3.ZERO})
		"time":
			core.mesh = MeshLib.sphere(0.22, 12, 8)
			core.material_override = orb_mat("time")
			trails.append({"n": 8, "life": 0.45, "mat": "ringv", "col": pal("time", 1), "size": 0.85, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "shrink", "exact": true})
			trails.append({"n": 8, "life": 0.9, "mat": "star", "col": pal("time", 0), "size": 0.14, "v0": 0.5, "v1": 1.2, "damp": 4.0, "grav": Vector3.ZERO})
		_:
			core.free()
			return false
	p.add_child(core)
	for o in trails:
		var od: Dictionary = o
		od["local"] = false
		od["expl"] = 0.0
		var e: CPUParticles3D = mg.make_emitter(od)
		if e:
			e.set_meta("trail", true)
			p.add_child(e)
			e.emitting = true
	return true

## Lighter dressing for mundane projectiles (elemental arrows, tracers).
static func dress_basic(p: Node3D, kind: String, color: Color, info: Dictionary) -> void:
	var mg = mgr()
	if mg == null:
		return
	var fx: int = mg.fx
	var o: Dictionary = {}
	match kind:
		"arrow", "bolt":
			if not info.get("status", {}).is_empty():
				o = {"n": 12, "life": 0.35, "mat": "add", "col": color, "size": 0.22, "v0": 0.0, "v1": 0.3, "grav": Vector3.ZERO, "curve": "shrink"}
			elif fx >= 2 or info.get("amount", 0.0) > 60.0:
				o = {"n": 8, "life": 0.18, "mat": "add", "col": Color(1, 1, 1, 0.35), "size": 0.12, "v0": 0.0, "v1": 0.05, "grav": Vector3.ZERO, "curve": "shrink"}
		"plasma":
			o = {"n": 16, "life": 0.35, "mat": "add", "ramp": "fire", "size": 0.5, "v0": 0.1, "v1": 0.5, "grav": Vector3.ZERO, "curve": "shrink"}
		"pulse":
			o = {"n": 10, "life": 0.18, "mat": "add", "col": color, "size": 0.25, "v0": 0.0, "v1": 0.2, "grav": Vector3.ZERO, "curve": "shrink"}
	if o.is_empty():
		return
	o["local"] = false
	o["expl"] = 0.0
	var e: CPUParticles3D = mg.make_emitter(o)
	if e:
		e.set_meta("trail", true)
		p.add_child(e)
		e.emitting = true

## Let trail emitters finish in world space after the projectile dies.
static func detach_trails(p: Node3D) -> void:
	var mg = mgr()
	for ch in p.get_children():
		if ch is CPUParticles3D and ch.has_meta("trail"):
			var gt: Transform3D = ch.global_transform
			var life: float = ch.lifetime
			p.remove_child(ch)
			if mg == null:
				ch.free()
				continue
			mg.add_child(ch)
			ch.global_transform = gt
			ch.emitting = false
			mg.reap(ch, life + 0.1)

# =============================================================== phase 4: impact
## School-specific impact; r ~ radius of the effect. Leaves decals (linger).
static func impact(pos: Vector3, sch: String, r: float = 1.0, crit: bool = true) -> void:
	var mg = mgr()
	if mg == null:
		return
	var fx: int = mg.fx
	var c0 := pal(sch, 0)
	var c1 := pal(sch, 1)
	var c3 := pal(sch, 3)
	var k := clampf(r, 0.5, 6.0)
	var gp := ground_point(pos)
	match sch:
		"fire":
			mg.glow(pos, c0, 1.2 + k * 0.9, 0.22)
			mg.emit(pos, {"n": int(16 + k * 7), "life": 0.55, "mat": "add", "ramp": "fire", "size": 0.6 + k * 0.25, "v0": 2.0 + k, "v1": 4.0 + k * 1.8, "grav": Vector3(0, 2.0, 0), "damp": 3.0 + k, "curve": "shrink", "critical": crit})
			mg.emit(pos, {"n": int(8 + k * 5), "life": 0.8, "mat": "streak", "col": c3, "size": 0.3, "v0": 4.0, "v1": 8.0 + k * 2.0, "dir": Vector3.UP, "spread": 70.0, "grav": Vector3(0, -9.0, 0), "curve": "shrink"})
			if fx >= 1:
				mg.emit(pos + Vector3(0, 0.3, 0), {"n": int(5 + k * 3), "life": 1.6, "mat": "mix", "col": Color(0.2, 0.18, 0.16, 0.7), "ramp": "smoke", "size": 1.0 + k * 0.35, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, 1.4, 0), "damp": 1.0, "curve": "puff", "shape": "sphere", "rad": k * 0.3})
			mg.shock(gp, k * 1.1, c1, 0.35)
			mg.light(pos + Vector3(0, 1, 0), c1, 3.0 + k, 4.0 + k * 2.0, 0.3)
			mg.decal(gp, "scorch", 1.0 + k * 1.1, 18.0, randf() * TAU)
		"ice":
			mg.glow(pos, c0, 1.0 + k * 0.6, 0.18)
			mg.emit(pos, {"n": int(10 + k * 5), "life": 0.75, "mat": "shard", "col": Color(0.82, 0.95, 1.0, 0.92), "size": 0.18 + k * 0.04, "v0": 3.0, "v1": 6.0 + k, "dir": Vector3.UP, "spread": 80.0, "grav": Vector3(0, -14, 0), "ang": 400.0, "curve": "pop", "critical": crit})
			mg.emit(pos, {"n": int(6 + k * 4), "life": 0.9, "mat": "mix", "col": Color(0.92, 0.97, 1.0, 0.8), "ramp": "smoke", "size": 0.8 + k * 0.25, "v0": 1.0, "v1": 2.5, "damp": 2.5, "grav": Vector3(0, -0.3, 0), "curve": "puff"})
			if fx >= 1:
				mg.emit(pos, {"n": 6, "life": 0.7, "mat": "star", "col": Color(1, 1, 1), "size": 0.35, "v0": 0.5, "v1": 1.5, "grav": Vector3.ZERO, "ramp": "pop"})
			mg.shock(gp, k, c1, 0.4)
			mg.decal(gp, "frost", 1.2 + k, 14.0, randf() * TAU)
			if k >= 2.5:
				ice_spikes(gp, k, 6)
			if fx >= 1:
				mg.light(pos + Vector3(0, 1, 0), c1, 2.0, 4.0, 0.2)
		"lightning":
			mg.glow(pos, Color(1, 1, 1), 1.4 + k * 0.7, 0.12)
			mg.emit(pos, {"n": int(14 + k * 6), "life": 0.35, "mat": "streak", "col": c0, "size": 0.42, "v0": 6.0, "v1": 12.0, "spread": 180.0, "grav": Vector3(0, -12, 0), "damp": 2.0, "curve": "shrink", "critical": crit})
			for i in (3 if fx >= 1 else 1):
				var an := randf() * TAU
				mg.bolt(gp + Vector3(0, 0.15, 0), gp + Vector3(cos(an), 0.05, sin(an)) * (0.8 + k * 1.1), c1, 0.12, 0.03, 0)
			mg.shock(gp, k * 0.9, c1, 0.25)
			mg.light(pos + Vector3(0, 1, 0), c0, 5.0, 7.0, 0.12)
			mg.decal(gp, "scorch", 0.6 + k * 0.5, 10.0, randf() * TAU)
		"dark":
			mg.emit(pos, {"n": int(14 + k * 6), "life": 0.45, "mat": "add", "col": c3, "size": 0.25, "shape": "sphere", "rad": 0.8 + k * 0.5, "v0": 0.0, "v1": 0.2, "radial": -14.0 - k * 2.0, "grav": Vector3.ZERO, "ramp": "pop", "expl": 1.0, "critical": crit})
			mg.emit(pos, {"n": int(6 + k * 4), "life": 1.1, "mat": "mix", "col": Color(0.18, 0.04, 0.25, 0.85), "ramp": "smoke", "size": 0.9 + k * 0.3, "v0": 1.5, "v1": 3.5, "damp": 3.0, "grav": Vector3(0, 0.5, 0), "curve": "puff"})
			mg.glow(pos, c1, 1.0 + k * 0.6, 0.25)
			mg.shock(gp, k, c1, 0.45)
			if k >= 2.0:
				ground_rune(gp, "sigil", c1, k * 0.8, 0.7, 1.5, 1.0)
		"time":
			mg.emit(gp + Vector3(0, 0.1, 0), {"n": 3, "exact": true, "life": 0.6, "mat": "ringflat", "col": c1, "size": k * 2.6, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "grow", "expl": 0.0, "critical": true})
			mg.emit(pos, {"n": int(10 + k * 4), "life": 1.2, "mat": "star", "col": c0, "size": 0.25, "v0": 2.0, "v1": 5.0, "damp": 8.0, "grav": Vector3.ZERO, "ramp": "late"})
			mg.glow(pos, c0, 1.0 + k * 0.5, 0.2)
			mg.shock_v(pos, k * 1.2, c1, 0.4, Vector3.ZERO)
		"energy":
			mg.glow(pos, c0, 1.0 + k * 0.6, 0.15)
			mg.emit(pos, {"n": int(10 + k * 5), "life": 0.3, "mat": "streak", "col": c1, "size": 0.35, "v0": 5.0, "v1": 10.0, "spread": 180.0, "grav": Vector3.ZERO, "damp": 4.0, "curve": "shrink", "critical": crit})
			mg.shock(gp, k * 0.9, c1, 0.3)
		"earth":
			mg.ground_impact(gp, k)
		_:
			mg.glow(pos, c0, 0.8 + k * 0.4, 0.12)
			mg.emit(pos, {"n": int(8 + k * 3), "life": 0.35, "mat": "streak", "col": c1, "size": 0.3, "v0": 3.0, "v1": 7.0, "spread": 180.0, "grav": Vector3(0, -10, 0), "curve": "shrink", "critical": crit})

## Small per-target magical hit (used by hit_fx for elemental damage).
static func hit(pos: Vector3, dir: Vector3, sch: String, heavy: bool) -> void:
	var mg = mgr()
	if mg == null:
		return
	var c0 := pal(sch, 0)
	var c1 := pal(sch, 1)
	var s := 1.5 if heavy else 1.0
	mg.glow(pos, c0, 0.7 * s, 0.12)
	match sch:
		"fire":
			mg.emit(pos, {"n": int(10 * s), "life": 0.4, "mat": "add", "ramp": "fire", "size": 0.4 * s, "v0": 1.5, "v1": 3.5, "dir": dir, "spread": 60.0, "grav": Vector3(0, 2.5, 0), "damp": 4.0, "curve": "shrink", "critical": true})
		"ice":
			mg.emit(pos, {"n": int(7 * s), "life": 0.5, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.12 * s, "v0": 2.0, "v1": 4.5, "dir": dir, "spread": 70.0, "grav": Vector3(0, -12, 0), "ang": 400.0, "critical": true})
		"lightning":
			mg.emit(pos, {"n": int(10 * s), "life": 0.2, "mat": "streak", "col": c0, "size": 0.35, "v0": 5.0, "v1": 10.0, "spread": 180.0, "grav": Vector3.ZERO, "critical": true})
			mg.bolt(pos, pos + Vector3(randf_range(-0.8, 0.8), randf_range(-0.6, 0.2), randf_range(-0.8, 0.8)), c1, 0.08, 0.025, 0)
		"dark":
			mg.emit(pos, {"n": int(8 * s), "life": 0.5, "mat": "mix", "col": Color(0.25, 0.05, 0.35, 0.85), "ramp": "smoke", "size": 0.45 * s, "v0": 0.8, "v1": 2.0, "dir": dir, "spread": 70.0, "grav": Vector3(0, 0.5, 0), "damp": 3.0, "curve": "puff", "critical": true})
		"time":
			mg.shock_v(pos, 0.8 * s, c1, 0.3, dir)
			mg.emit(pos, {"n": int(6 * s), "life": 0.8, "mat": "star", "col": c0, "size": 0.2, "v0": 1.5, "v1": 3.0, "damp": 7.0, "grav": Vector3.ZERO, "ramp": "late", "critical": true})
		_:
			mg.emit(pos, {"n": int(8 * s), "life": 0.25, "mat": "streak", "col": c1, "size": 0.3, "v0": 4.0, "v1": 8.0, "dir": dir, "spread": 70.0, "grav": Vector3.ZERO, "critical": true})

## Explosion dispatcher for VFX.explosion (school guessed from colour).
static func explode(pos: Vector3, r: float, c: Color) -> void:
	var mg = mgr()
	if mg == null:
		return
	var sch := school_from_color(c)
	if sch == "phys":
		sch = "earth" if (c.r + c.g + c.b) < 2.4 else "energy"
	impact(pos, sch, r)
	if sch == "fire" and mg.fx >= 1:
		var ball := MeshInstance3D.new()
		ball.mesh = MeshLib.sphere(1.0, 14, 10)
		ball.material_override = orb_mat("fire")
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mg.add_child(ball)
		ball.global_position = pos + Vector3(0, 0.4, 0)
		ball.scale = Vector3.ONE * 0.3
		var tw := ball.create_tween()
		tw.tween_property(ball, "scale", Vector3.ONE * r * 0.75, 0.16).set_ease(Tween.EASE_OUT)
		tw.tween_property(ball, "scale", Vector3.ONE * 0.05, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_callback(ball.queue_free)
	if r >= 3.0:
		if sch != "earth":
			mg.ground_impact(ground_point(pos), r * 0.6)
		VFX.shake(minf(0.6, r * 0.08))

## Crystal spikes bursting out of the ground in a ring, then sinking.
static func ice_spikes(gp: Vector3, r: float, n: int) -> void:
	var mg = mgr()
	if mg == null:
		return
	if mg.fx == 0:
		n = mini(n, 3)
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var d := r * randf_range(0.35, 0.85)
		var p := gp + Vector3(cos(a), 0, sin(a)) * d
		p.y = ground_y(p)
		var mi := MeshInstance3D.new()
		var hh := randf_range(0.7, 1.5) * clampf(r * 0.4, 0.6, 1.6)
		mi.mesh = MeshLib.prism(Vector3(0.45, 1.0, 0.45))
		mi.material_override = ice_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mg.add_child(mi)
		mi.global_position = p
		mi.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		mi.scale = Vector3(1, 0.01, 1)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(1, hh, 1), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(0.9 + randf() * 0.3)
		tw.tween_property(mi, "scale", Vector3(0.6, 0.01, 0.6), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)

# ============================================================ school set pieces
## Frost nova: shock ring, spikes, snow, wide frost decal.
static func freeze_nova(pos: Vector3, r: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	var c1 := pal("ice", 1)
	mg.shock(gp, r, c1, 0.4)
	mg.shock(gp, r * 0.6, Color(1, 1, 1), 0.3)
	mg.glow(pos + Vector3(0, 1, 0), pal("ice", 0), 2.5, 0.25)
	mg.emit(gp + Vector3(0, 0.4, 0), {"n": int(r * 8), "life": 0.9, "mat": "mix", "col": Color(0.92, 0.97, 1.0, 0.75), "ramp": "smoke", "size": 1.3, "shape": "ring", "rad": 0.6, "v0": 2.0, "v1": 4.0, "radial": 6.0, "dir": Vector3.UP, "spread": 20.0, "flat": 1.0, "damp": 2.0, "grav": Vector3.ZERO, "curve": "puff", "critical": true})
	mg.emit(gp + Vector3(0, 0.5, 0), {"n": int(r * 4), "life": 0.8, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.18, "v0": 5.0, "v1": 9.0, "dir": Vector3.UP, "spread": 75.0, "grav": Vector3(0, -14, 0), "ang": 400.0})
	ice_spikes(gp, r, 8)
	ground_rune(gp, "frost", c1, r * 0.9, 1.0, 0.4, 0.9)
	mg.decal(gp, "frost", r * 1.8, 16.0, randf() * TAU)
	mg.light(gp + Vector3(0, 1.5, 0), c1, 3.0, r + 3.0, 0.3)

## Decoration around a freshly raised ice wall (frost, mist, shards).
static func ice_wall(pos: Vector3, dir: Vector3, life: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	d = d.normalized()
	var b := Basis.looking_at(d, Vector3.UP)
	mg.emit(gp + Vector3(0, 0.3, 0), {"n": 22, "life": 1.1, "mat": "mix", "col": Color(0.9, 0.97, 1.0, 0.7), "ramp": "smoke", "size": 1.2, "shape": "box", "box": Vector3(3.0, 0.2, 0.5), "basis": b, "v0": 0.8, "v1": 2.0, "dir": Vector3.UP, "spread": 60.0, "damp": 2.0, "grav": Vector3.ZERO, "curve": "puff"})
	mg.emit(gp + Vector3(0, 1.0, 0), {"n": 16, "life": 0.7, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.18, "shape": "box", "box": Vector3(3.0, 0.8, 0.4), "basis": b, "v0": 2.0, "v1": 5.0, "dir": Vector3.UP, "spread": 70.0, "grav": Vector3(0, -12, 0), "ang": 300.0})
	mg.emit(gp + Vector3(0, 1.2, 0), {"n": 8, "life": 1.5, "mat": "star", "col": Color(1, 1, 1), "size": 0.3, "shape": "box", "box": Vector3(3.0, 1.2, 0.5), "basis": b, "v0": 0.0, "v1": 0.1, "grav": Vector3.ZERO, "ramp": "pop", "expl": 0.0})
	mg.decal(gp, "frost", 6.5, life + 4.0, atan2(d.x, d.z))
	mg.glow(gp + Vector3(0, 1.2, 0), pal("ice", 1), 3.0, 0.3)

## Lightning strike from the sky.
static func sky_strike(p: Vector3, c: Color = Color(0.75, 0.8, 1.0), r: float = 2.0) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(p)
	var top := gp + Vector3(randf_range(-2.0, 2.0), 16.0, randf_range(-2.0, 2.0))
	mg.bolt(top, gp, c, 0.22, 0.13, 3 if mg.fx >= 1 else 1)
	impact(gp + Vector3(0, 0.3, 0), "lightning", r * 0.8)

## Radial ground arcs + flash (thunderclap).
static func thunderclap(pos: Vector3, r: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	var c1 := pal("lightning", 1)
	mg.glow(gp + Vector3(0, 1, 0), Color(1, 1, 1), 3.5, 0.15)
	var n := 6 if mg.fx >= 1 else 3
	for i in n:
		var a := TAU * i / n + randf_range(-0.3, 0.3)
		mg.bolt(gp + Vector3(0, 0.3, 0), gp + Vector3(cos(a) * r, 0.2, sin(a) * r), c1, 0.2, 0.05, 1)
	mg.shock(gp, r, c1, 0.3)
	mg.ground_impact(gp, r * 0.5)
	mg.light(gp + Vector3(0, 2, 0), c1, 6.0, r + 5.0, 0.15)

## Chain-lightning arc between two points.
static func chain_arc(a: Vector3, b: Vector3) -> void:
	var mg = mgr()
	if mg == null:
		return
	var c1 := pal("lightning", 1)
	mg.bolt(a, b, c1, 0.22, 0.06, 2 if mg.fx >= 1 else 0)
	mg.glow(b, pal("lightning", 0), 0.9, 0.12)
	mg.emit(b, {"n": 8, "life": 0.25, "mat": "streak", "col": pal("lightning", 0), "size": 0.35, "v0": 5.0, "v1": 9.0, "spread": 180.0, "grav": Vector3(0, -10, 0), "critical": true})
	mg.light(b, c1, 2.5, 4.0, 0.1)

## Life-drain beam from victim to caster with particles flowing back.
static func drain(victim, caster) -> void:
	var mg = mgr()
	if mg == null or not is_instance_valid(victim) or not is_instance_valid(caster):
		return
	var c := Color(0.9, 0.15, 0.4)
	mg.beam_follow(victim, caster, c, 0.6, 0.12)
	var a: Vector3 = victim.chest()
	var b: Vector3 = caster.chest()
	var d := a.distance_to(b)
	var spd := 9.0
	mg.emit(a, {"n": 16, "life": d / spd, "mat": "add", "col": Color(1.0, 0.3, 0.5), "size": 0.2, "dir": (b - a).normalized(), "spread": 5.0, "v0": spd, "v1": spd * 1.05, "grav": Vector3.ZERO, "expl": 0.1, "lrand": 0.0, "ramp": "late"})
	mg.emit(a, {"n": 10, "life": 0.5, "mat": "mix", "col": Color(0.35, 0.03, 0.12, 0.8), "ramp": "smoke", "size": 0.5, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, 0.5, 0), "curve": "puff"})
	mg.glow(b, Color(1.0, 0.35, 0.55), 1.2, 0.35)

## Curse seal stamped on a target (the lingering sigil is a status visual).
static func curse_seal(c_pos: Vector3, t) -> void:
	var mg = mgr()
	if mg == null or not is_instance_valid(t):
		return
	var c1 := pal("dark", 1)
	mg.beam(c_pos, t.chest(), Color(0.55, 0.15, 0.85), 0.25, 0.06, false)
	ground_rune(t.global_position, "sigil", c1, 1.3 * t._scale(), 1.0, 2.0, 1.0)
	mg.emit(t.chest(), {"n": 14, "life": 0.6, "mat": "add", "col": pal("dark", 3), "size": 0.2, "shape": "sphere", "rad": 1.0, "radial": -8.0, "v0": 0.0, "v1": 0.3, "grav": Vector3.ZERO, "ramp": "pop", "critical": true})

## Dark nova around the caster.
static func dark_nova(pos: Vector3, r: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	var c1 := pal("dark", 1)
	mg.shock(gp, r, c1, 0.45)
	mg.shock(gp, r * 0.7, pal("dark", 3), 0.35)
	ground_rune(gp, "sigil", c1, 2.4, 0.9, 2.0, 1.0)
	mg.emit(gp + Vector3(0, 0.6, 0), {"n": int(r * 5), "life": 0.8, "mat": "mix", "col": Color(0.2, 0.04, 0.3, 0.85), "ramp": "smoke", "size": 1.2, "shape": "ring", "rad": 0.8, "v0": 3.0, "v1": 6.0, "radial": 4.0, "dir": Vector3.UP, "spread": 15.0, "flat": 1.0, "damp": 3.0, "grav": Vector3.ZERO, "curve": "puff", "critical": true})
	mg.glow(gp + Vector3(0, 1, 0), c1, 3.0, 0.3)
	mg.distort(gp + Vector3(0, 0.15, 0), r * 2.0, 0.45, Color(0.6, 0.2, 0.9, 0.2), false)

## Summoning circle with a rising pillar of dark motes.
static func summon_circle(pos: Vector3, r: float = 1.8, c: Color = Color(0.6, 0.2, 0.9)) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	ground_rune(gp, "summon", c, r, 1.6, 0.8, 1.0)
	mg.emit(gp + Vector3(0, 0.1, 0), {"n": 24, "life": 1.0, "mat": "add", "col": c, "size": 0.2, "shape": "ring", "rad": r * 0.8, "v0": 2.0, "v1": 4.5, "dir": Vector3.UP, "spread": 5.0, "grav": Vector3.ZERO, "ramp": "late", "expl": 0.3})
	mg.emit(gp + Vector3(0, 0.5, 0), {"n": 10, "life": 1.2, "mat": "mix", "col": Color(0.15, 0.03, 0.2, 0.8), "ramp": "smoke", "size": 1.0, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, 0.8, 0), "curve": "puff"})

## Puff where a summoned creature appears.
static func summon_puff(p: Vector3, c: Color = Color(0.6, 0.3, 0.9)) -> void:
	var mg = mgr()
	if mg == null:
		return
	mg.emit(p, {"n": 12, "life": 0.9, "mat": "mix", "col": Color(0.16, 0.04, 0.22, 0.85), "ramp": "smoke", "size": 0.9, "v0": 1.0, "v1": 2.5, "grav": Vector3(0, 0.6, 0), "damp": 2.0, "curve": "puff", "critical": true})
	mg.emit(p, {"n": 10, "life": 0.5, "mat": "add", "col": c, "size": 0.22, "v0": 1.5, "v1": 3.5, "grav": Vector3(0, 1, 0)})
	mg.shock(ground_point(p), 1.2, c, 0.35)

## Translucent afterimage of an actor's rig (blink, rift dash, shadow step).
static func ghost(a, c: Color, life: float = 0.5, at = null) -> void:
	var mg = mgr()
	if mg == null or a == null or not is_instance_valid(a):
		return
	var rig = a.get("rig")
	if rig == null or not is_instance_valid(rig) or not rig.is_inside_tree():
		return
	var g = rig.duplicate(0)
	if g == null or not (g is Node3D):
		return
	var m := smat("fresnel", {"col": c, "power": 1.2}) as ShaderMaterial
	_strip_ghost(g, m)
	mg.add_child(g)
	var gt: Transform3D = rig.global_transform
	if at is Vector3:
		gt.origin += at - a.global_position
	g.global_transform = gt
	var tw: Tween = g.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("col", Color(c.r, c.g, c.b, v)), c.a, 0.0, life)
	tw.parallel().tween_property(g, "scale", g.scale * 1.06, life)
	tw.tween_callback(g.queue_free)

static func _strip_ghost(n: Node, m: Material) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			ch.material_override = m
			ch.material_overlay = null
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_strip_ghost(ch, m)
		elif ch is Node3D and not (ch is VisualInstance3D):
			_strip_ghost(ch, m)
		else:
			n.remove_child(ch)
			ch.free()

## Blink: vanish implosion + ghost at the origin, rift streak, arrival ripple.
static func blink_out(a, sch: String = "time") -> void:
	var mg = mgr()
	if mg == null or not is_instance_valid(a):
		return
	var c1 := pal(sch, 1)
	ghost(a, Color(c1.r, c1.g, c1.b, 0.55), 0.55)
	mg.emit(a.chest(), {"n": 16, "life": 0.35, "mat": "add", "col": pal(sch, 3), "size": 0.2, "shape": "sphere", "rad": 1.0, "radial": -12.0, "v0": 0.0, "v1": 0.2, "grav": Vector3.ZERO, "ramp": "pop", "expl": 1.0, "critical": true})
	mg.shock_v(a.chest(), 1.4, c1, 0.25, Vector3.ZERO)

static func blink_in(a, from: Vector3, sch: String = "time") -> void:
	var mg = mgr()
	if mg == null or not is_instance_valid(a):
		return
	var c1 := pal(sch, 1)
	var to: Vector3 = a.chest()
	mg.beam(from + Vector3(0, 1.0, 0), to, c1, 0.3, 0.3, false)
	mg.emit(to, {"n": 14, "life": 0.5, "mat": "star", "col": pal(sch, 0), "size": 0.22, "v0": 2.0, "v1": 4.0, "damp": 5.0, "grav": Vector3.ZERO, "critical": true})
	mg.shock(ground_point(a.global_position), 1.6, c1, 0.35)
	mg.glow(to, pal(sch, 0), 1.3, 0.2)

## Rift dash: chain of afterimages along the path + rift rings at both ends.
static func rift_dash(a, start: Vector3, end: Vector3) -> void:
	var mg = mgr()
	if mg == null or not is_instance_valid(a):
		return
	var c1 := pal("time", 1)
	var n := 4 if mg.fx >= 1 else 1
	for i in n:
		var t := float(i + 1) / float(n + 1)
		ghost(a, Color(c1.r, c1.g, c1.b, 0.45 - 0.07 * i), 0.35 + 0.1 * i, start.lerp(end, t))
	mg.beam(start + Vector3(0, 1, 0), end + Vector3(0, 1, 0), c1, 0.35, 0.3, false)
	ground_rune(start, "rift", c1, 1.2, 0.6, 2.5, 1.0)
	ground_rune(end, "rift", c1, 1.2, 0.6, -2.5, 1.0)
	mg.emit((start + end) * 0.5 + Vector3(0, 1, 0), {"n": 18, "life": 0.6, "mat": "star", "col": pal("time", 0), "size": 0.18, "shape": "box", "box": Vector3(0.4, 0.5, start.distance_to(end) * 0.5), "basis": Basis.looking_at((end - start).normalized() if start.distance_to(end) > 0.1 else Vector3.FORWARD, Vector3.UP), "v0": 0.2, "v1": 1.0, "damp": 3.0, "grav": Vector3.ZERO, "ramp": "pop"})

## Time snap when a time trap closes on a victim.
static func time_snap(pos: Vector3, r: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var c1 := pal("time", 1)
	ground_rune(pos, "clock", c1, r, 1.0, 4.0, 1.2)
	mg.shock(ground_point(pos), r, c1, 0.4)
	mg.shock_v(pos + Vector3(0, 1, 0), r * 0.8, c1, 0.35, Vector3.ZERO)
	mg.glow(pos + Vector3(0, 1, 0), pal("time", 0), 2.0, 0.25)

## Falling meteor that lands at `p` after `delay` seconds.
static func meteor(p: Vector3, delay: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(p)
	var start := gp + Vector3(-6.0, 22.0, -4.0)
	var body := Node3D.new()
	mg.add_child(body)
	body.global_position = start
	var core := MeshInstance3D.new()
	core.mesh = MeshLib.sphere(0.9, 14, 10)
	core.material_override = orb_mat("fire")
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(core)
	var rock := MeshInstance3D.new()
	rock.mesh = MeshLib.sphere(0.55, 8, 6)
	rock.material_override = MeshLib.mat(Color(0.18, 0.1, 0.07), 0.0, 1.0, 0.6)
	body.add_child(rock)
	for o in [{"n": 40, "life": 0.7, "mat": "add", "ramp": "fire", "size": 1.4, "v0": 0.5, "v1": 2.0, "grav": Vector3(0, 2, 0), "shape": "sphere", "rad": 0.5, "curve": "shrink"},
			{"n": 18, "life": 1.4, "mat": "mix", "col": Color(0.2, 0.17, 0.15, 0.7), "ramp": "smoke", "size": 1.6, "v0": 0.2, "v1": 0.8, "grav": Vector3(0, 0.5, 0), "curve": "puff"}]:
		var od: Dictionary = o
		od["local"] = false
		od["expl"] = 0.0
		var e: CPUParticles3D = mg.make_emitter(od)
		if e:
			e.set_meta("trail", true)
			body.add_child(e)
			e.emitting = true
	mg.attach_light(body, pal("fire", 1), 3.0, 9.0, Vector3.ZERO)
	var tw := body.create_tween()
	tw.tween_property(body, "global_position", gp, maxf(0.1, delay)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		detach_trails(body)
		body.queue_free()
		mg.decal(gp, "crack", 5.0, 22.0, randf() * TAU))

## Boss phase-transition burst: light pillar, triple shock wave, debris.
static func phase_burst(pos: Vector3, c: Color, scl: float = 1.5) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := ground_point(pos)
	mg.emit(gp + Vector3(0, 0.2, 0), {"n": 40, "life": 0.8, "mat": "add", "col": c, "size": 0.45, "shape": "ring", "rad": 1.2 * scl, "v0": 8.0, "v1": 14.0, "dir": Vector3.UP, "spread": 6.0, "grav": Vector3.ZERO, "ramp": "late", "critical": true})
	mg.emit(gp + Vector3(0, 0.1, 0), {"n": 3, "exact": true, "life": 0.9, "mat": "ringflat", "col": c, "size": 18.0, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "grow", "expl": 0.0, "critical": true})
	mg.glow(gp + Vector3(0, 2, 0), c, 5.0 * scl, 0.4)
	mg.ground_impact(gp, 3.0 * scl)
	mg.distort(gp + Vector3(0, 1.5, 0), 6.0 * scl, 0.6, Color(c.r, c.g, c.b, 0.2), true)
	mg.light(gp + Vector3(0, 3, 0), c, 6.0, 14.0, 0.5)

# ============================================================== phase 5: linger
## Zone visuals by kind; returns false when the zone should use its default.
static func build_zone(z) -> bool:
	var mg = mgr()
	if mg == null:
		return false
	var r: float = z.radius
	var kind: String = z.kind
	var vis: Node3D = z._vis
	var fx: int = mg.fx
	var life: float = z.life
	var c: Color = z.color()
	var ems: Array = []
	match kind:
		"fire":
			ground_rune(Vector3(0, 0.08, 0), "fire", c, r, 0.0, 0.8, 0.55, vis)
			ems.append({"n": int(clampf(r * 14.0, 8, 34)), "life": 0.75, "mat": "flame", "ramp": "fire", "size": 1.0, "svar": 0.5, "v0": 1.0, "v1": 2.4, "dir": Vector3.UP, "spread": 10.0, "grav": Vector3(0, 1.0, 0), "shape": "ring", "rad": r * 0.85, "curve": "pop", "pos": Vector3(0, 0.35, 0)})
			ems.append({"n": 8, "life": 0.9, "mat": "streak", "col": pal("fire", 3), "size": 0.16, "v0": 1.5, "v1": 3.5, "dir": Vector3.UP, "spread": 25.0, "grav": Vector3(0, 0.5, 0), "shape": "ring", "rad": r * 0.8, "curve": "shrink", "pos": Vector3(0, 0.3, 0)})
			if fx >= 1:
				ems.append({"n": 6, "life": 1.8, "mat": "mix", "col": Color(0.2, 0.18, 0.17, 0.5), "ramp": "smoke", "size": 1.4, "v0": 0.6, "v1": 1.2, "dir": Vector3.UP, "spread": 15.0, "grav": Vector3(0, 0.6, 0), "shape": "ring", "rad": r * 0.6, "curve": "puff", "pos": Vector3(0, 1.0, 0)})
			mg.attach_light(vis, c, 1.2, r + 3.0, Vector3(0, 1, 0))
			mg.decal(z.global_position, "scorch", r * 2.3, life + 8.0, randf() * TAU)
		"blizzard":
			ground_rune(Vector3(0, 0.08, 0), "frost", c, r, 0.0, 0.3, 0.5, vis)
			ems.append({"n": int(r * 14.0), "life": 1.0, "mat": "streak", "col": Color(0.95, 0.98, 1.0, 0.85), "size": 0.2, "shape": "box", "box": Vector3(r * 0.9, 0.2, r * 0.9), "v0": 5.0, "v1": 8.0, "dir": Vector3(0.35, -1.0, 0.15), "spread": 8.0, "grav": Vector3(0, -4, 0), "pos": Vector3(0, 5.5, 0)})
			ems.append({"n": int(r * 6.0), "life": 1.6, "mat": "add", "col": Color(1, 1, 1, 0.9), "size": 0.12, "shape": "sphere", "rad": r * 0.8, "v0": 0.5, "v1": 1.5, "tan": 4.0, "grav": Vector3(0, -0.8, 0), "pos": Vector3(0, 1.5, 0)})
			if fx >= 1:
				ems.append({"n": int(r * 3.0), "life": 2.0, "mat": "mix", "col": Color(0.86, 0.93, 1.0, 0.45), "ramp": "smoke", "size": 2.4, "shape": "ring", "rad": r * 0.75, "tan": 3.0, "v0": 0.3, "v1": 0.8, "grav": Vector3.ZERO, "curve": "puff", "pos": Vector3(0, 0.8, 0)})
			mg.decal(z.global_position, "frost", r * 2.3, life + 6.0, randf() * TAU)
		"timeslow":
			ground_rune(Vector3(0, 0.08, 0), "clock", c, r, 0.0, 0.25, 0.8, vis)
			var dome := MeshInstance3D.new()
			dome.mesh = pmesh("hemi")
			dome.material_override = smat("fresnel", {"col": Color(0.4, 1.0, 0.85, 0.1), "power": 2.2, "bands": 3.0}, "dome|time")
			dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vis.add_child(dome)
			dome.scale = Vector3.ONE * 0.1
			dome.create_tween().tween_property(dome, "scale", Vector3(r, r * 0.75, r), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			ems.append({"n": int(r * 5.0), "life": 2.5, "mat": "star", "col": pal("time", 0), "size": 0.18, "shape": "sphere", "rad": r * 0.8, "v0": 0.05, "v1": 0.2, "grav": Vector3.ZERO, "ramp": "pop", "pos": Vector3(0, 1.2, 0)})
		"timetrap":
			ground_rune(Vector3(0, 0.08, 0), "clock", c, r * 1.2, 0.0, 1.5, 1.1, vis)
			ems.append({"n": 6, "life": 1.2, "mat": "add", "col": c, "size": 0.14, "shape": "ring", "rad": r, "v0": 0.4, "v1": 0.9, "dir": Vector3.UP, "spread": 10.0, "grav": Vector3.ZERO, "pos": Vector3(0, 0.1, 0)})
		"rift":
			ground_rune(Vector3(0, 0.08, 0), "rift", Color(0.55, 0.45, 1.0), r * 1.1, 0.0, 2.2, 1.0, vis)
			ems.append({"n": 3, "exact": true, "life": 0.8, "mat": "ringv", "col": c, "size": r * 1.6, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "shrink", "ramp": "pop", "pos": Vector3(0, 1.2, 0)})
			ems.append({"n": int(r * 8.0), "life": 0.6, "mat": "add", "col": Color(0.6, 0.5, 1.0), "size": 0.16, "shape": "sphere", "rad": r, "radial": -9.0, "v0": 0.0, "v1": 0.2, "grav": Vector3.ZERO, "ramp": "pop", "pos": Vector3(0, 0.8, 0)})
			mg.distort(z.global_position + Vector3(0, 1.2, 0), r * 2.0, life, Color(0.5, 0.4, 1.0, 0.2), true)
		"electric":
			ground_rune(Vector3(0, 0.08, 0), "storm", c, r, 0.0, 1.2, 0.9, vis)
			ems.append({"n": 10, "life": 0.15, "mat": "streak", "col": pal("lightning", 0), "size": 0.3, "shape": "ring", "rad": r * 0.8, "v0": 3.0, "v1": 7.0, "spread": 180.0, "grav": Vector3.ZERO, "pos": Vector3(0, 0.3, 0)})
		"dark":
			ground_rune(Vector3(0, 0.08, 0), "sigil", c, r, 0.0, 0.5, 0.8, vis)
			ems.append({"n": int(r * 4.0), "life": 1.6, "mat": "mix", "col": Color(0.18, 0.03, 0.26, 0.75), "ramp": "smoke", "size": 1.4, "shape": "ring", "rad": r * 0.7, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, 0.2, 0), "curve": "puff", "pos": Vector3(0, 0.3, 0)})
			ems.append({"n": 8, "life": 1.0, "mat": "add", "col": pal("dark", 3), "size": 0.14, "shape": "ring", "rad": r * 0.8, "v0": 0.5, "v1": 1.5, "dir": Vector3.UP, "spread": 15.0, "grav": Vector3.ZERO, "pos": Vector3(0, 0.2, 0)})
		"heal":
			ground_rune(Vector3(0, 0.08, 0), "summon", c, r, 0.0, 0.4, 0.8, vis)
			ems.append({"n": int(r * 5.0), "life": 1.4, "mat": "add", "col": c, "size": 0.16, "shape": "ring", "rad": r * 0.8, "v0": 0.6, "v1": 1.4, "dir": Vector3.UP, "spread": 10.0, "grav": Vector3.ZERO, "ramp": "pop", "pos": Vector3(0, 0.1, 0)})
		"mine":
			var disc := MeshInstance3D.new()
			disc.mesh = MeshLib.cyl(1.0, 1.0, 0.03, 20)
			disc.material_override = MeshLib.mat(Color(c.r, c.g, c.b, 0.5), 0.0, 1.0, 1.5, true)
			disc.scale = Vector3(r, 1, r)
			disc.position.y = 0.06
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vis.add_child(disc)
			MeshLib.part(vis, MeshLib.cyl(0.25, 0.3, 0.14, 10), MeshLib.mat(Color(0.18, 0.18, 0.2), 0.7, 0.4), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
			ems.append({"n": 2, "exact": true, "life": 0.9, "mat": "add", "col": Color(1.0, 0.15, 0.1), "size": 0.9, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "ramp": "pop", "pos": Vector3(0, 0.25, 0)})
		_:
			return false
	for o in ems:
		var od: Dictionary = o
		od["local"] = true
		od["expl"] = 0.0
		var e: CPUParticles3D = mg.make_emitter(od)
		if e:
			vis.add_child(e)
			e.position = od.get("pos", Vector3.ZERO)
			e.emitting = true
	vis.set_meta("fx", true)
	return true

## Wind a zone's visuals down during its last half second.
static func zone_fade(z) -> void:
	var vis: Node3D = z._vis
	if vis == null or vis.has_meta("fading"):
		return
	vis.set_meta("fading", true)
	for ch in vis.get_children():
		if ch is CPUParticles3D:
			ch.emitting = false
		elif ch is MeshInstance3D:
			var mi: MeshInstance3D = ch
			mi.create_tween().tween_property(mi, "scale", mi.scale * Vector3(0.02, 0.02, 0.02), 0.45).set_ease(Tween.EASE_IN)

# ================================================================ status visuals
## Per-status attachment on an actor (frozen shell, curse sigil, burning,
## stun stars, magic shield bubble, time stasis clock, slowed-time glyph).
static func status_node(a, kind: String, s: float) -> Node3D:
	var mg = mgr()
	if mg == null:
		return null
	var n := Node3D.new()
	n.name = "fx_" + kind
	a.add_child(n)
	match kind:
		"freeze":
			for i in 6:
				var an := TAU * i / 6.0 + randf_range(-0.2, 0.2)
				var hh := randf_range(0.6, 1.1) * s
				var mi := MeshInstance3D.new()
				mi.mesh = MeshLib.prism(Vector3(0.32 * s, 1.0, 0.32 * s))
				mi.material_override = ice_mat()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				n.add_child(mi)
				mi.position = Vector3(cos(an) * 0.42 * s, hh * 0.45, sin(an) * 0.42 * s)
				mi.rotation = Vector3(sin(an) * 0.35, randf() * TAU, -cos(an) * 0.35)
				mi.scale = Vector3(1, 0.01, 1)
				mi.create_tween().tween_property(mi, "scale", Vector3(1, hh, 1), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			var e: CPUParticles3D = mg.make_emitter({"n": 4, "life": 1.4, "mat": "mix", "col": Color(0.9, 0.97, 1.0, 0.5), "ramp": "smoke", "size": 0.8 * s, "shape": "sphere", "rad": 0.4 * s, "v0": 0.1, "v1": 0.3, "grav": Vector3(0, -0.2, 0), "curve": "puff", "local": true, "expl": 0.0})
			if e:
				n.add_child(e)
				e.position = Vector3(0, 0.4 * s, 0)
				e.emitting = true
			mg.decal(a.global_position, "frost", 1.6 * s, 6.0, randf() * TAU)
		"stasis":
			_quad(n, rune_mat("clock", pal("time", 1), 0.4, 1.0), 1.9 * s, Vector3(0, 1.0 * s, 0))
		"curse":
			_quad(n, rune_mat("sigil", Color(0.75, 0.25, 1.0), 1.2, 1.0), 0.95 * s, Vector3(0, 2.35 * s, 0))
			var e2: CPUParticles3D = mg.make_emitter({"n": 5, "life": 1.2, "mat": "mix", "col": Color(0.25, 0.05, 0.35, 0.7), "ramp": "smoke", "size": 0.45 * s, "shape": "sphere", "rad": 0.3 * s, "v0": 0.2, "v1": 0.5, "grav": Vector3(0, 0.6, 0), "curve": "puff", "local": false, "expl": 0.0})
			if e2:
				n.add_child(e2)
				e2.position = Vector3(0, 1.2 * s, 0)
				e2.emitting = true
		"burn":
			var e3: CPUParticles3D = mg.make_emitter({"n": 10, "life": 0.55, "mat": "flame", "ramp": "fire", "size": 0.6 * s, "svar": 0.5, "shape": "sphere", "rad": 0.28 * s, "v0": 0.6, "v1": 1.4, "dir": Vector3.UP, "spread": 15.0, "grav": Vector3(0, 1.5, 0), "curve": "pop", "local": false, "expl": 0.0})
			if e3:
				n.add_child(e3)
				e3.position = Vector3(0, 0.9 * s, 0)
				e3.emitting = true
			var e4: CPUParticles3D = mg.make_emitter({"n": 4, "life": 0.8, "mat": "streak", "col": pal("fire", 3), "size": 0.14, "shape": "sphere", "rad": 0.3 * s, "v0": 1.0, "v1": 2.0, "dir": Vector3.UP, "spread": 25.0, "grav": Vector3.ZERO, "curve": "shrink", "local": false, "expl": 0.0})
			if e4:
				n.add_child(e4)
				e4.position = Vector3(0, 1.0 * s, 0)
				e4.emitting = true
		"stun":
			_quad(n, rune_mat("stars", Color(1.0, 0.95, 0.5), 1.0, 1.0), 0.85 * s, Vector3(0, 2.2 * s, 0))
		"magic_shield":
			var b := MeshInstance3D.new()
			b.mesh = MeshLib.sphere(1.0, 20, 12)
			b.material_override = smat("fresnel", {"col": Color(0.45, 0.7, 1.0, 0.18), "power": 2.0, "bands": 5.0}, "bubble")
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(b)
			b.position = Vector3(0, 0.95 * s, 0)
			b.scale = Vector3.ONE * 0.2
			b.create_tween().tween_property(b, "scale", Vector3.ONE * 1.15 * s, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		"timeslow":
			_quad(n, rune_mat("clock", pal("time", 1), 0.25, 0.6), 1.3 * s, Vector3(0, 0.1, 0))
	return n

## Remove a status visual (frozen shells shatter).
static func end_status_node(nd: Node3D, a = null) -> void:
	var mg = mgr()
	if nd.name == "fx_freeze" and mg != null and a != null and is_instance_valid(a) and not a.is_dead:
		mg.emit(a.global_position + Vector3(0, 0.7, 0), {"n": 14, "life": 0.7, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.16, "v0": 2.5, "v1": 5.0, "dir": Vector3.UP, "spread": 80.0, "grav": Vector3(0, -12, 0), "ang": 400.0, "critical": true})
	for ch in nd.get_children():
		if ch is CPUParticles3D:
			ch.emitting = false
	var tw := nd.create_tween()
	tw.tween_property(nd, "scale", Vector3.ONE * 0.01, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(nd.queue_free)

# ======================================================================= loot
## Rarity dressing of a dropped item. Returns the beam to animate (or null).
static func loot(parent: Node3D, rar: int, col: Color) -> MeshInstance3D:
	var mg = mgr()
	var fx: int = mg.fx if mg != null else 1
	var budget := float(Settings.vq("particles", 0.7))
	var beam: MeshInstance3D = null
	if rar == 3:
		var p := CPUParticles3D.new()
		_loot_emitter(p, {"amount": maxi(3, int(9 * budget)), "life": 1.6, "mat": "add", "col": Color(0.75, 0.4, 1.0, 0.9), "size": 0.12, "rad": 0.45, "v0": 0.2, "v1": 0.6, "tan": 0.0})
		parent.add_child(p)
	if rar >= 4:
		var gold := rar == 4
		beam = MeshInstance3D.new()
		beam.mesh = pmesh("column")
		var bc := Color(1.0, 0.8, 0.3, 0.7) if gold else Color(1.0, 0.12, 0.22, 0.85)
		beam.material_override = smat("column", {"col": bc, "bands": 5.0 if gold else 8.0}, "lootbeam%d" % rar)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bw := 0.32 if gold else 0.48
		beam.scale = Vector3(bw, 10.0 if gold else 13.0, bw)
		beam.position = Vector3(0, beam.scale.y * 0.5, 0)
		parent.add_child(beam)
		var core := MeshInstance3D.new()
		core.mesh = pmesh("column")
		core.material_override = smat("column", {"col": Color(1, 1, 0.9, 0.6), "bands": 3.0}, "lootcore")
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.scale = Vector3(0.07, beam.scale.y * 0.8, 0.07)
		core.position = Vector3(0, core.scale.y * 0.5, 0)
		parent.add_child(core)
		var sw := CPUParticles3D.new()
		_loot_emitter(sw, {"amount": maxi(6, int((14 if gold else 20) * budget)), "life": 1.8, "mat": "star", "col": Color(1.0, 0.88, 0.45) if gold else Color(1.0, 0.3, 0.35), "size": 0.2, "rad": 0.7, "v0": 0.6, "v1": 1.4, "tan": 2.5})
		parent.add_child(sw)
		if gold:
			var gl := CPUParticles3D.new()
			_loot_emitter(gl, {"amount": maxi(3, int(6 * budget)), "life": 0.9, "mat": "star", "col": Color(1.0, 0.95, 0.6), "size": 0.32, "rad": 0.5, "v0": 0.0, "v1": 0.05, "tan": 0.0, "flat": true})
			parent.add_child(gl)
		else:
			ground_rune(Vector3(0, 0.05, 0), "sigil", Color(1.0, 0.15, 0.25), 1.3, 0.0, 0.5, 0.9, parent)
			var rn := CPUParticles3D.new()
			_loot_emitter(rn, {"amount": 5, "life": 2.4, "mat": "star", "col": Color(1.0, 0.25, 0.3), "size": 0.35, "rad": 0.9, "v0": 0.15, "v1": 0.35, "tan": 1.6})
			parent.add_child(rn)
			if mg != null and fx >= 2:
				var dq := MeshInstance3D.new()
				dq.mesh = pmesh("quad")
				dq.material_override = smat("distort", {"tint": Color(1.0, 0.15, 0.25, 0.3), "strength": 0.03, "billboard": 1}, "lootdist")
				dq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				dq.scale = Vector3.ONE * 2.6
				dq.position = Vector3(0, 0.8, 0)
				parent.add_child(dq)
			else:
				var rv := CPUParticles3D.new()
				_loot_emitter(rv, {"amount": 2, "life": 1.6, "mat": "ringv", "col": Color(1.0, 0.15, 0.25, 0.8), "size": 2.4, "rad": 0.0, "v0": 0.0, "v1": 0.0, "tan": 0.0, "grow": true})
				rv.position = Vector3(0, 0.8, 0)
				parent.add_child(rv)
	return beam

static func _loot_emitter(p: CPUParticles3D, o: Dictionary) -> void:
	p.amount = int(o.amount)
	p.lifetime = float(o.life)
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE if not o.get("flat", false) else CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_sphere_radius = maxf(0.01, float(o.rad))
	p.emission_box_extents = Vector3(float(o.rad), 0.05, float(o.rad))
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = float(o.v0)
	p.initial_velocity_max = float(o.v1)
	p.gravity = Vector3.ZERO
	p.tangential_accel_min = float(o.tan)
	p.tangential_accel_max = float(o.tan)
	p.mesh = pmesh("quad")
	p.material_override = pmat(str(o.mat))
	p.color = o.col
	p.color_ramp = ramp("pop")
	p.scale_amount_min = float(o.size) * 0.6
	p.scale_amount_max = float(o.size)
	if o.get("grow", false):
		p.scale_amount_curve = curve("grow")
	p.position.y = 0.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
