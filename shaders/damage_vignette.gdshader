shader_type canvas_item;

// Viñeta roja con sensación de cristal / pantalla rota al recibir daño.
// `intensity` y `crack_strength` se animan desde el HUD (impacto → 0).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.2, 0.12, 0.16, 0.28);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.78;
uniform float outer_radius : hint_range(0.1, 1.5) = 1.05;
uniform float curve : hint_range(0.5, 6.0) = 2.8;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float h0 = hash21(uv * 41.0);
	float h1 = hash21(uv * 37.0 + vec2(19.0, 3.0));
	vec2 uv_warp = uv + (vec2(h0, h1) - 0.5) * crack_strength * 0.022;

	float d = length(uv_warp) / 0.707;
	float mask = smoothstep(inner_radius, outer_radius, d);
	mask = pow(mask, curve);

	float ang = atan(uv_warp.y, uv_warp.x);
	float rad = length(uv_warp);
	float h2 = hash21(uv * 88.0);
	float spokes = abs(sin(ang * 13.0 + rad * 19.0 + h2 * 6.28318));
	float crack_lines = pow(smoothstep(0.78, 0.99, spokes), 2.8) * crack_strength * 0.45;

	float edge = smoothstep(inner_radius - 0.1, inner_radius + 0.04, d);
	float grain = (hash21(uv * 200.0) - 0.5) * crack_strength * 0.08 * mask * edge;

	float a = intensity * mask * color.a;
	a = clamp(a + crack_lines * intensity * 0.32 + grain * intensity, 0.0, 1.0);

	vec3 rgb = color.rgb * (1.0 + crack_strength * 0.12 * mask);
	COLOR = vec4(rgb, a);
}
