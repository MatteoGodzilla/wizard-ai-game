shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

instance uniform vec4 ground_tint : source_color = vec4(0.26, 0.41, 0.29, 1.0);
instance uniform float scorch : hint_range(0.0, 1.0) = 0.0;

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(217.43, 71.7))) * 43758.5453);
}

void fragment() {
	vec2 patch = abs(UV - 0.5) * 2.0;
	float texture_noise = grain(floor(UV * 54.0));
	float patch_noise = sin(UV.x * 23.5) * cos(UV.y * 19.0);
	float edge = 1.0 - smoothstep(0.55, 1.08, length(patch) + patch_noise * 0.08 + texture_noise * 0.055);
	vec3 grass = ground_tint.rgb * (0.88 + texture_noise * 0.17);
	vec3 ash = mix(vec3(0.051, 0.026, 0.016), vec3(0.125, 0.066, 0.034), texture_noise * texture_noise);
	ALBEDO = mix(grass, ash, scorch);
	ROUGHNESS = 1.0;
	ALPHA = edge;
}
