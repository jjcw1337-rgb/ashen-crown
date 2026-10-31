// The Demon's mocap body (Demon.build_mocap): Meshy's textures kept matte (cracked charcoal skin, never plastic),
// with the magma showing through the cracks: the hot orange texels of the albedo glow, breathing slowly, flaring
// with "glow" (attacks, casts, a hit's pulse), cooling to dark cinders as he dies ("cool"); the wing membrane
// (vertex colour G) is a touch backlit; phased into the Underworld ("phase_amt") he goes to a shadow, see-through
// and violet, the lava dimmed.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform vec3 ember : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 soul : source_color = vec3(0.62, 0.42, 1.0);
uniform float glow = 0.0;        // extra lava light (0 at rest; attacks, casts and hits push it)
uniform float cool = 0.0;        // 1 = the lava gone dark (death)
uniform float phase_amt = 0.0;   // 1 = in the Underworld
uniform float lava_base = 1.0;   // the lava's light at rest
varying float v_wing;

float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

void vertex(){
	v_wing = COLOR.g;
}

void fragment(){
	vec4 tex = texture(albedo_tex, UV);
	vec3 alb = tex.rgb;
	// the cracks: where the texture is lava (strong red over the green and blue, bright enough)
	float warm = alb.r - max(alb.g * 1.15, alb.b * 1.6);
	float hot = smoothstep(0.08, 0.32, warm) * smoothstep(0.25, 0.5, alb.r);
	// the magma breathes slowly, not all of it at once
	float breathe = 0.72 + 0.28 * sin(TIME * 1.25 + UV.y * 7.0 + UV.x * 3.0);
	float life = clamp(lava_base * breathe + glow, 0.0, 3.0) * (1.0 - cool);
	// cooled cracks are black cinders with a last dull red deep in them
	vec3 cinder = mix(vec3(0.05, 0.035, 0.03), vec3(0.16, 0.03, 0.01), 0.3 * (1.0 - cool) + 0.2 * h21(floor(UV * 240.0)));
	vec3 skin = mix(alb, cinder, hot * cool);
	vec3 em = alb * alb * hot * life * 2.2 + ember * hot * life * 0.35;
	// the membrane lets a little light through, warm from the body
	em += ember * v_wing * 0.08 * (1.0 - cool) * (0.6 + 0.4 * breathe);
	// the Underworld: a shadow of himself, dithered away, violet through the cracks
	if (phase_amt > 0.001) {
		float n = h21(FRAGCOORD.xy * 0.731 + vec2(floor(TIME * 8.0) * 0.37, 0.0));
		if (n < phase_amt * 0.6) {
			discard;
		}
		skin = mix(skin, vec3(0.04, 0.02, 0.07), phase_amt * 0.75);
		em = mix(em, soul * (0.35 * hot + 0.12 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5)), phase_amt * 0.85);
	}
	ALBEDO = skin;
	ROUGHNESS = 0.9 - 0.12 * hot * (1.0 - cool);
	METALLIC = 0.0;
	SPECULAR = 0.18;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.8;
	}
	EMISSION = em;
}
