extends Node2D

## Máscara de salidas abiertas: N=1, S=2, E=4, W=8 (puertas cerradas = resto; overlay + sin transición).
@export var open_exits: int = 15
## 1 o 2: conjuntos distintos de props en [Decoration] (tileset Swamp, source 7).
@export_range(1, 2) var decor_variant: int = 1
## Sal distinta por escena .tscn para variar la decoración exterior (0 = solo hash de la ruta).
@export_range(0, 2147483647) var exterior_deco_salt: int = 0

const _EXIT_N := 1
const _EXIT_S := 2
const _EXIT_E := 4
const _EXIT_W := 8
## [room_base] MainRoomLayout / Swamp Tileset.png (source 7).
const _SWAMP_SOURCE := 7
## Celda vacía en [TileMapLayer] (get_cell_source_id devuelve -1).
const _TILE_SOURCE_EMPTY := -1
## Origen atlas en Swamp Tileset.png (rejilla del atlas) permitidos para props fuera del [MainRoomLayout].
const _SWAMP_EXTERIOR_ATLAS: Array[Vector2i] = [
	Vector2i(0, 8), Vector2i(0, 9), Vector2i(4, 9), Vector2i(4, 8),
	Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 11),
	Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11),
	Vector2i(6, 12), Vector2i(1, 5), Vector2i(3, 5), Vector2i(4, 5),
	Vector2i(5, 4), Vector2i(7, 4), Vector2i(5, 3), Vector2i(6, 3), Vector2i(0, 6),
]
## Tamaño en celdas del mapa (coincide con size_in_atlas del TileSet) para no pisar tiles vecinos.
const _SWAMP_EXTERIOR_ATLAS_FOOTPRINT: Dictionary = {
	Vector2i(0, 8): Vector2i(2, 1),
	Vector2i(0, 9): Vector2i(2, 2),
	Vector2i(4, 9): Vector2i(2, 2),
	Vector2i(4, 8): Vector2i(2, 1),
	Vector2i(6, 12): Vector2i(2, 1),
	Vector2i(1, 5): Vector2i(2, 2),
	Vector2i(3, 5): Vector2i(1, 2),
	Vector2i(4, 5): Vector2i(1, 2),
	Vector2i(5, 4): Vector2i(2, 1),
}

## Área en espacio local (sin escala del Game) donde puede aparecer un enemigo; encaja con [room_base] y variantes.
@export var enemy_spawn_rect: Rect2 = Rect2(-70, -52, 148, 100)

@onready var _spawn_north: Marker2D = $SpawnNorth
@onready var _spawn_south: Marker2D = $SpawnSouth
@onready var _spawn_east: Marker2D = $SpawnEast
@onready var _spawn_west: Marker2D = $SpawnWest


func _ready() -> void:
	_apply_exit_doors()
	_apply_decor_variant()
	_erase_tiles_beyond_blocked_doors()
	var tube := get_node_or_null("Tube") as TileMapLayer
	if tube != null and Dungeon.is_start_room_hub():
		tube.visible = false
		tube.collision_enabled = false
	## Un frame después: evita un frame raro al instanciar la sala en transición (props encima del suelo).
	call_deferred("_paint_exterior_swamp_decoration")


func _apply_exit_doors() -> void:
	var doors_sprites := get_node_or_null("DoorsSprites") as TileMapLayer
	if doors_sprites != null:
		doors_sprites.clear()
	if (open_exits & _EXIT_N) == 0:
		_close_door_area($Doors/TopDoor as Area2D)
		_paint_swamp_wall_cap(doors_sprites, Vector2i(0, -8), Vector2i(4, 0))
	if (open_exits & _EXIT_S) == 0:
		_close_door_area($Doors/BottomDoor as Area2D)
		_paint_swamp_wall_cap(doors_sprites, Vector2i(0, 6), Vector2i(4, 2))
	if (open_exits & _EXIT_W) == 0:
		_close_door_area($Doors/LeftDoor as Area2D)
		_paint_swamp_wall_cap(doors_sprites, Vector2i(-13, -1), Vector2i(3, 1))
	if (open_exits & _EXIT_E) == 0:
		_close_door_area($Doors/RightDoor as Area2D)
		_paint_swamp_wall_cap(doors_sprites, Vector2i(13, -1), Vector2i(5, 1))


func _close_door_area(area: Area2D) -> void:
	area.monitoring = false
	area.monitorable = false
	var cs := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.disabled = true


func _paint_swamp_wall_cap(layer: TileMapLayer, cell: Vector2i, atlas: Vector2i) -> void:
	if layer == null or layer.tile_set == null:
		return
	layer.set_cell(cell, _SWAMP_SOURCE, atlas)


## Quita tiles en el pasillo exterior (misma celda en suelo / decoración / tubo) para que no se vea nada tras el tapón.
func _erase_cell_beyond_door(cell: Vector2i) -> void:
	for path: String in ["MainRoomLayout", "Decoration", "Tube"]:
		var layer := get_node_or_null(path) as TileMapLayer
		if layer == null:
			continue
		layer.erase_cell(cell)


func _erase_tiles_beyond_blocked_doors() -> void:
	if (open_exits & _EXIT_N) == 0:
		_erase_cell_beyond_door(Vector2i(0, -9))
	if (open_exits & _EXIT_S) == 0:
		_erase_cell_beyond_door(Vector2i(0, 7))
	if (open_exits & _EXIT_W) == 0:
		_erase_cell_beyond_door(Vector2i(-14, -1))
	if (open_exits & _EXIT_E) == 0:
		_erase_cell_beyond_door(Vector2i(14, -1))


func _apply_decor_variant() -> void:
	var deco := get_node_or_null("Decoration") as TileMapLayer
	if deco == null or deco.tile_set == null:
		return
	if decor_variant == 1:
		deco.set_cell(Vector2i(-5, -2), _SWAMP_SOURCE, Vector2i(2, 10))
		deco.set_cell(Vector2i(5, 2), _SWAMP_SOURCE, Vector2i(3, 10))
		deco.set_cell(Vector2i(-6, 3), _SWAMP_SOURCE, Vector2i(6, 9))
	elif decor_variant == 2:
		deco.set_cell(Vector2i(-5, 2), _SWAMP_SOURCE, Vector2i(2, 11))
		deco.set_cell(Vector2i(5, -2), _SWAMP_SOURCE, Vector2i(3, 11))
		deco.set_cell(Vector2i(6, -3), _SWAMP_SOURCE, Vector2i(7, 9))


## Props solo fuera del AABB de [MainRoomLayout]: celdas sin tile en suelo/puertas y totalmente fuera del rect usado.
func _paint_exterior_swamp_decoration() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var deco := get_node_or_null("Decoration") as TileMapLayer
	var main := get_node_or_null("MainRoomLayout") as TileMapLayer
	var doors := get_node_or_null("DoorsSprites") as TileMapLayer
	if deco == null or main == null or deco.tile_set == null:
		return
	var main_rect := main.get_used_rect()
	if main_rect.size == Vector2i.ZERO:
		return
	var rng := RandomNumberGenerator.new()
	var path_hash := int(hash(get_scene_file_path()))
	var salt := exterior_deco_salt if exterior_deco_salt != 0 else path_hash
	rng.seed = int(salt) ^ (decor_variant * 0x9E3779B9) ^ (open_exits * 0x517CC1B7) ^ (path_hash * 0x85EBCA6B)
	var margin := 5
	var bounds := main_rect.grow(margin)
	var candidates: Array[Vector2i] = []
	var y0 := bounds.position.y
	var x0 := bounds.position.x
	var y1 := bounds.position.y + bounds.size.y
	var x1 := bounds.position.x + bounds.size.x
	for y in range(y0, y1):
		for x in range(x0, x1):
			var anchor := Vector2i(x, y)
			if _swamp_exterior_anchor_in_ring(anchor, main_rect):
				candidates.append(anchor)
	if candidates.is_empty():
		return
	_shuffle_vector2i_array(candidates, rng)
	var occupied: Dictionary = {}
	_init_occupied_from_layer(deco, occupied)
	var max_places := 7 + _popcount32(open_exits) * 4
	var placed := 0
	for anchor: Vector2i in candidates:
		if placed >= max_places:
			break
		if occupied.has(anchor):
			continue
		var atlas: Vector2i = _SWAMP_EXTERIOR_ATLAS[rng.randi() % _SWAMP_EXTERIOR_ATLAS.size()]
		var fp: Vector2i = _swamp_exterior_footprint(atlas)
		if not _swamp_exterior_can_place(
			anchor, fp, main_rect, main, doors, deco, occupied
		):
			continue
		deco.set_cell(anchor, _SWAMP_SOURCE, atlas)
		for dy in range(fp.y):
			for dx in range(fp.x):
				occupied[anchor + Vector2i(dx, dy)] = true
		placed += 1


func _swamp_exterior_footprint(atlas: Vector2i) -> Vector2i:
	if _SWAMP_EXTERIOR_ATLAS_FOOTPRINT.has(atlas):
		return _SWAMP_EXTERIOR_ATLAS_FOOTPRINT[atlas] as Vector2i
	return Vector2i(1, 1)


func _swamp_exterior_anchor_in_ring(anchor: Vector2i, main_rect: Rect2i) -> bool:
	## Esquina superior-izquierda de un tile 1x1 fuera del rect del suelo (borde exterior del room).
	var c := anchor
	if main_rect.has_point(c):
		return false
	return true


func _swamp_exterior_can_place(
	anchor: Vector2i,
	fp: Vector2i,
	main_rect: Rect2i,
	main: TileMapLayer,
	doors: TileMapLayer,
	deco: TileMapLayer,
	occupied: Dictionary
) -> bool:
	for dy in range(fp.y):
		for dx in range(fp.x):
			var c := anchor + Vector2i(dx, dy)
			if main_rect.has_point(c):
				return false
			if main.get_cell_source_id(c) != _TILE_SOURCE_EMPTY:
				return false
			if doors != null and doors.get_cell_source_id(c) != _TILE_SOURCE_EMPTY:
				return false
			if deco.get_cell_source_id(c) != _TILE_SOURCE_EMPTY and not occupied.has(c):
				return false
			if occupied.has(c):
				return false
	return true


func _init_occupied_from_layer(layer: TileMapLayer, occupied: Dictionary) -> void:
	for c: Vector2i in layer.get_used_cells():
		occupied[c] = true


func _shuffle_vector2i_array(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Vector2i = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _popcount32(x: int) -> int:
	var n := 0
	var v := x
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## Posición global del spawn: exactamente el [Marker2D] del lado de entrada ([Game] la aplica al cargar / transición).
func get_spawn_global_position(entry: RoomTransition.EntrySide) -> Vector2:
	var marker := _marker_for_entry(entry)
	if marker == null:
		return global_position
	return marker.global_position


func _marker_for_entry(entry: RoomTransition.EntrySide) -> Marker2D:
	match entry:
		RoomTransition.EntrySide.NORTH:
			return _spawn_north
		RoomTransition.EntrySide.SOUTH:
			return _spawn_south
		RoomTransition.EntrySide.EAST:
			return _spawn_east
		RoomTransition.EntrySide.WEST:
			return _spawn_west
		_:
			return null


## Punto local aleatorio dentro de [enemy_spawn_rect] que queda al menos [min_dist_global] del jugador (global).
## Si [avoid_global] no está vacío, también exige [min_dist_avoid_global] respecto a cada punto (otros enemigos).
func pick_enemy_spawn_local(
	rng: RandomNumberGenerator,
	player_global: Vector2,
	min_dist_global: float,
	max_attempts: int = 48,
	avoid_global: Array[Vector2] = [],
	min_dist_avoid_global: float = 0.0
) -> Vector2:
	var r := enemy_spawn_rect
	var best: Vector2 = r.get_center()
	var best_score: float = -1.0
	for _i in max_attempts:
		var local_pt := Vector2(
			rng.randf_range(r.position.x, r.position.x + r.size.x),
			rng.randf_range(r.position.y, r.position.y + r.size.y)
		)
		var g := to_global(local_pt)
		if g.distance_to(player_global) < min_dist_global:
			continue
		var ok := true
		if min_dist_avoid_global > 0.0 and not avoid_global.is_empty():
			for p in avoid_global:
				if g.distance_to(p) < min_dist_avoid_global:
					ok = false
					break
		if ok:
			return local_pt
		## Puntuación = mínima distancia a jugador y a exclusiones; sirve de fallback si no hay hueco perfecto.
		var d_player: float = g.distance_to(player_global)
		var score: float = d_player
		if not avoid_global.is_empty():
			var d_avoid: float = 1.0e12
			for p in avoid_global:
				d_avoid = minf(d_avoid, g.distance_to(p))
			score = minf(d_player, d_avoid)
		if score > best_score:
			best_score = score
			best = local_pt
	return best
