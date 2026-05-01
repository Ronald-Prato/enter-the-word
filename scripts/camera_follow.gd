extends Camera2D

## Sigue al [Player] del padre [Game] con zoom y límites al borde de la sala ([MainRoomLayout]).
## Grupo `game_camera` como en skai.
## Debe coincidir con [Game.GROUP_CURRENT_ROOM].
const _CURRENT_ROOM_GROUP := "current_room"

enum Mode { FOLLOW_NORMAL, FOLLOW_COMBAT, ROOM_SHOWCASE }

@export var zoom_level: float = 2.6
## Durante combat mode: zoom base * este valor (más alto = más cerca del jugador).
@export var combat_zoom_multiplier: float = 1.25
## Tras 3 bajas: zoom que encaja todo el rect de la sala en el viewport; el margen (menor que 1) deja un poco de aire alrededor.
@export_range(0.88, 1.0, 0.01) var showcase_fit_margin: float = 0.94
## Suavizado del paneo hacia el centro en vista “showcase” (sala completa).
@export var combat_follow_smoothness: float = 12.0
## Modo combate: tiempo aproximado de respuesta de la cámara (SmoothDamp; más alto = más retraso y curva menos lineal).
@export_range(0.08, 1.2, 0.02) var combat_follow_smooth_time: float = 0.52
## Modo combate: curva extra al inicio del arranque (0 = solo SmoothDamp). Aumenta el “ease in” al empezar a moverse.
@export_range(0.0, 1.0, 0.05) var combat_follow_ease_in_weight: float = 0.42
## Suavizado del zoom al cambiar de modo (normal y sala completa).
@export var zoom_smoothness: float = 10.0
## Suavizado del zoom al acercarse en modo combate (más bajo = llega al zoom combat más lento).
@export var combat_zoom_smoothness: float = 4.2
## Encoge el rectángulo de encaje para que, cerca de los muros, el jugador no quede centrado.
@export var edge_padding_world: float = 40.0
## En modo combate: margen interior a los bordes de la sala (más bajo = la cámara te sigue más hacia los muros, sin llegar al borde duro).
@export var combat_edge_padding_world: float = 1.0


const _SHAKE_COMBAT_IMPULSE: float = 7.5
const _SHAKE_COMBAT_DECAY: float = 11.0
const _SHAKE_RESOURCE_IMPULSE: float = 2.15
const _SHAKE_RESOURCE_DECAY: float = 16.0

var _shake_strength: float = 0.0
var _shake_decay: float = 16.0

var _mode: Mode = Mode.FOLLOW_NORMAL
var _target_zoom: float = 2.6
var _showcase_position: Vector2 = Vector2.ZERO
var _combat_follow_vel: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("game_camera")
	_target_zoom = zoom_level
	zoom = Vector2(zoom_level, zoom_level)
	make_current()
	_apply_follow_for_mode(true, 0.0)


func reset_to_default_follow() -> void:
	_mode = Mode.FOLLOW_NORMAL
	_target_zoom = zoom_level
	zoom = Vector2(_target_zoom, _target_zoom)
	_combat_follow_vel = Vector2.ZERO
	_apply_follow_for_mode(true, 0.0)


func enter_combat_view() -> void:
	_mode = Mode.FOLLOW_COMBAT
	_target_zoom = zoom_level * combat_zoom_multiplier
	_combat_follow_vel = Vector2.ZERO


func enter_room_showcase_view() -> void:
	_mode = Mode.ROOM_SHOWCASE
	_combat_follow_vel = Vector2.ZERO
	var b := _room_bounds_global()
	if b.size == Vector2.ZERO:
		_showcase_position = global_position
		_target_zoom = zoom_level
	else:
		_showcase_position = b.get_center()
		_target_zoom = _compute_zoom_to_fit_room_rect(b)


## Zoom uniforme Godot: mayor = más cerca. Para ver todo el rect [b] en pantalla hace falta z ≤ vp.x/w y z ≤ vp.y/h → el tope es el mínimo de ambos (con un margen).
func _compute_zoom_to_fit_room_rect(b: Rect2) -> float:
	var vp := get_viewport().get_visible_rect().size
	var rw := maxf(b.size.x, 1.0)
	var rh := maxf(b.size.y, 1.0)
	var m := clampf(showcase_fit_margin, 0.5, 1.0)
	var z_w: float = vp.x / rw
	var z_h: float = vp.y / rh
	return minf(z_w, z_h) * m


func shake_on_resource_hit() -> void:
	_shake_strength = maxf(_shake_strength, _SHAKE_RESOURCE_IMPULSE)
	_shake_decay = _SHAKE_RESOURCE_DECAY


func shake_on_enemy_hit() -> void:
	_shake_strength = maxf(_shake_strength, _SHAKE_COMBAT_IMPULSE)
	_shake_decay = _SHAKE_COMBAT_DECAY


func shake_on_player_hit() -> void:
	_shake_strength = maxf(_shake_strength, _SHAKE_COMBAT_IMPULSE)
	_shake_decay = _SHAKE_COMBAT_DECAY


func _physics_process(delta: float) -> void:
	var game := get_parent()
	if game != null and game.has_method("is_room_transitioning") and game.is_room_transitioning():
		_smooth_zoom(delta)
		_apply_shake(delta)
		return
	_smooth_zoom(delta)
	match _mode:
		Mode.FOLLOW_NORMAL:
			_follow_player_clamped(true, delta)
		Mode.FOLLOW_COMBAT:
			_follow_player_clamped(false, delta)
		Mode.ROOM_SHOWCASE:
			global_position = global_position.lerp(
				_showcase_position,
				1.0 - exp(-combat_follow_smoothness * delta)
			)
	_apply_shake(delta)


func _smooth_zoom(delta: float) -> void:
	var smooth := zoom_smoothness
	if _mode == Mode.FOLLOW_COMBAT:
		smooth = maxf(combat_zoom_smoothness, 0.01)
	var z := lerpf(zoom.x, _target_zoom, 1.0 - exp(-smooth * delta))
	zoom = Vector2(z, z)


func _follow_player_clamped(instant: bool, delta: float) -> void:
	var game := get_parent()
	if game == null:
		return
	var player := game.get_node_or_null("Player") as Node2D
	if player == null:
		return
	var target := player.global_position
	var bounds := _room_bounds_global()
	var use_bounds := bounds.size != Vector2.ZERO
	var min_x: float = 0.0
	var max_x: float = 0.0
	var min_y: float = 0.0
	var max_y: float = 0.0
	var desired: Vector2
	if not use_bounds:
		desired = target
	else:
		var pad := maxf(edge_padding_world, 0.0)
		if _mode == Mode.FOLLOW_COMBAT:
			pad = maxf(combat_edge_padding_world, 0.0)
		var inner := bounds.grow(-pad)
		var half := _viewport_half_world()
		min_x = inner.position.x + half.x
		max_x = inner.position.x + inner.size.x - half.x
		min_y = inner.position.y + half.y
		max_y = inner.position.y + inner.size.y - half.y
		if min_x > max_x:
			var cx := inner.get_center().x
			min_x = cx
			max_x = cx
		if min_y > max_y:
			var cy := inner.get_center().y
			min_y = cy
			max_y = cy
		desired = Vector2(
			clampf(target.x, min_x, max_x),
			clampf(target.y, min_y, max_y)
		)
	if instant:
		global_position = desired
		_combat_follow_vel = Vector2.ZERO
	else:
		var new_pos := _smooth_damp_combat_follow(global_position, desired, delta)
		if use_bounds:
			new_pos.x = clampf(new_pos.x, min_x, max_x)
			new_pos.y = clampf(new_pos.y, min_y, max_y)
		global_position = new_pos


## Aproximación al SmoothDamp de Unity: arranque suave (ease in) y frenado al acercarse al objetivo.
func _smooth_damp_combat_follow(current: Vector2, target: Vector2, delta: float) -> Vector2:
	var st_base := maxf(combat_follow_smooth_time, 0.04)
	var err_len := (target - current).length()
	var w := clampf(combat_follow_ease_in_weight, 0.0, 1.0)
	## Con error grande, suavizado temporal más largo al inicio del movimiento (ease in más marcado).
	var st := st_base * lerpf(1.0, 1.85, w * clampf(err_len / 120.0, 0.0, 1.0))
	var omega := 2.0 / st
	var x := omega * delta
	var exp_x := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (_combat_follow_vel + omega * change) * delta
	_combat_follow_vel = (_combat_follow_vel - omega * temp) * exp_x
	return target + (change + temp) * exp_x


func _apply_follow_for_mode(instant: bool, delta: float) -> void:
	match _mode:
		Mode.FOLLOW_NORMAL, Mode.FOLLOW_COMBAT:
			_follow_player_clamped(instant, delta)
		Mode.ROOM_SHOWCASE:
			global_position = _showcase_position


func _viewport_half_world() -> Vector2:
	var px := get_viewport().get_visible_rect().size
	return Vector2(px.x / (2.0 * zoom.x), px.y / (2.0 * zoom.y))


func _room_bounds_global() -> Rect2:
	var room := get_tree().get_first_node_in_group(_CURRENT_ROOM_GROUP) as Node2D
	if room == null:
		return Rect2()
	var main := room.get_node_or_null("MainRoomLayout") as TileMapLayer
	if main == null or main.tile_set == null:
		return Rect2()
	var ur := main.get_used_rect()
	if ur.size == Vector2i.ZERO:
		return Rect2()
	var tsz := Vector2(main.tile_set.tile_size)
	var c1 := ur.position + ur.size - Vector2i(1, 1)
	var tl := main.to_global(main.map_to_local(ur.position))
	var br_origin := main.to_global(main.map_to_local(c1))
	var br := br_origin + tsz
	return Rect2(tl, br - tl)


func _apply_shake(delta: float) -> void:
	if _shake_strength > 0.02:
		_shake_strength = lerpf(_shake_strength, 0.0, 1.0 - exp(-_shake_decay * delta))
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	else:
		_shake_strength = 0.0
		offset = Vector2.ZERO
