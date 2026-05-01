extends Control

## Solo se dibujan salas ya reveladas por [Dungeon.reveal_minimap_from_current_room] (sala actual + vecinas por puerta al entrar).
## La sala actual se centra con transición suave al cambiar de sala.

## Hueco entre celdas; el fondo [COLOR_GRID_BG] se ve en las separaciones.
const CELL_GAP := 3.0
## Píxeles por celda en estado normal y expandido.
const CELL_SIZE_NORMAL := 60.0
const CELL_SIZE_EXPANDED := 30.0

## Fondo del panel = “lechada” entre celdas (líneas de rejilla visibles).
const COLOR_GRID_BG := Color(0.2, 0.2, 0.23, 1.0)
## En el minimapa pero nunca pisada (solo adyacencia); más oscuro que las ya visitadas.
const COLOR_REVEALED_UNVISITED := Color(0.32, 0.32, 0.4, 1.0)
## Visitada antes; no es la sala actual.
const COLOR_VISITED_NOT_CURRENT := Color(0.78, 0.78, 0.82, 1.0)
const COLOR_CURRENT := Color(1.0, 1.0, 1.0, 1.0)
## Cuadrado pequeño por pasillo (centro del hueco entre dos celdas).
const COLOR_DOOR := Color(0.35, 0.92, 0.98, 1.0)
const DOOR_MARK_MIN := 4.0
const DOOR_MARK_MAX := 9.0
## Fracción del tamaño de celda (minimapa normal vs expandido).
const DOOR_MARK_CELL_FRAC := 0.22

## Centro de la vista en coordenadas de rejilla (float) para animar el desplazamiento.
var _grid_center_smooth: Vector2 = Vector2.ZERO
var _grid_tween: Tween
var _panel: Panel


func _ready() -> void:
	_panel = get_parent() as Panel
	Dungeon.ensure_generated()
	sync_from_dungeon()


func _process(_delta: float) -> void:
	if _panel != null and (_panel.expand_t > 0.01 or _panel.scale.x > 1.01):
		queue_redraw()


func sync_from_dungeon() -> void:
	if not Dungeon.use_generated():
		return
	var id := Dungeon.current_room_id
	var n := Dungeon.get_room_count()
	if id < 0 or id >= n:
		return
	if _grid_tween != null and is_instance_valid(_grid_tween):
		_grid_tween.kill()
		_grid_tween = null
	_grid_center_smooth = Vector2(Dungeon.get_room_grid_pos(id))
	queue_redraw()


func animate_grid_transition(from_id: int, to_id: int, duration: float) -> void:
	if not Dungeon.use_generated():
		return
	var n := Dungeon.get_room_count()
	if from_id < 0 or from_id >= n or to_id < 0 or to_id >= n:
		sync_from_dungeon()
		return
	if from_id == to_id or duration <= 0.0:
		sync_from_dungeon()
		return
	var g0 := Vector2(Dungeon.get_room_grid_pos(from_id))
	var g1 := Vector2(Dungeon.get_room_grid_pos(to_id))
	_grid_center_smooth = g0
	queue_redraw()
	if _grid_tween != null and is_instance_valid(_grid_tween):
		_grid_tween.kill()
	_grid_tween = create_tween()
	_grid_tween.set_trans(Tween.TRANS_QUAD)
	_grid_tween.set_ease(Tween.EASE_IN_OUT)
	_grid_tween.tween_method(_apply_grid_center_lerp.bind(g0, g1), 0.0, 1.0, duration)
	_grid_tween.finished.connect(_on_grid_tween_finished)


func _apply_grid_center_lerp(t: float, g0: Vector2, g1: Vector2) -> void:
	_grid_center_smooth = g0.lerp(g1, t)
	queue_redraw()


func _on_grid_tween_finished() -> void:
	_grid_tween = null


func _draw() -> void:
	if not Dungeon.use_generated():
		return
	var room_count := Dungeon.get_room_count()
	if room_count <= 0:
		return

	var cur_id := Dungeon.current_room_id
	if cur_id < 0 or cur_id >= room_count:
		return

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_GRID_BG, true)

	var t: float = _panel.expand_t if _panel != null else 0.0
	var cell := lerpf(CELL_SIZE_NORMAL, CELL_SIZE_EXPANDED, t)
	var cell_v := Vector2(cell, cell)
	var half := size * 0.5
	var room_rects: Dictionary = {}

	for i in room_count:
		if not Dungeon.is_room_minimap_revealed(i):
			continue
		var g: Vector2i = Dungeon.get_room_grid_pos(i)
		var d := Vector2(g) - _grid_center_smooth
		var center := half + Vector2(d.x, d.y) * cell
		var r := Rect2(center - cell_v * 0.5, cell_v)
		r = r.grow(-CELL_GAP * 0.5)
		room_rects[i] = r
		var col: Color
		if i == cur_id:
			col = COLOR_CURRENT
		elif Dungeon.is_room_visited(i):
			col = COLOR_VISITED_NOT_CURRENT
		else:
			col = COLOR_REVEALED_UNVISITED
		draw_rect(r, col, true)

	for i in room_rects:
		var neigh: Dictionary = Dungeon.get_room_neighbors(i)
		for exit_side in neigh:
			var j: int = neigh[exit_side] as int
			if j < 0 or j <= i:
				continue
			if not room_rects.has(j):
				continue
			var dg: Vector2i = Dungeon.get_room_grid_pos(j) - Dungeon.get_room_grid_pos(i)
			_draw_corridor_mid_pixel(room_rects[i] as Rect2, room_rects[j] as Rect2, dg, cell)


func _draw_corridor_mid_pixel(r_i: Rect2, r_j: Rect2, dg: Vector2i, cell: float) -> void:
	var px: float
	var py: float
	if dg.x == 1:
		px = (r_i.end.x + r_j.position.x) * 0.5
		py = (r_i.get_center().y + r_j.get_center().y) * 0.5
	elif dg.x == -1:
		px = (r_j.end.x + r_i.position.x) * 0.5
		py = (r_i.get_center().y + r_j.get_center().y) * 0.5
	elif dg.y == 1:
		px = (r_i.get_center().x + r_j.get_center().x) * 0.5
		py = (r_i.end.y + r_j.position.y) * 0.5
	elif dg.y == -1:
		px = (r_i.get_center().x + r_j.get_center().x) * 0.5
		py = (r_j.end.y + r_i.position.y) * 0.5
	else:
		return
	var s := clampf(cell * DOOR_MARK_CELL_FRAC, DOOR_MARK_MIN, DOOR_MARK_MAX)
	var half := s * 0.5
	var origin := Vector2(px - half, py - half)
	draw_rect(Rect2(origin, Vector2(s, s)), COLOR_DOOR, true)
