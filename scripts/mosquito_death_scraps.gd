extends Node2D

## Píxeles fijos en mundo donde murió un mosquito (colores muestreados del sprite).

const SCRAP_PX := 2.0

var _offsets: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()


func setup(world_center: Vector2, scrap_colors: PackedColorArray, scrap_offsets: PackedVector2Array) -> void:
	global_position = world_center
	_colors = scrap_colors.duplicate()
	_offsets = scrap_offsets.duplicate()
	var n: int = mini(_colors.size(), _offsets.size())
	if n < _colors.size():
		_colors.resize(n)
	if n < _offsets.size():
		_offsets.resize(n)
	_apply_darkness_unshroud()
	queue_redraw()


func _apply_darkness_unshroud() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var w := scene.get_node_or_null("WorldDarkness") as CanvasModulate
	if w == null:
		return
	var c := w.color
	var e := 0.001
	modulate = Color(
		1.0 / maxf(c.r, e),
		1.0 / maxf(c.g, e),
		1.0 / maxf(c.b, e),
		1.0 / maxf(c.a, e)
	)


func _draw() -> void:
	var h := SCRAP_PX * 0.5
	var n: int = mini(_colors.size(), _offsets.size())
	for i in n:
		var o: Vector2 = _offsets[i]
		draw_rect(Rect2(o.x - h, o.y - h, SCRAP_PX, SCRAP_PX), _colors[i])
