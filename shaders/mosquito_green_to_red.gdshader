shader_type canvas_item;

// Paleta neón compartida (mosquito verde o rojo): acerca el sprite a `replace_color` con HDR/bloom.
// `dominance_weight` + distancia al `target_color` aseguran attack/moving cubiertos.

uniform vec4 target_color : source_color = vec4(0.34, 0.7, 0.41, 1.0);
uniform vec4 replace_color : source_color = vec4(2.15, 0.48, 0.38, 1.0);
uniform float tolerance : hint_range(0.0, 1.35) = 0.68;
uniform float edge_softness : hint_range(0.02, 0.55) = 0.28;
uniform float dominance_weight : hint_range(0.0, 1.0) = 0.96;
uniform float luminance_match : hint_range(0.0, 1.0) = 1.0;
uniform float neon_boost : hint_range(0.9, 3.0) = 1.92;
uniform float peak_influence : hint_range(0.0, 1.0) = 0.96;

float rgb_luminance(vec3 rgb) {
	return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 modu = COLOR;
	vec4 tex_color = texture(TEXTURE, UV);

	float dist = distance(tex_color.rgb, target_color.rgb);
	float t0 = max(0.0, tolerance - edge_softness);
	float blend_key = 1.0 - smoothstep(t0, tolerance + edge_softness, dist);

	float green_dom = smoothstep(0.03, 0.24, tex_color.g - max(tex_color.r, tex_color.b) * 0.88);
	float blend = clamp(max(blend_key, green_dom * dominance_weight), 0.0, 1.0);

	float lum_src = rgb_luminance(tex_color.rgb);
	float peak_src = max(max(tex_color.r, tex_color.g), tex_color.b);
	float drive = max(lum_src, peak_src * peak_influence);

	float lum_rep = max(rgb_luminance(replace_color.rgb), 0.03);
	float match = (drive / lum_rep) * neon_boost;

	vec3 rep_matched = replace_color.rgb * match;
	vec3 rep_flat = replace_color.rgb;
	vec3 replacement = mix(rep_flat, rep_matched, luminance_match);

	vec3 out_rgb = mix(tex_color.rgb, replacement, blend);
	COLOR = vec4(out_rgb * modu.rgb, tex_color.a * modu.a);
}
