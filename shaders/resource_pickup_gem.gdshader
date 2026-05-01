shader_type canvas_item;
render_mode unshaded;

uniform float pulse_speed : hint_range(0.0, 12.0) = 3.5;
uniform float shine : hint_range(1.0, 2.5) = 1.45;

void fragment() {
	float pulse = 0.9 + 0.1 * sin(TIME * pulse_speed);
	vec3 rgb = COLOR.rgb * shine * pulse;
	COLOR = vec4(rgb, COLOR.a);
}
