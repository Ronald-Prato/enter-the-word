extends Node

## Grafo procedural; sala 0 en cruz; cada brazo (1–4) tiene al menos 2 salas (hub + 5–8). Rejilla en _room_grid.

const MAX_ROOMS := 20
## Mínimo: 0 + 4 brazos + 1 sala extra obligatoria por brazo (ids 5–8) = 9.
const MIN_ROOMS := 9

const ROOMS_4_EXIT: Array[String] = [
	"res://scenes/rooms/4exit/NSEW_1.tscn",
	"res://scenes/rooms/4exit/NSEW_2.tscn",
]

const ROOMS_1_EXIT := {
	"N": ["res://scenes/rooms/1exit/N_1.tscn", "res://scenes/rooms/1exit/N_2.tscn"],
	"S": ["res://scenes/rooms/1exit/S_1.tscn", "res://scenes/rooms/1exit/S_2.tscn"],
	"E": ["res://scenes/rooms/1exit/E_1.tscn", "res://scenes/rooms/1exit/E_2.tscn"],
	"W": ["res://scenes/rooms/1exit/W_1.tscn", "res://scenes/rooms/1exit/W_2.tscn"],
}

const ROOMS_2_EXIT := {
	"NS": ["res://scenes/rooms/2exit/NS_1.tscn", "res://scenes/rooms/2exit/NS_2.tscn"],
	"NE": ["res://scenes/rooms/2exit/NE_1.tscn", "res://scenes/rooms/2exit/NE_2.tscn"],
	"NW": ["res://scenes/rooms/2exit/NW_1.tscn", "res://scenes/rooms/2exit/NW_2.tscn"],
	"SE": ["res://scenes/rooms/2exit/SE_1.tscn", "res://scenes/rooms/2exit/SE_2.tscn"],
	"SW": ["res://scenes/rooms/2exit/SW_1.tscn", "res://scenes/rooms/2exit/SW_2.tscn"],
	"EW": ["res://scenes/rooms/2exit/EW_1.tscn", "res://scenes/rooms/2exit/EW_2.tscn"],
}

## Claves = letras de salidas abiertas (orden del grafo); rutas = escenas [3exit] (NSE = sin W, etc.).
const ROOMS_3_EXIT := {
	"ENW": ["res://scenes/rooms/3exit/NEW_1.tscn", "res://scenes/rooms/3exit/NEW_2.tscn"],
	"WSE": ["res://scenes/rooms/3exit/SEW_1.tscn", "res://scenes/rooms/3exit/SEW_2.tscn"],
	"SEN": ["res://scenes/rooms/3exit/NSE_1.tscn", "res://scenes/rooms/3exit/NSE_2.tscn"],
	"NWS": ["res://scenes/rooms/3exit/NSW_1.tscn", "res://scenes/rooms/3exit/NSW_2.tscn"],
}

var _generated: bool = false
var _room_paths: PackedStringArray = []
## Cada sala: diccionario RoomTransition.ExitSide -> índice de sala vecina.
var _neighbors: Array = []
## Posición en rejilla del minimapa por id de sala (origen en la sala 0).
var _room_grid: Array = []
## Salas visibles en el minimapa (persistentes): sala actual + vecinos por puerta, al cargar cada sala.
var _room_minimap_revealed: Array = []
## Salas por las que el jugador ya ha pasado (para tono más suave en el minimapa).
var _room_visited: Array = []

var current_room_id: int = 0


func use_generated() -> bool:
	return _generated


func ensure_generated() -> void:
	if _generated:
		return
	generate()


func get_start_room_path() -> String:
	return _room_paths[0]


## Sala 0 del grafo: hub central con 4 salidas ([_pick_4exit] → [ROOMS_4_EXIT]).
func is_start_room_hub() -> bool:
	return _generated and current_room_id == 0


func get_next_room_path(exit_side: RoomTransition.ExitSide) -> String:
	var nid := get_next_room_id(exit_side)
	if nid < 0:
		return ""
	return _room_paths[nid]


func get_next_room_id(exit_side: RoomTransition.ExitSide) -> int:
	if current_room_id < 0 or current_room_id >= _neighbors.size():
		return -1
	var n: Variant = _neighbors[current_room_id].get(exit_side, -1)
	return n as int


func get_room_grid_pos(room_id: int) -> Vector2i:
	if room_id < 0 or room_id >= _room_grid.size():
		return Vector2i.ZERO
	return _room_grid[room_id] as Vector2i


func get_room_count() -> int:
	return _neighbors.size()


## Salidas de la sala en el grafo: [RoomTransition.ExitSide] -> id de sala vecina (>= 0).
func get_room_neighbors(room_id: int) -> Dictionary:
	if room_id < 0 or room_id >= _neighbors.size():
		return {}
	return (_neighbors[room_id] as Dictionary).duplicate()


func is_room_minimap_revealed(room_id: int) -> bool:
	if room_id < 0 or room_id >= _room_minimap_revealed.size():
		return false
	return _room_minimap_revealed[room_id] as bool


func is_room_visited(room_id: int) -> bool:
	if room_id < 0 or room_id >= _room_visited.size():
		return false
	return _room_visited[room_id] as bool


## Llama al entrar en una sala (p. ej. al fijar [current_room_id]).
func mark_room_entered(room_id: int) -> void:
	if room_id < 0 or room_id >= _room_visited.size():
		return
	_room_visited[room_id] = true


## Marca la sala actual y todas las conectadas por puerta (visibles desde aquí) como reveladas en el minimapa.
func reveal_minimap_from_current_room() -> void:
	var id := current_room_id
	if id < 0 or id >= _room_minimap_revealed.size():
		return
	_room_minimap_revealed[id] = true
	var neigh: Dictionary = _neighbors[id]
	for exit_side in neigh:
		var nid: int = neigh[exit_side] as int
		if nid >= 0 and nid < _room_minimap_revealed.size():
			_room_minimap_revealed[nid] = true


func generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hi: int = maxi(MIN_ROOMS, MAX_ROOMS)
	var r_count: int = rng.randi_range(MIN_ROOMS, hi)
	for _attempt in 64:
		if _try_build_dungeon(rng, r_count):
			return
		rng.randomize()
	push_error("Dungeon.generate: no se pudo construir la mazmorra")


func _try_build_dungeon(rng: RandomNumberGenerator, r_count: int) -> bool:
	var neighbors: Array = []
	neighbors.resize(r_count)
	for i in r_count:
		neighbors[i] = {}

	var grid: Array = []
	grid.resize(r_count)
	grid[0] = Vector2i(0, 0)

	# Sala 0 → 1–4 en cruz.
	var hub_dirs: Array = [
		RoomTransition.ExitSide.NORTH,
		RoomTransition.ExitSide.SOUTH,
		RoomTransition.ExitSide.EAST,
		RoomTransition.ExitSide.WEST,
	]
	for k in 4:
		var child_id: int = k + 1
		var d: RoomTransition.ExitSide = hub_dirs[k]
		var od: RoomTransition.ExitSide = _graph_opposite(d)
		neighbors[0][d] = child_id
		neighbors[child_id][od] = 0
		grid[child_id] = (grid[0] as Vector2i) + _grid_delta(d)

	var occupied: Dictionary = {}
	for j in range(5):
		occupied[grid[j] as Vector2i] = true

	# Una sala extra por brazo (5–8 → pegadas a 1–4); celda libre en rejilla.
	for k in 4:
		var branch_root: int = k + 1
		var new_id: int = k + 5
		var valid_dirs: Array = _valid_dirs_for_new_room(branch_root, neighbors, grid, occupied)
		if valid_dirs.is_empty():
			return false
		var d2: RoomTransition.ExitSide = valid_dirs[rng.randi() % valid_dirs.size()]
		var od2: RoomTransition.ExitSide = _graph_opposite(d2)
		neighbors[branch_root][d2] = new_id
		neighbors[new_id][od2] = branch_root
		grid[new_id] = (grid[branch_root] as Vector2i) + _grid_delta(d2)
		occupied[grid[new_id] as Vector2i] = true

	for i in range(9, r_count):
		var candidates: Array = []
		for p in range(i):
			if not _valid_dirs_for_new_room(p, neighbors, grid, occupied).is_empty():
				candidates.append(p)
		if candidates.is_empty():
			return false
		var parent: int = candidates[rng.randi() % candidates.size()]
		var free_dirs: Array = _valid_dirs_for_new_room(parent, neighbors, grid, occupied)
		if free_dirs.is_empty():
			return false
		var d3: RoomTransition.ExitSide = free_dirs[rng.randi() % free_dirs.size()]
		var od3: RoomTransition.ExitSide = _graph_opposite(d3)
		neighbors[parent][d3] = i
		neighbors[i][od3] = parent
		grid[i] = (grid[parent] as Vector2i) + _grid_delta(d3)
		occupied[grid[i] as Vector2i] = true

	var paths: PackedStringArray = []
	paths.resize(r_count)
	for i in r_count:
		if i == 0:
			paths[i] = _pick_4exit(rng)
		else:
			var exits: Array = neighbors[i].keys()
			paths[i] = _scene_for_directions(exits, rng)

	_room_paths = paths
	_neighbors = neighbors
	_room_grid = grid
	_setup_minimap_reveal_state(r_count)
	_generated = true
	current_room_id = 0
	reveal_minimap_from_current_room()
	return true


func _setup_minimap_reveal_state(r_count: int) -> void:
	_room_minimap_revealed.clear()
	_room_minimap_revealed.resize(r_count)
	_room_visited.clear()
	_room_visited.resize(r_count)
	for i in r_count:
		_room_minimap_revealed[i] = false
		_room_visited[i] = false


func _pick_4exit(rng: RandomNumberGenerator) -> String:
	return ROOMS_4_EXIT[rng.randi() % ROOMS_4_EXIT.size()]


func _scene_for_directions(exits: Array, rng: RandomNumberGenerator) -> String:
	var letters: Array[String] = []
	for e in exits:
		letters.append(_exit_side_to_letter(e as RoomTransition.ExitSide))
	var n: int = letters.size()
	if n == 1:
		var opts: Array = ROOMS_1_EXIT[letters[0]]
		return opts[rng.randi() % opts.size()] as String
	if n == 2:
		var key := _two_exit_key(letters[0], letters[1])
		var opts2: Array = ROOMS_2_EXIT[key]
		return opts2[rng.randi() % opts2.size()] as String
	if n == 3:
		var key3 := _three_exit_key_from_letters(letters)
		var opts3: Array = ROOMS_3_EXIT[key3]
		return opts3[rng.randi() % opts3.size()] as String
	return _pick_4exit(rng)


func _exit_side_to_letter(e: RoomTransition.ExitSide) -> String:
	match e:
		RoomTransition.ExitSide.NORTH:
			return "N"
		RoomTransition.ExitSide.SOUTH:
			return "S"
		RoomTransition.ExitSide.EAST:
			return "E"
		RoomTransition.ExitSide.WEST:
			return "W"
		_:
			return "N"


func _two_exit_key(a: String, b: String) -> String:
	var has := {}
	has[a] = true
	has[b] = true
	if has.has("N") and has.has("S"):
		return "NS"
	if has.has("E") and has.has("W"):
		return "EW"
	if has.has("N") and has.has("E"):
		return "NE"
	if has.has("N") and has.has("W"):
		return "NW"
	if has.has("S") and has.has("E"):
		return "SE"
	if has.has("S") and has.has("W"):
		return "SW"
	return "NS"


func _three_exit_key_from_letters(letters: Array[String]) -> String:
	var has := {}
	for x in letters:
		has[x] = true
	if not has.has("N"):
		return "WSE"
	if not has.has("S"):
		return "ENW"
	if not has.has("E"):
		return "NWS"
	if not has.has("W"):
		return "SEN"
	return "ENW"


func _graph_opposite(d: RoomTransition.ExitSide) -> RoomTransition.ExitSide:
	match d:
		RoomTransition.ExitSide.NORTH:
			return RoomTransition.ExitSide.SOUTH
		RoomTransition.ExitSide.SOUTH:
			return RoomTransition.ExitSide.NORTH
		RoomTransition.ExitSide.EAST:
			return RoomTransition.ExitSide.WEST
		RoomTransition.ExitSide.WEST:
			return RoomTransition.ExitSide.EAST
		_:
			return d


func _grid_delta(d: RoomTransition.ExitSide) -> Vector2i:
	match d:
		RoomTransition.ExitSide.NORTH:
			return Vector2i(0, -1)
		RoomTransition.ExitSide.SOUTH:
			return Vector2i(0, 1)
		RoomTransition.ExitSide.EAST:
			return Vector2i(1, 0)
		RoomTransition.ExitSide.WEST:
			return Vector2i(-1, 0)
		_:
			return Vector2i.ZERO


func _cardinal_dirs() -> Array:
	return [
		RoomTransition.ExitSide.NORTH,
		RoomTransition.ExitSide.SOUTH,
		RoomTransition.ExitSide.EAST,
		RoomTransition.ExitSide.WEST,
	]


## Direcciones libres desde `parent` cuya celda destino no está ocupada en `occupied`.
func _valid_dirs_for_new_room(parent: int, neighbors: Array, grid: Array, occupied: Dictionary) -> Array:
	var out: Array = []
	for d in _cardinal_dirs():
		if neighbors[parent].has(d):
			continue
		var np: Vector2i = (grid[parent] as Vector2i) + _grid_delta(d)
		if occupied.has(np):
			continue
		out.append(d)
	return out
