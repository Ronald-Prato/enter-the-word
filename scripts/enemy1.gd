extends CharacterBody2D

@export var spawn_fade_duration: float = 0.4
@export var move_speed: float = 22.0
@export var direction_change_interval: float = 2.0
@export var wall_probe_distance: float = 18.0
@export var direction_samples: int = 24

@export var detection_radius: float = 120.0
@export var detection_fill_color: Color = Color(1, 0.25, 0.2, 0.14)
@export var detection_outline_color: Color = Color(1, 0.35, 0.3, 0.4)

## Radio interior: al entrar aquí empieza el ataque (solo si no estás ya en ATTACK).
@export var attack_radius: float = 48.0
@export var attack_fill_color: Color = Color(0.9, 0.45, 0.15, 0.18)
@export var attack_outline_color: Color = Color(1, 0.55, 0.2, 0.55)
@export var attack_windup_duration: float = 0.8
@export var attack_dash_speed: float = 400.0
## Distancia del dash = attack_radius * este factor (p. ej. 1.5).
@export var attack_dash_distance_factor: float = 1
## Tras completar un dash, no puede volver a entrar en ataque hasta que pase este tiempo.
@export var attack_dash_cooldown: float = 1.0

@onready var _depth_sort: Marker2D = $DepthSort
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _detection_area: Area2D = $DetectionArea

enum State { WANDER, CHASE, ATTACK }

enum AttackPhase { WINDUP, DASH }

var _state: State = State.WANDER
var _attack_phase: AttackPhase = AttackPhase.WINDUP
var _move_direction: Vector2 = Vector2.RIGHT
var _dir_timer: float = 0.0
var _chase_target: CharacterBody2D = null
## Borde para entrar en ataque (evita re-disparar cada frame).
var _player_was_in_attack_range: bool = false
var _attack_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _dash_traveled: float = 0.0
var _dash_distance_total: float = 0.0
var _attack_dash_cooldown_left: float = 0.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("enemies")
	z_as_relative = false
	z_index = 6
	_detection_area.body_entered.connect(_on_detection_body_entered)
	_detection_area.body_exited.connect(_on_detection_body_exited)
	_sync_detection_shape_radius()
	_pick_new_direction()


func _physics_process(delta: float) -> void:
	var cooldown_just_ended := false
	if _attack_dash_cooldown_left > 0.0:
		var prev_cd := _attack_dash_cooldown_left
		_attack_dash_cooldown_left = maxf(_attack_dash_cooldown_left - delta, 0.0)
		cooldown_just_ended = prev_cd > 0.0 and _attack_dash_cooldown_left <= 0.0

	if _state != State.ATTACK:
		var p := _get_player()
		var in_attack := false
		if p != null and is_instance_valid(p):
			in_attack = global_position.distance_to(p.global_position) <= attack_radius
		if in_attack and not _player_was_in_attack_range:
			_begin_attack(p)
		elif cooldown_just_ended and in_attack:
			_begin_attack(p)
		_player_was_in_attack_range = in_attack

	match _state:
		State.WANDER:
			_process_wander(delta)
		State.CHASE:
			_process_chase()
		State.ATTACK:
			_process_attack(delta)

	if velocity.x != 0.0:
		_sprite.flip_h = velocity.x < 0.0

	var prev_pos := global_position
	move_and_slide()

	if _state == State.ATTACK and _attack_phase == AttackPhase.DASH:
		_dash_traveled += prev_pos.distance_to(global_position)
		if _dash_traveled >= _dash_distance_total:
			_finish_attack()


func _draw() -> void:
	var rd := detection_radius
	if rd > 0.0:
		draw_circle(Vector2.ZERO, rd, detection_fill_color)
		draw_arc(Vector2.ZERO, rd, 0.0, TAU, 72, detection_outline_color, 2.0, false)
	var ra := attack_radius
	if ra > 0.0 and ra < rd:
		draw_circle(Vector2.ZERO, ra, attack_fill_color)
		draw_arc(Vector2.ZERO, ra, 0.0, TAU, 72, attack_outline_color, 2.0, false)


# -- WANDER -------------------------------------------------------------------

func _process_wander(delta: float) -> void:
	_dir_timer += delta
	if _dir_timer >= direction_change_interval:
		_dir_timer = 0.0
		_pick_new_direction()
	velocity = _move_direction * move_speed


func _pick_new_direction() -> void:
	var valid := _gather_clear_directions(wall_probe_distance)
	if valid.is_empty():
		valid = _gather_clear_directions(wall_probe_distance * 0.45)
	if valid.is_empty():
		_move_direction = Vector2.from_angle(randf() * TAU).normalized()
		return
	_move_direction = valid[randi() % valid.size()].normalized()


# -- CHASE --------------------------------------------------------------------

func _process_chase() -> void:
	if _chase_target == null or not is_instance_valid(_chase_target):
		_transition_to(State.WANDER)
		return
	var dir := (_chase_target.global_position - global_position).normalized()
	velocity = dir * move_speed


# -- ATTACK -------------------------------------------------------------------

func _process_attack(delta: float) -> void:
	match _attack_phase:
		AttackPhase.WINDUP:
			velocity = Vector2.ZERO
			_attack_timer += delta
			if _attack_timer >= attack_windup_duration:
				_start_attack_dash()
		AttackPhase.DASH:
			velocity = _dash_dir * attack_dash_speed


func _start_attack_dash() -> void:
	var p := _chase_target
	if p == null or not is_instance_valid(p):
		p = _get_player()
	if p == null or not is_instance_valid(p):
		_finish_attack()
		return
	_chase_target = p
	_dash_dir = (p.global_position - global_position).normalized()
	if _dash_dir.length_squared() < 0.0001:
		_dash_dir = Vector2.RIGHT
	_dash_distance_total = attack_radius * attack_dash_distance_factor
	_dash_traveled = 0.0
	_attack_phase = AttackPhase.DASH


func _finish_attack() -> void:
	var p := _get_player()
	if p == null or not is_instance_valid(p):
		_transition_to(State.WANDER)
		_player_was_in_attack_range = false
		return
	var d := global_position.distance_to(p.global_position)
	_chase_target = p

	var completed_dash := _attack_phase == AttackPhase.DASH
	if completed_dash:
		_attack_dash_cooldown_left = attack_dash_cooldown
	if d <= detection_radius:
		_transition_to(State.CHASE)
		_player_was_in_attack_range = d <= attack_radius
	else:
		_transition_to(State.WANDER)
		_player_was_in_attack_range = false


func _begin_attack(player: CharacterBody2D) -> void:
	if _attack_dash_cooldown_left > 0.0:
		return
	if _state == State.ATTACK:
		return
	if player == null or not is_instance_valid(player):
		return
	_chase_target = player
	_transition_to(State.ATTACK)


# -- STATE TRANSITIONS --------------------------------------------------------

func _transition_to(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	match new_state:
		State.WANDER:
			_chase_target = null
			_dir_timer = 0.0
			_pick_new_direction()
		State.CHASE:
			pass
		State.ATTACK:
			_attack_phase = AttackPhase.WINDUP
			_attack_timer = 0.0


# -- DETECTION ----------------------------------------------------------------

func _on_detection_body_entered(body: Node2D) -> void:
	if _state == State.ATTACK:
		return
	if body.is_in_group("player"):
		_chase_target = body as CharacterBody2D
		_transition_to(State.CHASE)


func _on_detection_body_exited(body: Node2D) -> void:
	if _state == State.ATTACK:
		return
	if body == _chase_target:
		_transition_to(State.WANDER)


func _sync_detection_shape_radius() -> void:
	var cs := _detection_area.get_node_or_null("DetectionShape") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = detection_radius


func _get_player() -> CharacterBody2D:
	var n := get_tree().get_first_node_in_group("player")
	if n is CharacterBody2D:
		return n as CharacterBody2D
	return null


# -- HELPERS (raycasts) -------------------------------------------------------

func _gather_clear_directions(probe: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(direction_samples, 8)
	for i in n:
		var dir := Vector2.from_angle(TAU * float(i) / float(n))
		if _is_direction_clear(dir, probe):
			out.append(dir)
	return out


func _is_direction_clear(dir: Vector2, probe: float) -> bool:
	var d := dir.normalized()
	if d.length_squared() < 0.0001:
		return false
	var space := get_world_2d().direct_space_state
	var from := global_position
	var to := from + d * probe
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.exclude = [self]
	q.collision_mask = collision_mask
	return space.intersect_ray(q).is_empty()


# -- PUBLIC API (usado por game.gd) -------------------------------------------

func get_depth_sort_global_y() -> float:
	if _depth_sort != null and is_instance_valid(_depth_sort):
		return _depth_sort.global_position.y
	return global_position.y


func play_spawn_fade_in(duration: float = -1.0) -> void:
	var d := spawn_fade_duration if duration < 0.0 else duration
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, d)
