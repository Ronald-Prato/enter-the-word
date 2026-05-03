extends Object

## Misma lógica que `mosquito_green_to_red.gdshader` para colores de death-scraps.

static func remap_scrap_pixel(c: Color, palette_mat: ShaderMaterial, legacy_swap_rg_when_no_mat: bool) -> Color:
	if c.a < 0.2:
		return c
	if palette_mat == null or palette_mat.shader == null:
		return Color(c.g, c.r, c.b, c.a) if legacy_swap_rg_when_no_mat else c

	var target: Color = palette_mat.get_shader_parameter("target_color") as Color
	var replace: Color = palette_mat.get_shader_parameter("replace_color") as Color
	var tol: float = float(palette_mat.get_shader_parameter("tolerance"))
	var soft: float = float(palette_mat.get_shader_parameter("edge_softness"))
	var dpv: Variant = palette_mat.get_shader_parameter("dominance_weight")
	var dom_w: float = 0.96 if dpv == null else float(dpv)

	var d: float = Vector3(c.r, c.g, c.b).distance_to(Vector3(target.r, target.g, target.b))
	var t0: float = maxf(0.0, tol - soft)
	var blend_key: float = 1.0 - _smoothstep(t0, tol + soft, d)
	var green_dom: float = _smoothstep(0.03, 0.24, c.g - maxf(c.r, c.b) * 0.88)
	var blend: float = clampf(maxf(blend_key, green_dom * dom_w), 0.0, 1.0)

	var lum_src: float = _rgb_luminance(c)
	var peak_src: float = maxf(c.r, maxf(c.g, c.b))
	var piv: Variant = palette_mat.get_shader_parameter("peak_influence")
	var peak_inf: float = 0.96 if piv == null else float(piv)
	var drive: float = maxf(lum_src, peak_src * peak_inf)
	var lum_rep: float = maxf(_rgb_luminance(replace), 0.03)

	var nb: float = 1.92
	var nbp: Variant = palette_mat.get_shader_parameter("neon_boost")
	if nbp != null:
		nb = float(nbp)
	else:
		var legacy: Variant = palette_mat.get_shader_parameter("red_boost")
		if legacy != null:
			nb = float(legacy)

	var lum_param: Variant = palette_mat.get_shader_parameter("luminance_match")
	var lum_match: float = 1.0 if lum_param == null else float(lum_param)
	var scale: float = (drive / lum_rep) * nb
	var rep_matched := Color(replace.r * scale, replace.g * scale, replace.b * scale, replace.a)
	var rep_flat := Color(replace.r, replace.g, replace.b, replace.a)
	var replacement: Color = rep_flat.lerp(rep_matched, lum_match)
	return c.lerp(replacement, blend)


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0 if x < edge0 else 1.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _rgb_luminance(col: Color) -> float:
	return 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
