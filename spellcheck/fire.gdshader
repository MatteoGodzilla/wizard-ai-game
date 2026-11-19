shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform float shift = 0.0;

void fragment() {
	float h = 1.0 - UV.y;
	float t = TIME * 5.0 + shift;
	float sway = sin(h * 10.0 - t) * h * 0.14 + sin(t * 1.6) * h * 0.1;
	float width = mix(0.42, 0.025, pow(h, 0.62));
	float body = 1.0 - smoothstep(width * 0.42, width, abs(UV.x - 0.5 - sway));
	float tip = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.61, 1.0, h + sin(t + UV.x * 16.0) * 0.17));
	float core = (1.0 - smoothstep(0.015, width * 0.63, abs(UV.x - 0.5 + sway * 0.2))) * (1.0 - h);
	ALBEDO = mix(vec3(1.0, 0.075, 0.012), vec3(1.0, 0.82, 0.22), core);
	ALPHA = body * tip * (0.46 + core * 0.5);
}
