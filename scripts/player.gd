extends CharacterBody2D

## Píxeles por segundo. Ajusta a gusto.
@export var speed: float = 96.0

## Daño base que aplica el jugador por golpe de cuerpo a cuerpo (enemigos).
@export var damage: float = 3.0

## Radio fijo del ataque cuerpo a cuerpo: el swing se alinea al borde de este círculo.
@export var attack_range: float = 70.0

## Escena de swing que colisiona con enemigos (igual que en skai).
@export var swing_scene: PackedScene

## Empuje al recibir daño: vector `from_direction` = desde el atacante hacia el jugador (como pasa `enemy.gd` / mosquito).
@export var damage_knockback_peak: float = 260.0
@export var damage_knockback_decay: float = 5.8
## Tope de velocidad extra por knockback (evita acumular varios golpes en un frame).
@export var damage_knockback_max_speed: float = 400.0

## Destello HDR en el sprite (bloom) al recibir daño; mismo enfoque que mosquito / `enemy.gd`.
@export var damage_hit_flash_duration: float = 0.26
@export_range(1.2, 5.5, 0.05) var damage_hit_flash_hdr_peak: float = 3.05

## Tras un golpe, no recibe daño durante este tiempo (i-frames).
@export var damage_invulnerability_duration: float = 2.0
## Mitad de un ciclo titilar: opacidad plena ↔ baja (valores menores = titila más rápido).
@export var damage_invuln_blink_half_period: float = 0.1
## Opacidad en la fase “apagada” (p. ej. 0.2 = ~20 % visible).
@export_range(0.0, 1.0, 0.05) var damage_invuln_blink_alpha_low: float = 0.2

var transition_locked: bool = false
var _damage_knockback: Vector2 = Vector2.ZERO
var _damage_hit_flash_tween: Tween
var _damage_hit_flash_intensity: float = 0.0
var _invuln_remaining: float = 0.0
var _invuln_blink_accum: float = 0.0
var _invuln_blink_visible: bool = true

## Última dirección de movimiento (normalizada); define qué idle mostrar al parar.
var _last_facing_dir: Vector2 = Vector2.RIGHT

const _ANIM_IDLE_SIDEWAYS := &"idle_sideways"
const _ANIM_IDLE_UP := &"idle_up"
const _ANIM_IDLE_DOWN := &"idle_down"
const _ANIM_RUN_SIDEWAYS := &"run_sideways"
const _ANIM_RUN_UP := &"run_up"
const _ANIM_RUN_DOWN := &"run_down"

const _ANIM_ATTACK_SIDEWAYS := &"attack_sideways"
const _ANIM_ATTACK_UP := &"attack_up"
const _ANIM_ATTACK_DOWN := &"attack_down"

const _ANIM_ROLL_SIDEWAYS := &"roll_sideways"
const _ANIM_ROLL_UP := &"roll_up"
const _ANIM_ROLL_DOWN := &"roll_down"

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _attacking: bool = false
var _rolling: bool = false

## Referencia al nodo de swing actual; mientras exista, no hay otro VFX de ataque.
var _active_swing: Node2D = null

## === Dash / Voltereta (J) ===
@export var dash_distance: float = 72.0
@export var dash_duration: float = 0.40
@export var dash_cooldown: float = 0.5

var _dash_time_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _j_was_pressed: bool = false

const _SPRITE_OFFSET_X: float = 12.0
var _sprite_offset_y: float = 0.0

func _ready() -> void:
	# Evita lógica de suelo/slop; ideal para vista cenital.
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("player")
	_sprite_offset_y = _sprite.offset.y
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.play(_ANIM_IDLE_SIDEWAYS)
	_update_sprite_offset(true, false)
	_sprite.animation_finished.connect(_on_attack_finished)


func _physics_process(delta: float) -> void:
	_tick_damage_invulnerability(delta)
	if transition_locked:
		_damage_knockback = Vector2.ZERO
		velocity = Vector2.ZERO
		_apply_sprite_flip_idle()
		_sync_animation(false, Vector2.ZERO)
		return

	_tick_dash(delta)

	if _dash_time_remaining > 0.0:
		velocity = _dash_velocity + _damage_knockback
		move_and_slide()
		_decay_damage_knockback(delta)
		return

	# Roll (J / dash): puede cancelar el clip de ataque (igual que en skai: MELEE_SWING → voltereta).
	var j_pressed := Input.is_key_pressed(KEY_J)
	var dash_just := (
		(Input.is_action_just_pressed("dash") if InputMap.has_action("dash") else false)
		or (j_pressed and not _j_was_pressed)
	)
	_j_was_pressed = j_pressed
	if dash_just:
		_try_dash()
	if _dash_time_remaining > 0.0:
		velocity = _dash_velocity + _damage_knockback
		move_and_slide()
		_decay_damage_knockback(delta)
		return

	if _attacking:
		velocity = _damage_knockback
		move_and_slide()
		_decay_damage_knockback(delta)
		return

	if Input.is_action_just_pressed("ui_accept"):
		_try_attack()
		return
	var direction := _get_move_direction()
	var moving := direction.length_squared() > 0.0
	if moving:
		direction = direction.normalized()
		_last_facing_dir = direction
	velocity = direction * speed + _damage_knockback
	if moving:
		var run_anim := _run_anim_for_direction(direction)
		if run_anim == _ANIM_RUN_SIDEWAYS and direction.x != 0.0:
			_sprite.flip_h = direction.x < 0.0
			_update_sprite_offset(true, _sprite.flip_h)
		elif run_anim == _ANIM_RUN_UP or run_anim == _ANIM_RUN_DOWN:
			_sprite.flip_h = false
			_update_sprite_offset(false)
	else:
		_apply_sprite_flip_idle()
	move_and_slide()
	_decay_damage_knockback(delta)
	_sync_animation(moving, direction)


func _run_anim_for_direction(dir: Vector2) -> StringName:
	if absf(dir.y) > absf(dir.x):
		return _ANIM_RUN_UP if dir.y < 0.0 else _ANIM_RUN_DOWN
	return _ANIM_RUN_SIDEWAYS


func _idle_anim_for_direction(dir: Vector2) -> StringName:
	if absf(dir.y) > absf(dir.x):
		return _ANIM_IDLE_UP if dir.y < 0.0 else _ANIM_IDLE_DOWN
	return _ANIM_IDLE_SIDEWAYS


func _update_sprite_offset(sideways: bool, flip_h: bool = false) -> void:
	var offset_x := _SPRITE_OFFSET_X
	if sideways:
		offset_x = -_SPRITE_OFFSET_X if flip_h else _SPRITE_OFFSET_X
	_sprite.offset = Vector2(offset_x, _sprite_offset_y)


func _apply_sprite_flip_idle() -> void:
	if _rolling or _attacking:
		return
	var idle_anim := _idle_anim_for_direction(_last_facing_dir)
	if idle_anim == _ANIM_IDLE_SIDEWAYS:
		if _last_facing_dir.x != 0.0:
			_sprite.flip_h = _last_facing_dir.x < 0.0
		_update_sprite_offset(true, _sprite.flip_h)
	else:
		_sprite.flip_h = false
		_update_sprite_offset(false)


func _sync_animation(moving: bool, direction: Vector2) -> void:
	if _rolling or _attacking:
		return
	var desired: StringName
	if moving:
		desired = _run_anim_for_direction(direction)
	else:
		desired = _idle_anim_for_direction(_last_facing_dir)
	if _sprite.animation != desired:
		_sprite.play(desired)


func is_damage_invulnerable() -> bool:
	return _invuln_remaining > 0.001


func take_damage(amount: float, from_direction: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0:
		return
	if is_damage_invulnerable():
		return
	var kb: Vector2 = from_direction
	if kb.length_squared() < 0.0001:
		if _last_facing_dir.length_squared() > 0.0001:
			kb = -_last_facing_dir
		else:
			kb = Vector2.RIGHT
	var away: Vector2 = kb.normalized()
	_damage_knockback += away * damage_knockback_peak
	var cap: float = maxf(damage_knockback_max_speed, 0.0)
	if cap > 0.0 and _damage_knockback.length() > cap:
		_damage_knockback = _damage_knockback.normalized() * cap
	if _attacking:
		_cancel_attack_for_roll()
		_sync_animation(false, Vector2.ZERO)
	get_tree().call_group("game_camera", "shake_on_player_hit")
	get_tree().call_group("player_hud", "flash_damage_vignette")
	_play_damage_hit_flash()
	_invuln_remaining = maxf(damage_invulnerability_duration, 0.0)
	_invuln_blink_accum = 0.0
	_invuln_blink_visible = true
	_update_damage_invulnerability_visual()


func _tick_damage_invulnerability(delta: float) -> void:
	if _sprite == null:
		return
	if _invuln_remaining > 0.0:
		_invuln_remaining = maxf(_invuln_remaining - delta, 0.0)
		_invuln_blink_accum += delta
		var half: float = maxf(damage_invuln_blink_half_period, 0.04)
		while _invuln_blink_accum >= half:
			_invuln_blink_accum -= half
			_invuln_blink_visible = not _invuln_blink_visible
		_update_damage_invulnerability_visual()
	else:
		_invuln_blink_accum = 0.0
		_invuln_blink_visible = true
		_update_damage_invulnerability_visual()


func _update_damage_invulnerability_visual() -> void:
	if _sprite == null:
		return
	if _invuln_remaining <= 0.0:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	var a: float = 1.0 if _invuln_blink_visible else damage_invuln_blink_alpha_low
	_sprite.modulate = Color(1.0, 1.0, 1.0, a)


func _play_damage_hit_flash() -> void:
	if _sprite == null:
		return
	if _damage_hit_flash_tween != null and _damage_hit_flash_tween.is_valid():
		_damage_hit_flash_tween.kill()
	_set_damage_hit_flash_intensity(1.0)
	_damage_hit_flash_tween = create_tween()
	_damage_hit_flash_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_damage_hit_flash_tween.tween_method(
		_set_damage_hit_flash_intensity,
		1.0,
		0.0,
		maxf(damage_hit_flash_duration, 0.04)
	)


func _set_damage_hit_flash_intensity(v: float) -> void:
	_damage_hit_flash_intensity = v
	_apply_damage_hit_sprite_modulate()


func _apply_damage_hit_sprite_modulate() -> void:
	if _sprite == null:
		return
	if _damage_hit_flash_intensity > 0.001:
		var i: float = clampf(_damage_hit_flash_intensity, 0.0, 1.0)
		var m: float = lerpf(1.0, damage_hit_flash_hdr_peak, i)
		_sprite.self_modulate = Color(m, m, m, 1.0)
		return
	_sprite.self_modulate = Color.WHITE


func _decay_damage_knockback(delta: float) -> void:
	_damage_knockback = _damage_knockback.lerp(
		Vector2.ZERO,
		1.0 - exp(-damage_knockback_decay * delta)
	)


func _get_move_direction() -> Vector2:
	var dir := Vector2.ZERO
	if (
		Input.is_action_pressed("ui_left")
		or Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_LEFT)
	):
		dir.x -= 1.0
	if (
		Input.is_action_pressed("ui_right")
		or Input.is_physical_key_pressed(KEY_D)
		or Input.is_physical_key_pressed(KEY_RIGHT)
	):
		dir.x += 1.0
	if (
		Input.is_action_pressed("ui_up")
		or Input.is_physical_key_pressed(KEY_W)
		or Input.is_physical_key_pressed(KEY_UP)
	):
		dir.y -= 1.0
	if (
		Input.is_action_pressed("ui_down")
		or Input.is_physical_key_pressed(KEY_S)
		or Input.is_physical_key_pressed(KEY_DOWN)
	):
		dir.y += 1.0
	return dir


func _try_attack() -> void:
	if _attacking:
		return
	var anim := _attack_anim_for_direction(_last_facing_dir)
	if anim.is_empty():
		return
	_attacking = true
	var sideways := absf(_last_facing_dir.y) <= absf(_last_facing_dir.x)
	if sideways and _last_facing_dir.x != 0.0:
		_sprite.flip_h = _last_facing_dir.x < 0.0
		_update_sprite_offset(true, _sprite.flip_h)
	else:
		_sprite.flip_h = false
		_update_sprite_offset(false)
	_sprite.play(anim)
	_spawn_swing()


func _spawn_swing() -> void:
	if swing_scene == null:
		return
	if is_instance_valid(_active_swing):
		return
	var swing: Node2D = swing_scene.instantiate() as Node2D
	if swing == null:
		return
	_active_swing = swing
	swing.tree_exited.connect(_on_swing_tree_exited, CONNECT_ONE_SHOT)
	var parent := get_parent()
	if parent != null:
		parent.add_child(swing)
	else:
		add_sibling(swing)
	swing.global_position = global_position
	var angle: float = _last_facing_dir.angle()
	if swing.has_method("setup"):
		swing.call(
			"setup",
			null,                          # target (no hay selección de enemigo)
			angle,
			-1.0,                          # reach_px (no usado)
			1,                             # swing_mode = ENEMY
			attack_range,
			global_position,
			1.0,                           # damage_multiplier
			false                          # empowered
		)


func _on_swing_tree_exited() -> void:
	_active_swing = null


func _attack_anim_for_direction(dir: Vector2) -> StringName:
	if absf(dir.y) > absf(dir.x):
		return _ANIM_ATTACK_DOWN if dir.y > 0.0 else _ANIM_ATTACK_UP
	return _ANIM_ATTACK_SIDEWAYS


func _on_attack_finished() -> void:
	if not _attacking:
		return
	_attacking = false
	_sync_animation(false, Vector2.ZERO)


func _roll_anim_for_direction(dir: Vector2) -> StringName:
	if absf(dir.y) > absf(dir.x):
		return _ANIM_ROLL_DOWN if dir.y > 0.0 else _ANIM_ROLL_UP
	return _ANIM_ROLL_SIDEWAYS


func _cancel_attack_for_roll() -> void:
	if not _attacking:
		return
	_attacking = false


func _try_dash() -> void:
	if _dash_cooldown_remaining > 0.0:
		return
	if _attacking:
		_cancel_attack_for_roll()
	var dir := _get_move_direction()
	if dir.length_squared() < 0.0001:
		dir = _last_facing_dir
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	_rolling = true
	var anim := _roll_anim_for_direction(dir)
	var sideways := absf(dir.y) <= absf(dir.x)
	if sideways and dir.x != 0.0:
		_sprite.flip_h = dir.x < 0.0
		_update_sprite_offset(true, _sprite.flip_h)
	else:
		_sprite.flip_h = false
		_update_sprite_offset(false)
	_sprite.play(anim)
	_dash_time_remaining = dash_duration
	_dash_cooldown_remaining = dash_cooldown
	_dash_velocity = dir * (dash_distance / maxf(dash_duration, 0.0001))


func _tick_dash(delta: float) -> void:
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = maxf(_dash_time_remaining - delta, 0.0)
		if _dash_time_remaining <= 0.0:
			_rolling = false
			_dash_velocity = Vector2.ZERO
			_sync_animation(false, Vector2.ZERO)
	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)
