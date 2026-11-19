shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 field_color : source_color = vec4(0.8, 0.2, 0.46, 1.0);

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.6);
	float stripe = 1.0 - smoothstep(0.05, 0.13, abs(sin((UV.y * 12.0 - TIME * 0.26) * 3.14159)));
	ALBEDO = field_color.rgb * (0.67 + rim * 0.36);
	ALPHA = 0.047 + rim * 0.28 + stripe * (0.035 + rim * 0.07);
}
