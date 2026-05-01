extends Node2D

## Swing de ataque melee: detecta enemigos en cono frente al player y aplica daño.
## Replica el funcionamiento de skai (player_swing.gd) sin depender de assets de slash.

const ENEMY_BODY_LAYER_MASK: int = 8

## Frame (0-based) en el que se considera impacto. -1 = mitad de la animación.
@export var impact_frame: int = -1

## Área circular del swipe (igual que en skai).
@export var swing_collision_coverage: float = 0.28

## Golpe melee a enemigos: centro enemigo en ≤ attack_range + radial_margin desde el jugador…
@export var enemy_hit_radial_margin_px: float = 9.0
## … y dentro de un cono de esta mitad (grados) hacia cada lado frente al arco del swing.
@export var enemy_hit_cone_half_deg: float = 36.0

## Multiplicador sobre player.damage.
var _damage_multiplier: float = 1.0
var _already_hit: bool = false
var _impact_frame_resolved: int = -1
var _attack_range_px: float = -1.0
var _player_spawn_pos: Vector2 = Vector2.ZERO
var _player: Node2D = null
var _target: Node2D = null

@onready var _area: Area2D = $Area
@onready var _collision: CollisionShape2D = $Area/CollisionShape2D


func setup(
	target: Node2D,
	facing_angle_rad: float,
	_reach_px: float = -1.0,
	swing_mode: int = 1,
	attack_range_px: float = -1.0,
	player_spawn_pos: Vector2 = Vector2.ZERO,
	damage_multiplier: float = 1.0,
	_empowered_glow: bool = false
) -> void:
	_target = target
	_attack_range_px = attack_range_px
	_player_spawn_pos = player_spawn_pos
	_damage_multiplier = damage_multiplier
	rotation = facing_angle_rad
	
	# Buscar player en grupo.
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D


func _ready() -> void:
	add_to_group(&"player_swing")
	# El Area2D solo detecta cuerpos de enemigos (capa 8).
	_area.collision_mask = ENEMY_BODY_LAYER_MASK
	_area.collision_layer = 0
	_area.monitoring = true
	_area.monitorable = false
	# Conectar area_entered para detectar recursos (no enemigos); enemigos se procesan manualmente.
	_area.area_entered.connect(_on_area_entered)
	_resolve_impact_frame()
	# Duración del swing = vida del nodo.
	# Si hay animación, esperarla; si no, autodestruirse tras un frame de impacto.
	# En este proyecto no hay sprite de slash, así que el swing dura 1 frame de physics + autodestruye.
	if _impact_frame_resolved <= 0:
		call_deferred("_emit_hit")
	else:
		# Pequeño delay para que el Area2D registre overlaps.
		var t := get_tree().create_timer(0.05)
		t.timeout.connect(_emit_hit)


func _resolve_impact_frame() -> void:
	_impact_frame_resolved = maxi(impact_frame, 0)


func _emit_hit() -> void:
	if _already_hit:
		return
	_already_hit = true
	_area.set_deferred("monitoring", false)
	_emit_enemy_hits()
	# Autodestrucción inmediata.
	queue_free()


func _emit_enemy_hits() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	var ppos: Vector2 = _player.global_position
	var player_damage: float = 0.0
	if "damage" in _player:
		player_damage = float(_player.get("damage"))
	var r_atk: float = _attack_range_px
	if r_atk <= 0.0:
		r_atk = 100.0
	var radial_margin: float = maxf(enemy_hit_radial_margin_px, 0.0)
	var cone_half: float = clampf(enemy_hit_cone_half_deg, 15.0, 85.0)
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var cos_lim: float = cos(deg_to_rad(cone_half))
	var any_hit: bool = false
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == null or not is_instance_valid(n) or not (n is Node2D):
			continue
		var e := n as Node2D
		var to_e: Vector2 = e.global_position - ppos
		var dist: float = to_e.length()
		if dist > r_atk + radial_margin:
			continue
		if dist < 0.001:
			continue
		var nd: Vector2 = to_e / dist
		if forward.dot(nd) < cos_lim:
			continue
		var away: Vector2 = to_e
		var dmg: float = player_damage * _damage_multiplier
		if e.has_method("receive_player_melee_hit"):
			e.call("receive_player_melee_hit", away, dmg)
			any_hit = true
		elif e.has_method("apply_player_swing_knockback"):
			e.call("apply_player_swing_knockback", away, dmg)
			any_hit = true
		elif e is CharacterBody2D:
			var cb := e as CharacterBody2D
			cb.velocity += nd * 48.0
			any_hit = true
	if any_hit:
		get_tree().call_group("game_camera", "shake_on_enemy_hit")


func _on_area_entered(a: Area2D) -> void:
	# Reservado para recursos (no usado en este proyecto por ahora).
	pass
