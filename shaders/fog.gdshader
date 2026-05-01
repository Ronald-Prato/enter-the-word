shader_type canvas_item;

// Textura de ruido: `filter_linear` interpola entre texels; con `filter_nearest` se ven bloques al escalar.
uniform sampler2D noise_texture : repeat_enable, filter_linear;
// Fog density
uniform float density : hint_range(0.0, 1.0) = 0.25;

// Desplazamiento UV por segundo (TIME); independiente del modo de cámara (sin ParallaxBackground).
uniform vec2 speed = vec2(0.12, 0.06);

void fragment() {
	vec2 uv = UV + speed * TIME;
	// Sample the noise texture (tiling; ColorRect ahora cubre el mismo rect que el ground).
	float noise = texture(noise_texture, uv).r;
	// Convert the noise from the (0.0, 1.0) range to the (-1.0, 1.0) range
	// and clamp it between 0.0 and 1.0 again
	float fog = clamp(noise * 2.0 - 1.0, 0.0, 1.0);
	// Apply the fog effect
	COLOR.a *= fog * density;
}
