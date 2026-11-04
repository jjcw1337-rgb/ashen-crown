shader_type spatial;
// The raid stash chest's gold wolf seals (jj's pick B; Game.chest_seals): Meshy's gold, with the molten-gold grooves
// it painted (bright, saturated orange-gold texels) lit from inside and breathing; `energy` flares as they burst off.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float energy = 2.2;
uniform float phase = 0.0;
uniform vec3 glow_col : source_color = vec3(1.0, 0.62, 0.18);   // the grooves' light (blue on stash #2)

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb;
	METALLIC = 0.85;
	ROUGHNESS = 0.35;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float hot = clamp((a.r - a.b) * 2.2 - 0.5, 0.0, 1.0) * clamp((a.r + a.g) * 0.9 - 0.75, 0.0, 1.0);
	float breath = 0.7 + 0.3 * sin(TIME * 1.6 + phase) + 0.1 * sin(TIME * 4.1 + phase * 1.7);
	EMISSION = glow_col * (hot * 2.6 + 0.3) * energy * breath;
}
