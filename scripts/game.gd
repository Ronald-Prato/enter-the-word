extends Node2D

const ROOM_NODE_NAME := "Room"
## No usar get_node("Room"): al hacer queue_free la sala vieja sigue un frame con el mismo nombre y el nombre duplicado rompe la siguiente transición.
const GROUP_CURRENT_ROOM := "current_room"
const ROOM_POSITION := Vector2(-8, 7)
## Escala visual y de colisión de la sala; la rejilla lógica del dungeon no cambia.
const ROOM_SCALE := 2.0

const MOSQUITO_SCENE := preload("res://scenes/mosquito_enemy.tscn")
## Distancia mínima jugador–enemigo al spawnear (espacio global, con escala de sala aplicada).
const ENEMY_MIN_PLAYER_DISTANCE_GLOBAL := 80.0
## Separación mínima entre enemigos al spawnear (global); evita que aparezcan amontonados.
const ENEMY_MIN_SEPARATION_GLOBAL := 90.0
const MAX_CONCURRENT_MOSQUITOES := 3
## Tras entrar en sala con enemigos: espera antes del primer mosquito.
const INITIAL_ENEMY_SPAWN_DELAY_S := 0.85
## Tiempo aleatorio entre cada uno de los mosquitos iniciales (no el mismo instante).
const INITIAL_ENEMY_STAGGER_MIN_S := 0.62
const INITIAL_ENEMY_STAGGER_MAX_S := 1.05
## Bajas del jugador en la sala para salir del combat mode (cámara amplia + minimapa).
const COMBAT_KILLS_TO_CLEAR := 3

## `mosquito_death_scraps.tscn` usa z_index=1: debe quedar entre suelo (TileMap ≤ 0) y el jugador (≥ Z_PLAYER_DEFAULT).
## Capas tipo Decoration4 / overrides en salas pueden llegar a z_index relativo 4; el jugador “detrás” del enemigo debe seguir > eso y < Z_ENEMY.
const Z_ENEMY := 6
const Z_PLAYER_DEFAULT := 5
const Z_PLAYER_IN_FRONT := 10

@export var room_transition_duration: float = 0.22
@export var combat_minimap_fade_out_s: float = 0.28
@export var combat_minimap_fade_in_s: float = 0.38

@onready var _camera: Camera2D = $Camera2D
@onready var _minimap_draw: Control = $CanvasLayer/MinimapRoot/MinimapDraw
@onready var _minimap_root: CanvasItem = $CanvasLayer/MinimapRoot
@onready var _player: CharacterBody2D = $Player

var _transitioning: bool = false
var _combat_active: bool = false
## Tras 3 kills en la sala: sin respawn de mosquitos y cámara en vista de sala.
var _room_combat_finished: bool = false
var _kills_this_room: int = 0
var _minimap_fade_tween: Tween
var _enemy_spawn_rng := RandomNumberGenerator.new()
## Mosquitos iniciales de la sala: se reparten en el tiempo (no todos en un frame).
var _room_initial_spawns_left: int = 0
var _room_initial_spawn_timer: float = 0.0


func _ready() -> void:
	add_to_group("game")
	_enemy_spawn_rng.randomize()
	Dungeon.ensure_generated()
	_spawn_room()


# --------------- room spawning ---------------

func _spawn_room() -> void:
	var path: String = RoomTransition.peek_pending_room_path()
	var room_scene := load(path) as PackedScene
	if room_scene == null:
		push_error("Invalid room path: %s" % path)
		return
	path = RoomTransition.take_pending_room_path()
	var room_id: int = RoomTransition.take_pending_room_id()
	if Dungeon.use_generated():
		Dungeon.current_room_id = room_id
		Dungeon.reveal_minimap_from_current_room()
		Dungeon.mark_room_entered(room_id)
	if _minimap_draw != null:
		_minimap_draw.sync_from_dungeon()
	var room := room_scene.instantiate() as Node2D
	room.name = ROOM_NODE_NAME
	room.position = ROOM_POSITION
	room.scale = Vector2(ROOM_SCALE, ROOM_SCALE)
	room.add_to_group(GROUP_CURRENT_ROOM)
	add_child(room)
	move_child(room, 0)
	_apply_player_entry_from_room(room)
	_spawn_enemy_for_room_if_needed(room)
	_restore_scraps_for_room(room, room_id)


func _restore_scraps_for_room(room: Node2D, room_id: int) -> void:
	if not Dungeon.use_generated():
		return
	var scraps_data: Array = Dungeon.get_room_scraps(room_id)
	for sd in scraps_data:
		var scraps := load("res://scenes/mosquito_death_scraps.tscn").instantiate() as Node2D
		if scraps == null:
			continue
		room.add_child(scraps)
		scraps.position = sd.get("position", Vector2.ZERO)
		if scraps.has_method("setup"):
			scraps.call("setup", room.to_global(scraps.position), sd["colors"], sd["offsets"])


# --------------- depth sorting ---------------

func _physics_process(_delta: float) -> void:
	_update_player_depth()


func _process(delta: float) -> void:
	if _transitioning or not Dungeon.use_generated() or Dungeon.current_room_id == 0:
		_room_initial_spawns_left = 0
		_room_initial_spawn_timer = 0.0
		return
	if _room_combat_finished:
		_room_initial_spawns_left = 0
		_room_initial_spawn_timer = 0.0
		return
	if _room_initial_spawns_left > 0:
		_room_initial_spawn_timer -= delta
		if _room_initial_spawn_timer <= 0.0:
			if _spawn_single_mosquito():
				_room_initial_spawns_left -= 1
				if _room_initial_spawns_left > 0:
					_room_initial_spawn_timer = _enemy_spawn_rng.randf_range(
						INITIAL_ENEMY_STAGGER_MIN_S, INITIAL_ENEMY_STAGGER_MAX_S
					)
				else:
					_room_initial_spawn_timer = 0.0
			else:
				## A tope de enemigos: reintentar en breve sin consumir la cola.
				_room_initial_spawn_timer = 0.18


func is_room_transitioning() -> bool:
	return _transitioning


func on_enemy_killed_by_player() -> void:
	if not _combat_active:
		return
	_kills_this_room += 1
	if _kills_this_room >= COMBAT_KILLS_TO_CLEAR:
		_finish_room_combat_objective()


## Si [require_enemies], solo entra en combate cuando ya hay al menos un enemigo (respawns / edge cases).
func _try_begin_combat_mode(require_enemies: bool = true) -> void:
	if not Dungeon.use_generated() or Dungeon.current_room_id == 0:
		return
	if require_enemies and _count_valid_mosquitoes() < 1:
		return
	if _combat_active:
		return
	_combat_active = true
	_room_combat_finished = false
	_kills_this_room = 0
	if _camera != null and _camera.has_method("enter_combat_view"):
		_camera.call("enter_combat_view")
	_tween_minimap_alpha(0.0, combat_minimap_fade_out_s)


func _finish_room_combat_objective() -> void:
	if not _combat_active:
		return
	_combat_active = false
	_room_combat_finished = true
	_room_initial_spawns_left = 0
	_room_initial_spawn_timer = 0.0
	if _camera != null and _camera.has_method("enter_room_showcase_view"):
		_camera.call("enter_room_showcase_view")
	_tween_minimap_alpha(1.0, combat_minimap_fade_in_s)


func _tween_minimap_alpha(alpha: float, duration: float) -> void:
	if _minimap_root == null:
		return
	if _minimap_fade_tween != null and _minimap_fade_tween.is_valid():
		_minimap_fade_tween.kill()
	if duration <= 0.0:
		var c0 := _minimap_root.modulate
		c0.a = clampf(alpha, 0.0, 1.0)
		_minimap_root.modulate = c0
		return
	_minimap_fade_tween = create_tween()
	_minimap_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_minimap_fade_tween.tween_property(_minimap_root, "modulate:a", clampf(alpha, 0.0, 1.0), duration)


func _reset_combat_state_for_room_travel() -> void:
	_combat_active = false
	_room_combat_finished = false
	_kills_this_room = 0
	_room_initial_spawns_left = 0
	_room_initial_spawn_timer = 0.0
	if _minimap_fade_tween != null and _minimap_fade_tween.is_valid():
		_minimap_fade_tween.kill()
		_minimap_fade_tween = null
	if _minimap_root != null:
		var c := _minimap_root.modulate
		c.a = 1.0
		_minimap_root.modulate = c
	if _camera != null and _camera.has_method("reset_to_default_follow"):
		_camera.call("reset_to_default_follow")


func _clear_enemies_from_game() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			n.queue_free()


func _update_player_depth() -> void:
	if _player == null:
		return
	var py := _player.global_position.y
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var has_enemy := false
	for e in enemies:
		if is_instance_valid(e):
			has_enemy = true
			break
	if not has_enemy:
		_player.z_as_relative = false
		_player.z_index = Z_PLAYER_DEFAULT
		return
	var in_front := true
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var ey_line: float
		if enemy.has_method("get_depth_sort_global_y"):
			ey_line = enemy.get_depth_sort_global_y()
		else:
			ey_line = enemy.global_position.y
		if py < ey_line:
			in_front = false
			break
	_player.z_as_relative = false
	_player.z_index = Z_PLAYER_IN_FRONT if in_front else Z_PLAYER_DEFAULT


# --------------- room transitions ---------------

func begin_room_transition(exit_side: RoomTransition.ExitSide) -> void:
	if _transitioning:
		return
	_reset_combat_state_for_room_travel()
	_clear_enemies_from_game()
	_room_initial_spawns_left = 0
	_room_initial_spawn_timer = 0.0
	var old_room := get_tree().get_first_node_in_group(GROUP_CURRENT_ROOM) as Node2D
	if old_room == null:
		push_error("begin_room_transition: no hay sala actual.")
		return
	var room_path: String = RoomTransition.peek_pending_room_path()
	var room_scene := load(room_path) as PackedScene
	if room_scene == null:
		push_error("Invalid room path: %s" % room_path)
		return
	room_path = RoomTransition.take_pending_room_path()
	var room_id := RoomTransition.take_pending_room_id()
	if Dungeon.use_generated():
		var prev_room_id := Dungeon.current_room_id
		Dungeon.current_room_id = room_id
		Dungeon.reveal_minimap_from_current_room()
		Dungeon.mark_room_entered(room_id)
		if _minimap_draw != null:
			_minimap_draw.animate_grid_transition(prev_room_id, room_id, room_transition_duration)
	var slide_offset := _slide_offset_for_exit(exit_side)
	_transitioning = true
	if _player != null:
		_player.transition_locked = true
	var new_room := room_scene.instantiate() as Node2D
	new_room.name = "RoomNew"
	new_room.position = ROOM_POSITION - slide_offset
	new_room.scale = Vector2(ROOM_SCALE, ROOM_SCALE)
	add_child(new_room)
	move_child(new_room, 0)
	_restore_scraps_for_room(new_room, room_id)
	var old_end := old_room.position + slide_offset
	var player_end := _player.global_position + slide_offset if _player != null else Vector2.ZERO
	var tween := create_tween()
	tween.set_parallel(true)
	var trans := Tween.TRANS_CUBIC
	var ease_type := Tween.EASE_IN_OUT
	tween.tween_property(old_room, "position", old_end, room_transition_duration).set_trans(trans).set_ease(ease_type)
	tween.tween_property(new_room, "position", ROOM_POSITION, room_transition_duration).set_trans(trans).set_ease(ease_type)
	if _player != null:
		tween.tween_property(_player, "global_position", player_end, room_transition_duration).set_trans(trans).set_ease(ease_type)
	tween.finished.connect(_finish_room_transition.bind(old_room, new_room, _player))


func _finish_room_transition(old_room: Node2D, new_room: Node2D, player: CharacterBody2D) -> void:
	if is_instance_valid(old_room):
		old_room.remove_from_group(GROUP_CURRENT_ROOM)
		old_room.name = "_RoomLeaving"
		old_room.queue_free()
	if not is_instance_valid(new_room):
		if player != null and is_instance_valid(player):
			player.transition_locked = false
		_transitioning = false
		return
	new_room.name = ROOM_NODE_NAME
	new_room.position = ROOM_POSITION
	new_room.add_to_group(GROUP_CURRENT_ROOM)
	move_child(new_room, 0)
	var entry := RoomTransition.take_pending_entry()
	if entry != RoomTransition.EntrySide.NONE and player != null and is_instance_valid(player):
		if new_room.has_method("get_spawn_global_position"):
			player.global_position = new_room.get_spawn_global_position(entry)
			player.velocity = Vector2.ZERO
			player.move_and_slide()
	if player != null and is_instance_valid(player):
		player.transition_locked = false
	_transitioning = false
	_spawn_enemy_for_room_if_needed(new_room)


func _apply_player_entry_from_room(room: Node2D) -> void:
	var entry := RoomTransition.take_pending_entry()
	if entry == RoomTransition.EntrySide.NONE:
		return
	if _player == null:
		return
	if room.has_method("get_spawn_global_position"):
		_player.global_position = room.get_spawn_global_position(entry)
		_player.velocity = Vector2.ZERO
		_player.move_and_slide()


func _spawn_enemy_for_room_if_needed(room: Node2D) -> void:
	if not Dungeon.use_generated():
		return
	if Dungeon.current_room_id == 0:
		return
	if _player == null:
		return
	if not room.has_method("pick_enemy_spawn_local"):
		return
	_room_initial_spawns_left = MAX_CONCURRENT_MOSQUITOES
	_room_initial_spawn_timer = INITIAL_ENEMY_SPAWN_DELAY_S
	_try_begin_combat_mode(false)


func _count_valid_mosquitoes() -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			count += 1
	return count


func _spawn_single_mosquito(room: Node2D = null) -> bool:
	if room == null:
		room = get_tree().get_first_node_in_group(GROUP_CURRENT_ROOM) as Node2D
	if room == null or _player == null:
		return false
	if not room.has_method("pick_enemy_spawn_local"):
		return false
	if _count_valid_mosquitoes() >= MAX_CONCURRENT_MOSQUITOES:
		return false
	var avoid: Array[Vector2] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if n is Node2D:
			avoid.append((n as Node2D).global_position)
	var local_pt: Vector2 = room.pick_enemy_spawn_local(
		_enemy_spawn_rng,
		_player.global_position,
		ENEMY_MIN_PLAYER_DISTANCE_GLOBAL,
		80,
		avoid,
		ENEMY_MIN_SEPARATION_GLOBAL
	)
	var enemy := MOSQUITO_SCENE.instantiate() as Node2D
	if enemy == null:
		return false
	add_child(enemy)
	enemy.global_position = room.to_global(local_pt)
	enemy.z_as_relative = false
	enemy.z_index = Z_ENEMY
	if _player != null:
		move_child(enemy, _player.get_index() + 1)
	if enemy.has_method("play_spawn_fade_in"):
		enemy.call("play_spawn_fade_in")
	return true


func _visible_world_size() -> Vector2:
	var px := get_viewport().get_visible_rect().size
	return px / _camera.zoom


func _slide_offset_for_exit(exit_side: RoomTransition.ExitSide) -> Vector2:
	var vs := _visible_world_size()
	match exit_side:
		RoomTransition.ExitSide.NORTH:
			return Vector2(0.0, vs.y)
		RoomTransition.ExitSide.SOUTH:
			return Vector2(0.0, -vs.y)
		RoomTransition.ExitSide.EAST:
			return Vector2(-vs.x, 0.0)
		RoomTransition.ExitSide.WEST:
			return Vector2(vs.x, 0.0)
		_:
			return Vector2.ZERO
