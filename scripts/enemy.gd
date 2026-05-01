extends CharacterBody2D

## Enemigo de persecución + estocada (`scenes/enemy.tscn`).
## Colgá `AnimatedSprite2D` / `Sprite2D` bajo `SpriteHolder` para arte propio;
## la lógica (IA, golpes, colisión) sigue en este nodo raíz.
##
## AI:
##  - Intercepción (lead target) + separation entre enemigos.
##  - Ataque cuerpo a cuerpo: si el player entra en `attack_range`, pausa
##    `attack_windup_s` y luego estocada + dash. La dirección se fija en
##    `attack_aim_lock_at_s` (p. ej. a los 400 ms de un windup de 600 ms):
##    apunta a donde estaba el player en ese instante; los últimos ms son margen
##    para esquivar. Sin daño al player por ahora.

enum State { CHASE, WINDUP, STRIKE }

@export var speed: float = 62.0
@export var accel_smoothing: float = 6.5
@export var radius: float = 8.0
@export var body_color: Color = Color(0.95, 0.22, 0.22, 1.0)
## Si false, no se dibuja el círculo del cuerpo (p. ej. enemigo con `AnimatedSprite2D`).
@export var draws_body_circle: bool = true
## Si false, no se dibuja la hoja / polígono de estocada en `STRIKE` (daño por otro canal).
@export var draws_attack_blade: bool = true
## Si false, no se dibuja el círculo HDR al recibir golpe; podés usar `_sync_hit_flash_visual` en una subclase.
@export var draws_hit_flash_circle: bool = true

## Vida máxima: el jugador hace daño con `player.damage` en cada golpe.
@export var max_health: float = 9.0

## Duración de la animación de aparición (scale 0 → 1).
@export var spawn_scale_duration: float = 0.35
## Duración de la animación provisional de muerte (scale actual → 0).
@export var death_scale_duration: float = 0.28

@export var lead_bias_min: float = 0.75
@export var lead_bias_max: float = 1.15
@export var max_lead_time: float = 3.0
@export var player_still_threshold: float = 8.0

@export var separation_radius: float = 22.0
@export var separation_weight: float = 60.0

## --- Ataque (estocada) ---
## Distancia al player para iniciar windup (se dibuja el círculo de alcance).
@export var attack_range: float = 48.0
## Pausa antes de la estocada + dash (carga total).
@export var attack_windup_s: float = 0.6
## Tiempo desde el inicio de la carga en el que se fija la dirección hacia el
## player (snapshot de su posición). Debe ser ≤ `attack_windup_s`; el resto es
## margen de maniobra (p. ej. 0,4 s de 0,6 s → 200 ms para cambiar de rumbo).
@export var attack_aim_lock_at_s: float = 0.4
## Duración total de la fase STRIKE (dash + espada visible). Debe ser ≥ `attack_dash_duration_s`.
@export var attack_strike_s: float = 0.24
## Duración del desplazamiento rápido hacia el player al inicio del golpe.
@export var attack_dash_duration_s: float = 0.1
## Velocidad del dash (px/s). Corto pero rápido.
@export var attack_dash_speed: float = 420.0
## Tras completar el ataque, no se puede volver a intentar hasta pasado este tiempo.
@export var attack_cooldown_s: float = 0.85

## Longitud de la estocada desde el borde del cuerpo hacia delante (también define el alcance del golpe en `_try_hit_player`).
@export var attack_length: float = 20.0
## Ancho de la hoja en la base y en la punta (forma de cuchilla / pinchazo).
@export var attack_width_base: float = 8.0
@export var attack_width_tip: float = 3.0
## HDR rojo/salmón (>1 en los canales) para que el `WorldEnvironment.glow`
## genere un halo estilo neón sobre la hoja.
@export var attack_blade_color: Color = Color(3.4, 1.05, 0.95, 0.95)
## Núcleo brillante en el centro de la hoja (“máscara” con más HDR) para el
## acabado neón: se dibuja encima con un polígono un poco más fino.
@export var attack_blade_core_color: Color = Color(5.6, 2.4, 2.0, 1.0)

## Daño (en corazones) que el enemigo inflige al jugador por cada estocada. 0.5 = medio corazón.
@export var player_damage: float = 0.5
## Margen sobre el alcance de la hoja en el que se considera impacto con el jugador.
@export var player_hit_reach_pad: float = 4.0
## Radio aproximado del jugador para calcular el impacto (debe coincidir con `player.collision_radius`).
@export var player_body_radius: float = 9.0
## Apertura del cono de impacto alrededor de `_strike_dir` (grados). Fuera del cono solo hay hit por contacto directo.
@export var player_hit_cone_deg: float = 65.0

## Cantidad máxima de puntos de la estela (más = estela más larga, pero más cara de dibujar).
@export var trail_max_points: int = 14
## Cada cuántos segundos se añade un punto a la estela durante el dash.
@export var trail_sample_interval_s: float = 0.015
## Cuando la estela deja de crecer, pierde puntos a este ritmo (por segundo) para desvanecerse.
@export var trail_fade_points_per_s: float = 55.0

## Pico de empuje al recibir el melee del jugador (se amortigua con `_player_hit_knockback`).
@export var player_melee_knockback_peak: float = 30.0
## Duración total del flash blanco (máscara con glow) al ser golpeado.
@export var player_hit_flash_duration: float = 0.26
## Brillo HDR del flash en el pico (1.0 = sin glow; >1 activa bloom con el WorldEnvironment).
@export var player_hit_flash_hdr: float = 5.5
## Hinchazón del radio del flash en el pico (px extra sobre `radius`).
@export var player_hit_flash_radius_bump: float = 2.2

## Visual del radio de ataque (muy suave, como el spawn del player).
@export var attack_range_fill: Color = Color(1.0, 0.35, 0.28, 0.09)
@export var attack_range_ring: Color = Color(1.0, 0.45, 0.38, 0.35)
@export var attack_range_ring_width: float = 1.25
@export var attack_range_arc_segments: int = 64

## Drop de experiencia al morir (gema azul neón con glow púrpura).
## Desactivado por defecto: todavía no usamos XP en este modo de juego.
@export var drops_xp_on_death: bool = false
@export var xp_pickup_scene: PackedScene
## Rango de cantidades a soltar (inclusive). Se elige uniforme entre min y max.
@export_range(0, 8, 1) var xp_drops_min: int = 1
@export_range(0, 8, 1) var xp_drops_max: int = 3
## Dispersión horizontal/vertical de los drops alrededor del centro del enemigo.
@export var xp_drop_spread_x: float = 14.0
@export var xp_drop_spread_y: float = 10.0

## Marco de esquinas al seleccionar (misma forma que los recursos).
## Va ceñido al cuerpo: `radius` + este margen (px desde el centro hasta la caja que encierra las L).
@export var selection_frame_margin: float = 4.25
@export var selection_corner_length: float = 5.0
@export var selection_color: Color = Color(0.96, 0.86, 0.38, 0.95)
var _is_selected: bool = false

var _player: CharacterBody2D
var _spawn_tween: Tween
var _death_tween: Tween
var _lead_bias: float = 1.0
var _hit_flash_tween: Tween
## Intensidad actual del flash de golpe (0..1). Se tweenea a 0 y se dibuja en `_draw`.
var _flash_intensity: float = 0.0
## Vector extra aplicado encima de la velocidad de la IA; decae suavemente (sensación de empuje con ease).
var _player_hit_knockback: Vector2 = Vector2.ZERO
var _health: float = 0.0
var _dying: bool = false

@onready var _hit_particles: CPUParticles2D = $HitParticles

static var _pixel_spark_tex: Texture2D
var _hit_spark_color_ramp: Gradient

var _state: State = State.CHASE
var _windup_remaining: float = 0.0
var _strike_remaining: float = 0.0
var _dash_remaining: float = 0.0
var _cooldown_remaining: float = 0.0
## Tras `attack_aim_lock_at_s`, ya no se actualiza hasta el próximo ataque.
var _aim_locked: bool = false
## Dirección de la estocada (normalizada, espacio global → se convierte a local al dibujar).
var _strike_dir: Vector2 = Vector2.RIGHT
## Evita impactar al jugador varias veces con una misma estocada.
var _strike_hit_player: bool = false

## Trail (estela) durante el dash. Usamos Line2D con `top_level = true` para
## guardar puntos en mundo y que no se muevan con el enemigo.
@onready var _trail: Line2D = $Trail
var _trail_sample_acc: float = 0.0
var _trail_fade_acc: float = 0.0


func _ready() -> void:
	if not is_in_group("enemies"):
		add_to_group("enemies")
	if _pixel_spark_tex == null:
		_pixel_spark_tex = _create_pixel_spark_texture()
	_setup_hit_particles()
	_lead_bias = randf_range(lead_bias_min, lead_bias_max)
	_health = max_health
	_refresh_player()
	_play_spawn_animation()
	_compensate_world_darkness_modulate()
	queue_redraw()


## Anula el tinte de `WorldDarkness` (CanvasModulate en la escena principal): opacidad y color plenos.
func _compensate_world_darkness_modulate() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var world_dark := scene.get_node_or_null("WorldDarkness") as CanvasModulate
	if world_dark == null:
		return
	var c := world_dark.color
	var e := 0.001
	modulate = Color(
		1.0 / maxf(c.r, e),
		1.0 / maxf(c.g, e),
		1.0 / maxf(c.b, e),
		1.0 / maxf(c.a, e)
	)


func is_selected() -> bool:
	return _is_selected


func set_selected(v: bool) -> void:
	if v and _dying:
		return
	if _is_selected == v:
		return
	_is_selected = v
	queue_redraw()


## Cuadrado 2×2 opaco: se combina con `TEXTURE_FILTER_NEAREST` y escala grande para lucir como pixel art.
func _create_pixel_spark_texture() -> ImageTexture:
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _setup_hit_particles() -> void:
	if _hit_particles == null:
		return
	_hit_particles.texture = _pixel_spark_tex
	_hit_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hit_particles.use_parent_material = false
	_hit_spark_color_ramp = _create_hit_spark_color_ramp()
	_hit_particles.color_ramp = _hit_spark_color_ramp


## LDR: sin glow. Un naranja rojizo que se mantiene opaco y cae rápido a alpha 0 al final.
func _create_hit_spark_color_ramp() -> Gradient:
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.78, 0.58, 1.0))
	grad.add_point(0.35, Color(1.0, 0.45, 0.35, 1.0))
	grad.add_point(0.75, Color(0.78, 0.25, 0.22, 0.8))
	grad.add_point(1.0, Color(0.5, 0.15, 0.15, 0.0))
	return grad


func _play_spawn_animation() -> void:
	scale = Vector2.ZERO
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = create_tween()
	_spawn_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_tween.tween_property(self, "scale", Vector2.ONE, spawn_scale_duration)


func _refresh_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func apply_player_swing_knockback(from_direction: Vector2, damage: float = 0.0) -> void:
	receive_player_melee_hit(from_direction, damage)


## Impacto del swing del jugador: partículas, destello, empuje amortiguado y resta de vida.
## Si la vida llega a 0, dispara la animación de muerte (scale → 0) y libera el nodo.
func receive_player_melee_hit(from_direction: Vector2, damage: float = 0.0, knockback_scale: float = 1.0) -> void:
	if _dying:
		return
	if from_direction.length_squared() < 0.0001:
		return
	_spawn_hit_sparks(from_direction)
	_play_hit_white_flash()
	var away: Vector2 = from_direction.normalized()
	_player_hit_knockback += away * player_melee_knockback_peak * knockback_scale
	if damage > 0.0:
		_health -= damage
		if _health <= 0.0:
			_start_death()


## Animación provisional: tween de la escala actual a 0 y luego `queue_free`.
## Durante la muerte: sin AI, sin colisiones y sin recibir nuevos golpes.
func _start_death() -> void:
	if _dying:
		return
	_dying = true
	_notify_game_player_kill()
	_is_selected = false
	queue_redraw()
	velocity = Vector2.ZERO
	_player_hit_knockback = Vector2.ZERO
	_clear_trail()
	set_physics_process(false)
	# Desactiva colisiones para que no bloquee ni reciba más impactos durante la animación.
	collision_layer = 0
	collision_mask = 0
	# Quita el ClickArea de su capa para que no sea seleccionable mientras se encoge.
	var click_area := get_node_or_null(^"ClickArea") as Area2D
	if click_area != null:
		click_area.collision_layer = 0
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_spawn_xp_drops()
	_play_death_outro()


func _notify_game_player_kill() -> void:
	var game := get_tree().get_first_node_in_group("game") as Node
	if game != null and game.has_method("on_enemy_killed_by_player"):
		game.call("on_enemy_killed_by_player")


## Por defecto: encoge con tween. Subclases (p. ej. mosquito) pueden anularlo.
func _play_death_outro() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(self, "scale", Vector2.ZERO, death_scale_duration)
	_death_tween.tween_callback(queue_free)


## Al morir, suelta gemas azules neón (XP). Se agregan al mismo
## padre que el enemigo (típicamente `Enemies`) para convivir con el resto de
## entidades de mundo; al recogerlas incrementan `RunResources.experience`.
func _spawn_xp_drops() -> void:
	if not drops_xp_on_death:
		return
	if xp_pickup_scene == null:
		return
	var parent_n: Node = get_parent()
	if parent_n == null:
		return
	var lo: int = maxi(xp_drops_min, 0)
	var hi: int = maxi(xp_drops_max, lo)
	var count: int = randi_range(lo, hi)
	for _i in count:
		var pickup: Node2D = xp_pickup_scene.instantiate() as Node2D
		if pickup == null:
			continue
		var spread := Vector2(
			randf_range(-xp_drop_spread_x, xp_drop_spread_x),
			randf_range(-xp_drop_spread_y, xp_drop_spread_y)
		)
		pickup.global_position = global_position + spread
		parent_n.add_child(pickup)


## Chispas en cono siguiendo el empuje (salen despedidas hacia donde el enemigo es empujado).
func _spawn_hit_sparks(from_direction: Vector2) -> void:
	if _hit_particles == null:
		return
	if from_direction.length_squared() < 0.0001:
		return
	var emit_dir: Vector2 = from_direction.normalized()
	_hit_particles.global_rotation = emit_dir.angle()
	_hit_particles.direction = Vector2(1.0, 0.0)
	_hit_particles.restart()
	_hit_particles.emitting = true


## Máscara blanca con glow HDR: sube instantáneo al pico y decae con ease-out.
## Se pinta en `_draw` por encima del cuerpo; los valores HDR >1 activan bloom.
func _play_hit_white_flash() -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_set_flash_intensity(1.0)
	_hit_flash_tween = create_tween()
	# EASE_IN: el brillo se mantiene cerca del pico durante la mayor parte del
	# tween y cae rápido al final, así el destello se percibe largo de verdad.
	_hit_flash_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_hit_flash_tween.tween_method(_set_flash_intensity, 1.0, 0.0, player_hit_flash_duration)


func _set_flash_intensity(v: float) -> void:
	_flash_intensity = v
	queue_redraw()
	_sync_hit_flash_visual(v)


## Destello de golpe en el sprite u otro canal (por defecto sólo el círculo en `_draw`).
func _sync_hit_flash_visual(_intensity: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_refresh_player()

	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	match _state:
		State.CHASE:
			_tick_chase(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.STRIKE:
			_tick_strike(delta)

	velocity += _player_hit_knockback
	move_and_slide()
	_player_hit_knockback = _player_hit_knockback.lerp(Vector2.ZERO, 1.0 - exp(-14.0 * delta))
	_update_trail(delta)
	_after_physics_step(delta)


## Hook para subclases (sprites, hitboxes custom) tras la lógica base.
func _after_physics_step(_delta: float) -> void:
	pass


func get_ai_state() -> State:
	return _state


## 0 al iniciar WINDUP, → 1 al terminar la carga (útil para VFX de ataque).
func get_attack_windup_charge_progress() -> float:
	if _state != State.WINDUP:
		return 0.0
	return 1.0 - clampf(_windup_remaining / maxf(attack_windup_s, 0.0001), 0.0, 1.0)


func get_strike_direction() -> Vector2:
	return _strike_dir


func is_strike_dash_active() -> bool:
	return _state == State.STRIKE and _dash_remaining > 0.0


func get_strike_hit_done() -> bool:
	return _strike_hit_player


## Marca que el golpe de estocada de este ciclo ya aplicó daño (p. ej. hitbox de área).
func register_strike_hit_consumed() -> void:
	_strike_hit_player = true


func _tick_chase(delta: float) -> void:
	var desired := Vector2.ZERO
	if _player != null:
		var target := _compute_target_point(_player.global_position, _player.velocity)
		var to_t := target - global_position
		if to_t.length() > 0.5:
			desired = to_t.normalized() * speed

		var sep := _compute_separation()
		if sep != Vector2.ZERO:
			desired += sep * separation_weight

		if desired.length() > speed:
			desired = desired.normalized() * speed

		var t := 1.0 - exp(-accel_smoothing * delta)
		velocity = velocity.lerp(desired, t)

		var d_player := global_position.distance_to(_player.global_position)
		if d_player <= attack_range and _cooldown_remaining <= 0.0:
			_state = State.WINDUP
			_windup_remaining = attack_windup_s
			_aim_locked = false
			velocity = Vector2.ZERO
			queue_redraw()
	else:
		var t2 := 1.0 - exp(-accel_smoothing * delta)
		velocity = velocity.lerp(Vector2.ZERO, t2)


func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_windup_remaining -= delta
	var elapsed: float = attack_windup_s - maxf(_windup_remaining, 0.0)
	var lock_deadline: float = minf(attack_aim_lock_at_s, attack_windup_s)
	if not _aim_locked and elapsed >= lock_deadline:
		_lock_strike_aim()
		_aim_locked = true

	if _windup_remaining <= 0.0:
		if not _aim_locked:
			_lock_strike_aim()
		_aim_locked = false
		_state = State.STRIKE
		_strike_remaining = attack_strike_s
		_dash_remaining = minf(attack_dash_duration_s, attack_strike_s)
		_strike_hit_player = false
		_trail_sample_acc = trail_sample_interval_s
		_clear_trail()
		queue_redraw()


func _lock_strike_aim() -> void:
	if _player != null and is_instance_valid(_player):
		var to_p := _player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_strike_dir = to_p.normalized()


func _tick_strike(delta: float) -> void:
	if _dash_remaining > 0.0:
		_dash_remaining -= delta
		velocity = _strike_dir * attack_dash_speed
	else:
		velocity = Vector2.ZERO
	_try_hit_player()
	_strike_remaining -= delta
	if _strike_remaining <= 0.0:
		_state = State.CHASE
		_dash_remaining = 0.0
		velocity = Vector2.ZERO
		_cooldown_remaining = attack_cooldown_s
		queue_redraw()


## Impacto con el jugador: chequea alcance y cono frente al enemigo. Si el
## jugador roza el cuerpo, se permite impacto sin cono (colisión directa).
func _try_hit_player() -> void:
	if _strike_hit_player:
		return
	_refresh_player()
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("take_damage"):
		return
	var to_p: Vector2 = _player.global_position - global_position
	var d: float = to_p.length()
	# Evita salir sin daño cuando los centros coinciden (solape fuerte / embestida).
	if d < 0.0001:
		to_p = _strike_dir * 1.0
		d = to_p.length()
	var blade_reach: float = radius + attack_length + player_hit_reach_pad + player_body_radius
	var body_touch: float = radius + player_body_radius + 2.0
	var is_body_touch: bool = d <= body_touch
	var is_blade_reach: bool = d <= blade_reach
	if not is_body_touch and not is_blade_reach:
		return
	var nd: Vector2 = to_p / d
	var cos_lim: float = cos(deg_to_rad(player_hit_cone_deg))
	var in_cone: bool = nd.dot(_strike_dir) >= cos_lim
	if not (is_body_touch or (is_blade_reach and in_cone)):
		return
	_strike_hit_player = true
	_player.call("take_damage", player_damage, to_p)


func _compute_target_point(p: Vector2, vp: Vector2) -> Vector2:
	if vp.length() < player_still_threshold:
		return p
	var r := p - global_position
	var vp2 := vp.length_squared()
	var s2 := speed * speed
	var a := vp2 - s2
	var b := 2.0 * r.dot(vp)
	var c := r.length_squared()
	var t: float = -1.0
	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			var cand := -c / b
			if cand > 0.0:
				t = cand
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2
	if t <= 0.0:
		t = r.length() / maxf(speed, 1.0)
	t = minf(t * _lead_bias, max_lead_time)
	return p + vp * t


func _compute_separation() -> Vector2:
	var parent := get_parent()
	if parent == null:
		return Vector2.ZERO
	var sep := Vector2.ZERO
	var count := 0
	var r2 := separation_radius * separation_radius
	for sib in parent.get_children():
		if sib == self or not is_instance_valid(sib):
			continue
		if not (sib is Node2D):
			continue
		var other := sib as Node2D
		var delta := global_position - other.global_position
		var d2 := delta.length_squared()
		if d2 > 0.0001 and d2 < r2:
			var d := sqrt(d2)
			var w: float = 1.0 - (d / separation_radius)
			sep += (delta / d) * w
			count += 1
	if count > 0:
		sep /= float(count)
	return sep


## Mantiene la estela durante el dash y la desvanece al terminar el ataque.
## Los puntos se almacenan en coordenadas globales (Line2D `top_level = true`).
func _update_trail(delta: float) -> void:
	if _trail == null:
		return
	var dashing: bool = _state == State.STRIKE and _dash_remaining > 0.0
	if dashing:
		_trail_sample_acc += delta
		if _trail_sample_acc >= trail_sample_interval_s:
			_trail_sample_acc = 0.0
			_trail.add_point(global_position)
			# Line2D dibuja del punto 0 al último; el gradiente del recurso va de
			# transparente (viejo) a opaco (reciente). Limitamos la longitud.
			while _trail.get_point_count() > trail_max_points:
				_trail.remove_point(0)
		_trail_fade_acc = 0.0
	else:
		# Sin dash: retira puntos progresivamente desde el más antiguo.
		_trail_fade_acc += delta * trail_fade_points_per_s
		while _trail_fade_acc >= 1.0 and _trail.get_point_count() > 0:
			_trail_fade_acc -= 1.0
			_trail.remove_point(0)


func _clear_trail() -> void:
	if _trail == null:
		return
	_trail.clear_points()


func _draw() -> void:
	if draws_body_circle:
		draw_circle(Vector2.ZERO, radius, body_color)

	# Flash de golpe: círculo HDR (enemigo procedural). Sprites suelen usar `_sync_hit_flash_visual`.
	if draws_hit_flash_circle and _flash_intensity > 0.001:
		var i: float = _flash_intensity
		var hdr: float = lerpf(1.0, player_hit_flash_hdr, i)
		var flash_col := Color(hdr, hdr, hdr, i)
		var base_r: float = radius if draws_body_circle else maxf(radius, 10.0)
		var r: float = base_r + player_hit_flash_radius_bump * i
		draw_circle(Vector2.ZERO, r, flash_col)

	if draws_attack_blade and _state == State.STRIKE:
		var half_b := attack_width_base * 0.5
		var half_t := attack_width_tip * 0.5
		# Estocada en el plano XY: hoja alargada en la dirección del player (como pinchar hacia adelante).
		var xf := Transform2D(_strike_dir.angle(), Vector2.ZERO)
		var poly := PackedVector2Array([
			xf * Vector2(radius, -half_b),
			xf * Vector2(radius + attack_length, -half_t),
			xf * Vector2(radius + attack_length, half_t),
			xf * Vector2(radius, half_b),
		])
		draw_colored_polygon(poly, attack_blade_color)
		# Núcleo brillante: mismo perfil pero más estrecho (≈ 50 %), HDR más alto.
		# Este polígono interior es la “máscara” que rebota el bloom y vende el neón.
		var core_b: float = half_b * 0.55
		var core_t: float = half_t * 0.55
		var core_poly := PackedVector2Array([
			xf * Vector2(radius + 0.5, -core_b),
			xf * Vector2(radius + attack_length - 0.5, -core_t),
			xf * Vector2(radius + attack_length - 0.5, core_t),
			xf * Vector2(radius + 0.5, core_b),
		])
		draw_colored_polygon(core_poly, attack_blade_core_color)
	if _is_selected:
		var hm: float = radius + selection_frame_margin
		var half_s: Vector2 = Vector2(hm, hm)
		var l: float = selection_corner_length
		var w: float = 1.8
		var t_tl := Vector2(-half_s.x, -half_s.y)
		var t_tr := Vector2( half_s.x, -half_s.y)
		var t_br := Vector2( half_s.x,  half_s.y)
		var t_bl := Vector2(-half_s.x,  half_s.y)
		draw_line(t_tl, t_tl + Vector2(l, 0), selection_color, w, true)
		draw_line(t_tl, t_tl + Vector2(0, l), selection_color, w, true)
		draw_line(t_tr, t_tr + Vector2(-l, 0), selection_color, w, true)
		draw_line(t_tr, t_tr + Vector2(0, l), selection_color, w, true)
		draw_line(t_br, t_br + Vector2(-l, 0), selection_color, w, true)
		draw_line(t_br, t_br + Vector2(0, -l), selection_color, w, true)
		draw_line(t_bl, t_bl + Vector2(l, 0), selection_color, w, true)
		draw_line(t_bl, t_bl + Vector2(0, -l), selection_color, w, true)
