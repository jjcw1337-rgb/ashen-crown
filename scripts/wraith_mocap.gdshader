// The Wraith's body (Wraith._spectral): Meshy's own textures, lit like everything else, plus
//  - the cold cyan light in the robe's tears and its eyes (the bluest, brightest texels glow, breathing slowly)
//  - a faint rim of spirit-light so it reads against dark ground
//  - the robe, shins and feet fraying into mist toward the hem: vertex colour R (0 at the hips, 1 at the hem,
//    tools/blender/wraith/prep_wraith_mocap.py) against drifting 3D noise; what's eaten is cut away (no sorting
//    trouble on a skinned mesh) with a glowing edge, and the hem's mist particles fill in the softness
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform bool use_rough = false;
uniform vec3 spirit : source_color = vec3(0.35, 0.85, 1.0);
uniform float fray = 0.62;        // how much of the way down the robe starts to fray (0..1 of R)
uniform float glow = 1.0;         // the tears' and eyes' light (skills can flare it)
uniform float phase_amt = 0.0;    // 0..1: the whole body thinning to spirit (Wraithform, dissolves)

varying vec3 wpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 7.3) * 0.3 + noise(p * 4.3 + 1.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float down = COLOR.r;
	// the fray: noise drifting upward through the robe; past the threshold it's gone
	float n = fbm(wpos * vec3(5.5, 3.2, 5.5) + vec3(0.0, -TIME * 0.55, 0.0));
	float eat = smoothstep(fray, 1.0, down) * 1.15 + phase_amt * 0.85;
	float keep = n - eat;
	if (keep < 0.0) {
		discard;
	}
	float edge = (1.0 - smoothstep(0.0, 0.14, keep)) * step(0.02, eat);
	vec3 col = c.rgb * mix(1.0, 0.55, smoothstep(0.2, 1.0, down));
	ALBEDO = col;
	// matte grave-cloth: Meshy's roughness map makes the robe wet and glassy, so it's only allowed to roughen
	ROUGHNESS = use_rough ? max(texture(rough_tex, UV).g, 0.82) : 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	// the light inside: blue-cyan texels brighter than their red
	float cyan = smoothstep(0.1, 0.22, c.b - c.r) * smoothstep(0.32, 0.6, c.b);
	float breathe = 0.75 + 0.25 * sin(TIME * 1.9 + wpos.y * 3.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = spirit * (cyan * 1.2 * breathe * glow + rim * 0.16 + edge * 1.4 + phase_amt * 0.6 * rim);
}
