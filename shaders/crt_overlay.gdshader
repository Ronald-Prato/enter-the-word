shader_type canvas_item;

// CRT encima del juego: lee la pantalla, aberración cromática radial, scanlines, rejilla, viñeta.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

/// 0 = sin máscaras CRT, 1 = máximo (scanlines / rejilla / viñeta / tint).
uniform float effect_mix : hint_range(0.0, 1.0) = 0.76;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float scanline_count : hint_range(50.0, 800.0) = 310.0;
uniform float pixel_grid_intensity : hint_range(0.0, 1.0) = 0.11;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.28;
uniform float curvature : hint_range(0.0, 0.15) = 0.032;
uniform vec4 tint : source_color = vec4(0.96, 0.98, 0.9, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.055;

uniform float chroma_strength : hint_range(0.0, 0.025) = 0.0044;
uniform float chroma_mix : hint_range(0.0, 1.0) = 0.82;

vec3 sample_screen_chromatic(vec2 base_uv, vec2 screen_centered) {
	vec3 base_col = texture(screen_texture, base_uv).rgb;
	if (chroma_strength < 1e-6) {
		return base_col;
	}
	float dist01 = length(screen_centered) / 0.707;
	vec2 radial = vec2(1.0, 0.0);
	float dl = length(screen_centered);
	if (dl > 1e-5) {
		radial = screen_centered / dl;
	}
	float edge_boost = mix(0.45, 1.25, smoothstep(0.2, 1.0, dist01));
	vec2 ofs = radial * chroma_strength * edge_boost;
	vec2 r_uv = clamp(base_uv + ofs, vec2(0.0005), vec2(0.9995));
	vec2 b_uv = clamp(base_uv - ofs, vec2(0.0005), vec2(0.9995));
	vec3 aberrated = vec3(
			texture(screen_texture, r_uv).r,
			texture(screen_texture, base_uv).g,
			texture(screen_texture, b_uv).b
	);
	return mix(base_col, aberrated, chroma_mix);
}

void fragment() {
	vec2 su = SCREEN_UV;

	vec2 centered = su - 0.5;
	float dist = length(centered);
	float curve_factor = 1.0 + curvature * dist * dist;
	vec2 sample_uv = centered * curve_factor + 0.5;
	sample_uv = clamp(sample_uv, vec2(0.0005), vec2(0.9995));

	vec3 scene = sample_screen_chromatic(sample_uv, centered);

	float scanline = sin(su.y * scanline_count * 3.14159265) * 0.5 + 0.5;
	scanline = pow(scanline, 1.42);
	float scan_mul = mix(1.0, scanline, scanline_intensity);

	float pixel_line = sin(su.x * scanline_count * 0.75 * 3.14159265) * 0.5 + 0.5;
	pixel_line = pow(pixel_line, 1.42);
	float pixel_mul = mix(1.0, pixel_line, pixel_grid_intensity);

	vec2 vig_uv = su - 0.5;
	float vignette_dist = length(vig_uv) / 0.707;
	float vig_mul = 1.0 - smoothstep(0.4, 1.0, vignette_dist) * vignette_intensity;

	float combined = scan_mul * pixel_mul * vig_mul;
	float m = mix(1.0, combined, effect_mix);
	scene *= m;
	scene *= mix(vec3(1.0), tint.rgb, tint_strength * effect_mix);

	COLOR = vec4(scene, 1.0);
}
