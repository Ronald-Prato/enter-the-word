extends Area2D

## Drop azul/neón que sueltan los enemigos al morir. Tras spawnear, un tiempo
## (`proximity_grace_s`) las gemas solo se recogen por contacto físico; luego
## activan imán + absorción por proximidad como `resource_pickup.gd`. Al
## recoger suma experiencia a `RunResources`.
signal picked_up(pickup: Area2D)

const SPIN_SPEED: float = 1.15

## A partir de esta distancia el ítem "salta" hacia el jugador.
@export var magnet_radius: float = 140.0
@export var magnet_speed: float = 360.0
## Radio de absorción más amplio que el de un resource pickup: las gemas de
## experiencia son pequeñas y no queremos que el jugador tenga que pisarlas
## exactamente; al cruzar esta distancia se recogen solas.
@export var absorb_distance: float = 24.0
## Tras spawnear, las gemas quedan quietas en el suelo este tiempo (s). Durante
## ese lapso no hay imán ni absorción por proximidad; sí se pueden recoger al
## pisarlas (overlap físico con el Area2D). Pasado el tiempo, actúa el imán normal.
@export var proximity_grace_s: float = 0.5
## Cantidad de XP otorgada por este pickup al ser recogido.
@export var xp_amount: int = 1

@onready var _pivot: Node2D = $VisualPivot
@onready var _highlight: Polygon2D = $VisualPivot/GemHighlight
@onready var _light: PointLight2D = $Glow

var _consumed: bool = false
var _pulse_t: float = 0.0
var _player: CharacterBody2D
var _light_base_energy: float = 1.0
## Tiempo restante antes de activar imán + absorción por proximidad.
var _grace_remaining: float = 0.0


func _ready() -> void:
	set_process(true)
	body_entered.connect(_on_body_entered)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if _pivot != null:
		_pivot.rotation = randf() * TAU
	_pulse_t = randf() * TAU
	if _light != null:
		_light_base_energy = _light.energy
	_grace_remaining = maxf(proximity_grace_s, 0.0)


func _resolve_player() -> void:
	if is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func _process(delta: float) -> void:
	if _consumed:
		return
	_resolve_player()

	if _grace_remaining > 0.0:
		_grace_remaining = maxf(_grace_remaining - delta, 0.0)

	if _grace_remaining <= 0.0 and _player != null:
		var to_player: Vector2 = _player.global_position - global_position
		var dist: float = to_player.length()
		if dist <= absorb_distance:
			_collect()
			return
		if dist <= magnet_radius and dist > 0.001:
			var dir: Vector2 = to_player / dist
			global_position += dir * magnet_speed * delta

	if _pivot != null:
		_pivot.rotation += delta * SPIN_SPEED
	_pulse_t += delta * 5.0
	var pulse: float = sin(_pulse_t)
	if _highlight != null:
		var w: float = 0.55 + 0.35 * pulse
		_highlight.modulate.a = w
	if _light != null:
		_light.energy = _light_base_energy * (0.82 + 0.18 * pulse)


func _collect() -> void:
	if _consumed:
		return
	_consumed = true
	set_process(false)
	RunResources.add_experience(xp_amount)
	_resolve_player()
	if is_instance_valid(_player) and _player.has_method("add_level_xp"):
		# Cada gema: 5 puntos de progreso hacia el siguiente nivel (ver `player.gd`).
		_player.call("add_level_xp", 5.0 * float(xp_amount))
	if is_instance_valid(_player) and _player.has_method("flash_pickup_feedback"):
		_player.flash_pickup_feedback()
	picked_up.emit(self)
	queue_free()


func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	if body is CharacterBody2D:
		_player = body as CharacterBody2D
		_collect()
