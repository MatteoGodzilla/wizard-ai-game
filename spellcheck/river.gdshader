shader_type spatial;

uniform float animation_time = 0.0;
instance uniform float frozen = 0.0;
instance uniform vec4 dye : source_color = vec4(0.0);

varying vec2 arena_uv;

void vertex() {
	arena_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float wave = sin(arena_uv.x * 6.0 + arena_uv.y * 3.0 - animation_time * 1.8);
	wave += 0.55 * sin(arena_uv.x * 9.0 - arena_uv.y * 5.0 + animation_time);
	float glint = smoothstep(0.9, 1.5, wave);
	vec3 water = mix(vec3(0.07, 0.30, 0.34), vec3(0.31, 0.65, 0.67), glint * 0.54);
	float frost = abs(sin(arena_uv.y * 5.0 + sin(arena_uv.x * 5.7) * 1.4));
	vec3 ice = mix(vec3(0.36, 0.66, 0.80), vec3(0.73, 0.88, 0.95), smoothstep(0.84, 1.0, frost) * 0.55);
	ALBEDO = mix(mix(water, ice, frozen), dye.rgb, dye.a * 0.65);
	ROUGHNESS = mix(0.3, 0.59, frozen);
}
