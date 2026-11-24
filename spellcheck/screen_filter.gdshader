shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec3 scene = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(clamp(mix(vec3(luminance), scene, saturation), vec3(0.0), vec3(1.0)), 1.0);
}
