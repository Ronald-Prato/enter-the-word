extends Panel

## Escala al mantener Tab (crece hacia abajo-izquierda, esquina sup-der fija).
@export var expand_scale: float = 1.75
## Suavizado hacia la escala objetivo (mayor = más rápido).
@export var expand_smooth_speed: float = 14.0

## Factor actual de expansión (1.0 = normal). MinimapDraw lo lee para ajustar el cell size.
var expand_t: float = 0.0

var _base_position: Vector2
var _base_size: Vector2


func _ready() -> void:
	_base_position = position
	_base_size = size


func _process(delta: float) -> void:
	var target := expand_scale if Input.is_physical_key_pressed(KEY_TAB) else 1.0
	var s := lerpf(scale.x, target, 1.0 - exp(-delta * expand_smooth_speed))

	expand_t = clampf((s - 1.0) / (expand_scale - 1.0), 0.0, 1.0)

	var top_right := _base_position + Vector2(_base_size.x, 0.0)
	position = top_right - Vector2(_base_size.x * s, 0.0)
	scale = Vector2(s, s)
