extends Node

## NONE = primera carga o ya consumido; el resto = lado desde el que el jugador entra en la sala nueva.
enum EntrySide { NONE, NORTH, SOUTH, EAST, WEST }

## Lado por el que el jugador sale (puerta que toca).
enum ExitSide { NORTH, SOUTH, EAST, WEST }

const DEFAULT_ROOM_PATH := "res://scenes/rooms/4exit/NSEW_1.tscn"

var _pending_entry: EntrySide = EntrySide.NONE
var _pending_room_path: String = ""
var _pending_room_id: int = -1


func _opposite_exit(exit_side: ExitSide) -> EntrySide:
	match exit_side:
		ExitSide.NORTH:
			return EntrySide.SOUTH
		ExitSide.SOUTH:
			return EntrySide.NORTH
		ExitSide.EAST:
			return EntrySide.WEST
		ExitSide.WEST:
			return EntrySide.EAST
		_:
			return EntrySide.NONE


func request_go_through_door(exit_side: ExitSide, next_room_path: String, next_room_id: int = -1) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var game := tree.get_first_node_in_group("game")
	if game != null and game.has_method("is_room_transitioning") and game.is_room_transitioning():
		return
	var player := tree.get_first_node_in_group("player") as CharacterBody2D
	if player != null and player.transition_locked:
		return
	_pending_entry = _opposite_exit(exit_side)
	_pending_room_path = next_room_path
	_pending_room_id = next_room_id
	if game != null and game.has_method("begin_room_transition"):
		game.call("begin_room_transition", exit_side)
		return
	push_warning("RoomTransition: Game no encontrado; recargando escena.")
	tree.change_scene_to_file("res://scenes/game.tscn")


func take_pending_entry() -> EntrySide:
	var e := _pending_entry
	_pending_entry = EntrySide.NONE
	return e


func peek_pending_room_path() -> String:
	if not _pending_room_path.is_empty():
		return _pending_room_path
	if Dungeon.use_generated():
		return Dungeon.get_start_room_path()
	return DEFAULT_ROOM_PATH


func peek_pending_room_id() -> int:
	if _pending_room_id >= 0:
		return _pending_room_id
	if Dungeon.use_generated():
		return 0
	return -1


func take_pending_room_path() -> String:
	var p := _pending_room_path
	_pending_room_path = ""
	if p.is_empty():
		return peek_pending_room_path()
	return p


func take_pending_room_id() -> int:
	var id := _pending_room_id
	_pending_room_id = -1
	if id >= 0:
		return id
	return peek_pending_room_id()
