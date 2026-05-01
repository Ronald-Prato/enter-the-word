extends TileMapLayer

## Atlas (coords en la rejilla del atlas de etw_doors_tileset): origen → destino.
const ATLAS_REPLACE := {
	Vector2i(1, 1): Vector2i(3, 1),
	Vector2i(1, 2): Vector2i(3, 2),
}

@export var toggle_on_enter: bool = false
@export var fade_duration: float = 0.2

var _animating: bool = false


func _ready() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			if _animating:
				return
			_replace_doors_animated()
			get_viewport().set_input_as_handled()


## Sustituye tiles cerrados por abiertos sin animación (p. ej. sala inicial).
func apply_open_doors_immediate() -> void:
	var doors_sid := _find_doors_source_id()
	if doors_sid < 0:
		return
	for cell: Vector2i in get_used_cells():
		var sid := get_cell_source_id(cell)
		if sid != doors_sid:
			continue
		var coords := get_cell_atlas_coords(cell)
		if not ATLAS_REPLACE.has(coords):
			continue
		set_cell(cell, sid, ATLAS_REPLACE[coords], get_cell_alternative_tile(cell))


func _replace_doors_animated() -> void:
	var doors_sid := _find_doors_source_id()
	if doors_sid < 0:
		return

	var cells_to_replace: Array[Dictionary] = []
	for cell: Vector2i in get_used_cells():
		var sid := get_cell_source_id(cell)
		if sid != doors_sid:
			continue
		var coords := get_cell_atlas_coords(cell)
		if not ATLAS_REPLACE.has(coords):
			continue
		cells_to_replace.append({
			"cell": cell,
			"sid": sid,
			"old_coords": coords,
			"new_coords": ATLAS_REPLACE[coords],
			"alt": get_cell_alternative_tile(cell),
		})

	if cells_to_replace.is_empty():
		return

	_animating = true

	var fade_layer := TileMapLayer.new()
	fade_layer.tile_set = tile_set
	fade_layer.position = Vector2.ZERO
	fade_layer.z_index = 1
	add_child(fade_layer)

	for info: Dictionary in cells_to_replace:
		fade_layer.set_cell(info["cell"], info["sid"], info["old_coords"], info["alt"])
		erase_cell(info["cell"])
		set_cell(info["cell"], info["sid"], info["new_coords"], info["alt"])

	var tween := create_tween()
	tween.tween_property(fade_layer, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(func() -> void:
		fade_layer.queue_free()
		_animating = false
	)


func _find_doors_source_id() -> int:
	var ts := tile_set
	if ts == null:
		return -1
	for i in ts.get_source_count():
		var sid: int = ts.get_source_id(i)
		var src: TileSetSource = ts.get_source(sid)
		if src is TileSetAtlasSource:
			var atlas := src as TileSetAtlasSource
			if atlas.texture != null and atlas.texture.resource_path.find("etw_doors_tileset") != -1:
				return sid
	return -1
