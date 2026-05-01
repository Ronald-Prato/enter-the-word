extends Area2D

@export var exit_side: RoomTransition.ExitSide
@export_file("*.tscn") var next_room_path: String = "res://scenes/rooms/room_1.tscn"


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body is CharacterBody2D and (body as CharacterBody2D).transition_locked:
		return
	var path: String
	var next_id: int = -1
	if Dungeon.use_generated():
		path = Dungeon.get_next_room_path(exit_side)
		next_id = Dungeon.get_next_room_id(exit_side)
		if path.is_empty():
			return
	else:
		path = next_room_path
	RoomTransition.request_go_through_door(exit_side, path, next_id)
