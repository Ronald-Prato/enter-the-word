extends "res://scripts/enemy.gd"

## RedMosquito: mismo `ShaderMaterial` neón que el verde (`mosquito_green_to_red.gdshader`),
## con `replace_color` rojo HDR; scraps vía `mosquito_neon_palette_remap`.

const ANIM_MOVING := &"moving"
const ANIM_ATTACK := &"attack"
const ANIM_DEATH := &"death"

const _FLIP_VEL_EPS := float(6.0)
## Mismo rojo que `HitParticles` al recibir daño (fallback si no se puede muestrear el sprite).
const RED_MOSQUITO_HIT_SPARK := Color(1.0, 0.65, 0.65, 1.0)
## Estela del dash del red mosquito (viejo -> nuevo): rojo translúcido a rojo vivo.
const RED_MOSQUITO_TRAIL_GRADIENT_OLD := Color(0.85, 0.35, 0.35, 0.0)
const RED_MOSQUITO_TRAIL_GRADIENT_NEW := Color(1.1, 0.6, 0.6, 0.95)
## HDR rojo neón durante WINDUP (bloom vía WorldEnvironment).
const WINDUP_NEON_BASE := Color(2.5, 0.5, 0.5, 1.0)
const WINDUP_NEON_CHARGED := Color(4.5, 0.65, 0.65, 1.0)

const _DEATH_SCRAPS_SCENE: PackedScene = preload("res://scenes/mosquito_death_scraps.tscn")
const _NEON_PALETTE_REMAP := preload("res://scripts/mosquito_neon_palette_remap.gd")

@export var strike_hit_forward_px: float = 26.0
@export var strike_hit_shape_size: Vector2 = Vector2(38, 22)
## Tope de HDR en el sprite al recibir golpe (bloom sigue la silueta del pixel art).
@export_range(1.2, 5.5, 0.05) var hit_flash_sprite_hdr_peak: float = 3.05
@export_range(4, 28, 1) var death_scrap_count: int = 16
@export_range(4.0, 28.0, 0.5) var death_scrap_spread_px: float = 14.0

@onready var _sprite: AnimatedSprite2D = $MosquitoSprite
@onready var _strike_hit_area: Area2D = $StrikeHitArea

var _mosquito_palette_mat: ShaderMaterial

var _prev_ai_state: State = State.IDLE
var _last_flip_h: bool = false
var _attack_anim_started_for_strike: bool = false
var _hit_flash_intensity_for_sprite: float = 0.0
var _combo_remaining: int = 0


func _sync_hit_flash_visual(intensity: float) -> void:
	_hit_flash_intensity_for_sprite = intensity
	_apply_mosquito_sprite_modulate()


func _apply_mosquito_sprite_modulate() -> void:
	if _sprite == null:
		return
	if _dying and _hit_flash_intensity_for_sprite <= 0.001:
		_sprite.self_modulate = Color.WHITE
		return
	if _hit_flash_intensity_for_sprite > 0.001:
		var i: float = clampf(_hit_flash_intensity_for_sprite, 0.0, 1.0)
		var peak: float = minf(player_hit_flash_hdr, hit_flash_sprite_hdr_peak)
		var m: float = lerpf(1.0, peak, i)
		_sprite.self_modulate = Color(m, m * 0.35, m * 0.35, 1.0)
		return
	if get_ai_state() == State.WINDUP:
		_sprite.self_modulate = _windup_charge_self_modulate()
		return
	_sprite.self_modulate = Color.WHITE


func _windup_charge_self_modulate() -> Color:
	var charge_t: float = get_attack_windup_charge_progress()
	var pulse: float = 0.86 + 0.14 * sin(Time.get_ticks_msec() * 0.0085)
	var c: Color = WINDUP_NEON_BASE.lerp(WINDUP_NEON_CHARGED, charge_t)
	return Color(c.r * pulse, c.g * pulse, c.b * pulse, 1.0)


func _ready() -> void:
	if _sprite != null:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _sprite.sprite_frames == null:
			push_warning("RedMosquitoEnemy: asigná SpriteFrames en MosquitoSprite o en mosquito_sprite_frames.tres.")
	super._ready()
	if _sprite != null:
		_mosquito_palette_mat = _sprite.material as ShaderMaterial
	if _sprite != null:
		_sprite.animation_finished.connect(_on_sprite_anim_finished)
	_configure_attack_trail_visual()
	_configure_mosquito_hit_particles()
	if _strike_hit_area != null:
		_strike_hit_area.collision_layer = 0
		_strike_hit_area.collision_mask = 1
		_strike_hit_area.monitoring = false
		_strike_hit_area.monitorable = false
		var cs := _strike_hit_area.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape is RectangleShape2D:
			(cs.shape as RectangleShape2D).size = strike_hit_shape_size
			cs.position = Vector2(strike_hit_shape_size.x * 0.32, 0.0)


func _configure_attack_trail_visual() -> void:
	if _trail == null:
		return
	var grad := Gradient.new()
	grad.add_point(0.0, RED_MOSQUITO_TRAIL_GRADIENT_OLD)
	grad.add_point(1.0, RED_MOSQUITO_TRAIL_GRADIENT_NEW)
	_trail.gradient = grad
	_trail.default_color = RED_MOSQUITO_TRAIL_GRADIENT_NEW


func _configure_mosquito_hit_particles() -> void:
	if _hit_particles == null:
		return
	_hit_particles.color = RED_MOSQUITO_HIT_SPARK
	_hit_particles.amount = 5
	_hit_particles.spread = 18.0
	_hit_particles.initial_velocity_min = 72.0
	_hit_particles.initial_velocity_max = 118.0
	_hit_particles.scale_amount_min = 0.65
	_hit_particles.scale_amount_max = 1.05
	_hit_spark_color_ramp = _create_mosquito_hit_spark_color_ramp()
	_hit_particles.color_ramp = _hit_spark_color_ramp


func _create_mosquito_hit_spark_color_ramp() -> Gradient:
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.82, 0.82, 1.0))
	grad.add_point(0.32, Color(1.0, 0.5, 0.5, 1.0))
	grad.add_point(0.68, Color(0.85, 0.35, 0.35, 0.82))
	grad.add_point(1.0, Color(0.6, 0.15, 0.15, 0.0))
	return grad


func _try_hit_player() -> void:
	pass


func _after_physics_step(_delta: float) -> void:
	if _dying or _sprite == null or _strike_hit_area == null:
		return
	var st: State = get_ai_state()

	# Detectar inicio de nuevo combo (CHASE -> WINDUP): preparar ataque extra
	if _prev_ai_state == State.CHASE and st == State.WINDUP:
		_combo_remaining = 1

	# Detectar fin de ataque (STRIKE -> CHASE): forzar segundo ataque si queda
	if _prev_ai_state == State.STRIKE and st == State.CHASE:
		if _combo_remaining > 0:
			_combo_remaining -= 1
			_state = State.WINDUP
			_windup_remaining = attack_windup_s
			_aim_locked = false
			velocity = Vector2.ZERO
			_freeze_attack_windup_visual()
			st = State.WINDUP

	if st == State.WINDUP:
		_freeze_attack_windup_visual()
	elif st == State.STRIKE:
		if _prev_ai_state != State.STRIKE:
			_attack_anim_started_for_strike = false
		_run_strike_visual_and_hitbox()
	else:
		_attack_anim_started_for_strike = false
		_strike_hit_area.monitoring = false
		_sync_moving_locomotion_visual()

	_prev_ai_state = st
	_apply_mosquito_sprite_modulate()


func _freeze_attack_windup_visual() -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(ANIM_ATTACK):
		return
	_sprite.animation = ANIM_ATTACK
	_sprite.stop()
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.speed_scale = 1.0


func _run_strike_visual_and_hitbox() -> void:
	var dash_on: bool = is_strike_dash_active()
	_position_strike_hit_area()

	if dash_on:
		_strike_hit_area.monitoring = true
		if not _attack_anim_started_for_strike:
			_attack_anim_started_for_strike = true
			if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(ANIM_ATTACK):
				_sprite.play(ANIM_ATTACK)
				var max_f: int = maxi(_sprite.sprite_frames.get_frame_count(ANIM_ATTACK) - 1, 0)
				if max_f >= 1:
					_sprite.set_frame_and_progress(1, 0.0)
				else:
					_sprite.set_frame_and_progress(0, 0.0)
				_sprite.speed_scale = 1.0
		_try_strike_area_damage()
	else:
		_strike_hit_area.monitoring = false


func _position_strike_hit_area() -> void:
	var dir: Vector2 = get_strike_direction()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	_strike_hit_area.global_rotation = dir.angle()
	_strike_hit_area.global_position = global_position + dir * strike_hit_forward_px


func _try_strike_area_damage() -> void:
	if get_strike_hit_done():
		return
	for b in _strike_hit_area.get_overlapping_bodies():
		if b.is_in_group("player") and b.has_method("take_damage"):
			if b.has_method("is_damage_invulnerable") and bool(b.call("is_damage_invulnerable")):
				register_strike_hit_consumed()
				return
			var to_p: Vector2 = b.global_position - global_position
			b.call("take_damage", player_damage, to_p)
			register_strike_hit_consumed()
			return


func _sync_moving_locomotion_visual() -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(ANIM_MOVING):
		return
	if _sprite.animation != ANIM_MOVING or not _sprite.is_playing():
		_sprite.play(ANIM_MOVING)
	var v: Vector2 = velocity
	if absf(v.x) > _FLIP_VEL_EPS:
		_last_flip_h = v.x < 0.0
	_sprite.flip_h = _last_flip_h
	_sprite.speed_scale = 1.0


func _play_death_outro() -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_set_flash_intensity(0.0)
	_spawn_mosquito_death_scraps()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(ANIM_DEATH):
		if _strike_hit_area != null:
			_strike_hit_area.monitoring = false
		_sprite.sprite_frames.set_animation_loop(ANIM_DEATH, false)
		_sprite.play(ANIM_DEATH)
		return
	super._play_death_outro()


func _spawn_mosquito_death_scraps() -> void:
	var room := get_tree().get_first_node_in_group("current_room") as Node2D
	if room == null:
		return
	var scraps := _DEATH_SCRAPS_SCENE.instantiate() as Node2D
	if scraps == null:
		return
	var data := _build_death_scrap_data(death_scrap_count, death_scrap_spread_px)
	room.add_child(scraps)
	scraps.global_position = global_position
	if scraps.has_method("setup"):
		scraps.call("setup", global_position, data["colors"], data["offsets"])
	if Dungeon.use_generated():
		var scrap_data := {
			"colors": data["colors"].duplicate(),
			"offsets": data["offsets"].duplicate(),
			"position": scraps.position,
		}
		Dungeon.add_room_scrap(Dungeon.current_room_id, scrap_data)


func _build_death_scrap_data(count: int, spread: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var colors := PackedColorArray()
	var offs := PackedVector2Array()
	var img: Image = _get_mosquito_frame_image_for_scraps()
	if img == null or img.get_width() < 1 or img.get_height() < 1:
		for _i in count:
			colors.append(RED_MOSQUITO_HIT_SPARK)
			offs.append(_random_scrap_offset(rng, spread))
		return {"colors": colors, "offsets": offs}
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 1 or h < 1:
		for _i in count:
			colors.append(RED_MOSQUITO_HIT_SPARK)
			offs.append(_random_scrap_offset(rng, spread))
		return {"colors": colors, "offsets": offs}
	var max_attempts: int = maxi(count * 50, 50)
	var attempts := 0
	while colors.size() < count and attempts < max_attempts:
		attempts += 1
		var px: int = rng.randi_range(0, w - 1)
		var py: int = rng.randi_range(0, h - 1)
		var col: Color = img.get_pixel(px, py)
		if col.a < 0.2:
			continue
		col = _NEON_PALETTE_REMAP.remap_scrap_pixel(col, _mosquito_palette_mat, true)
		colors.append(col)
		offs.append(_random_scrap_offset(rng, spread))
	while colors.size() < count:
		var fb: Color = RED_MOSQUITO_HIT_SPARK
		if colors.size() > 0:
			fb = colors[rng.randi_range(0, colors.size() - 1)]
		colors.append(fb)
		offs.append(_random_scrap_offset(rng, spread))
	return {"colors": colors, "offsets": offs}


func _random_scrap_offset(rng: RandomNumberGenerator, spread: float) -> Vector2:
	return Vector2(
		rng.randf_range(-spread, spread),
		rng.randf_range(-spread * 0.55, spread * 0.55)
	)


func _get_mosquito_frame_image_for_scraps() -> Image:
	if _sprite == null or _sprite.sprite_frames == null:
		return null
	var anim: StringName = _sprite.animation
	if not _sprite.sprite_frames.has_animation(anim) and _sprite.sprite_frames.has_animation(ANIM_MOVING):
		anim = ANIM_MOVING
	if not _sprite.sprite_frames.has_animation(anim):
		return null
	var fc: int = _sprite.sprite_frames.get_frame_count(anim)
	if fc < 1:
		return null
	var frame_i: int = clampi(_sprite.frame, 0, fc - 1)
	var tex: Texture2D = _sprite.sprite_frames.get_frame_texture(anim, frame_i)
	if tex == null and anim != ANIM_MOVING and _sprite.sprite_frames.has_animation(ANIM_MOVING):
		fc = _sprite.sprite_frames.get_frame_count(ANIM_MOVING)
		if fc < 1:
			return null
		tex = _sprite.sprite_frames.get_frame_texture(ANIM_MOVING, 0)
	if tex == null:
		return null
	return _texture_to_rgba_image(tex)


func _texture_to_rgba_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		return img
	if tex is AtlasTexture:
		var at := tex as AtlasTexture
		var base_tex: Texture2D = at.atlas
		if base_tex == null:
			return null
		var base_img: Image = base_tex.get_image()
		if base_img == null or base_img.get_width() < 1 or base_img.get_height() < 1:
			return null
		if base_img.get_format() != Image.FORMAT_RGBA8:
			base_img.convert(Image.FORMAT_RGBA8)
		var r := Rect2i(
			int(at.region.position.x),
			int(at.region.position.y),
			int(at.region.size.x),
			int(at.region.size.y)
		)
		return base_img.get_region(r)
	return null


func _on_sprite_anim_finished() -> void:
	if _dying and _sprite.animation == ANIM_DEATH:
		queue_free()
		return
	if _sprite.animation == ANIM_ATTACK and get_ai_state() == State.CHASE:
		_sync_moving_locomotion_visual()
