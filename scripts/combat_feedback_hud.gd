extends Control

## Viñeta roja al recibir daño; mismo grupo que skai (`player_hud` + `flash_damage_vignette`).

@export var damage_vignette_duration: float = 0.42
@export var damage_vignette_peak: float = 0.34
@export var damage_vignette_crack_peak: float = 0.26
@export var damage_vignette_crack_fade_mult: float = 0.42

@onready var _damage_vignette: ColorRect = $DamageVignette

var _vignette_tween: Tween


func _ready() -> void:
	if not is_in_group("player_hud"):
		add_to_group("player_hud")
	if _damage_vignette != null:
		_damage_vignette.z_as_relative = false
		_damage_vignette.z_index = -2
	_reset_vignette()


func flash_damage_vignette() -> void:
	var mat := _get_vignette_material()
	if mat == null:
		return
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	mat.set_shader_parameter("intensity", damage_vignette_peak)
	mat.set_shader_parameter("crack_strength", damage_vignette_crack_peak)
	_vignette_tween = create_tween()
	_vignette_tween.set_parallel(true)
	var crack_dur: float = maxf(damage_vignette_duration * damage_vignette_crack_fade_mult, 0.06)
	_vignette_tween.tween_method(_set_vignette_intensity, damage_vignette_peak, 0.0, damage_vignette_duration).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	_vignette_tween.tween_method(_set_vignette_crack, damage_vignette_crack_peak, 0.0, crack_dur).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN)


func _set_vignette_intensity(v: float) -> void:
	var mat := _get_vignette_material()
	if mat == null:
		return
	mat.set_shader_parameter("intensity", v)


func _set_vignette_crack(v: float) -> void:
	var mat := _get_vignette_material()
	if mat == null:
		return
	mat.set_shader_parameter("crack_strength", v)


func _reset_vignette() -> void:
	var mat := _get_vignette_material()
	if mat == null:
		return
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("crack_strength", 0.0)


func _get_vignette_material() -> ShaderMaterial:
	if _damage_vignette == null:
		return null
	return _damage_vignette.material as ShaderMaterial
