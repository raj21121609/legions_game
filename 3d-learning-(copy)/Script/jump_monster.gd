extends Node3D

# --- EXACT ANIMATION NAMES FROM YOUR LIBRARY ---
const ANIM_ATTACK: StringName = &"newLib/j_bite"
const ANIM_WALK: StringName   = &"newLib/j_walk"
const ANIM_DEATH: StringName  = &"newLib/j_death"
const ANIM_IDLE: StringName   = &"newLib/j_idle"
const ANIM_JUMP: StringName   = &"newLib/j_jump"
const ANIM_RUN: StringName    = &"newLib/j_run"

enum State { IDLE, WALK, RUN, JUMP, ATTACK, DEATH }

@export_group("Nodes")
@export var anim_player: AnimationPlayer
@export var assigned_area: Node3D
@export var target_player: Node3D

@export_group("Territory & Island Safety")
## How far the crab patrols when idle/walking if no Assigned Area is set.
@export var fallback_patrol_radius: float = 10.0
## How far from its spawn point the crab is allowed to chase the player.
@export var max_chase_radius: float = 18.0
@export var ledge_check_distance: float = 1.0
@export var max_safe_drop_height: float = 2.0
@export var boundary_margin: float = 0.5

@export_group("Movement & Actions")
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var rotation_speed: float = 8.0
@export var jump_velocity: float = 4.0
@export var jump_chance_on_move: float = 0.25
## If your crab model faces backwards while moving, set this to 180.0 (or 90.0 / -90.0 if sideways).
@export var model_facing_offset_degrees: float = 180.0

@export_group("Combat")
@export var max_health: float = 100.0
@export var chase_range: float = 10.0
@export var attack_range: float = 2.2
@export var attack_damage: float = 15.0
@export var attack_duration: float = 0.9
@export var attack_cooldown: float = 1.2

var current_state: State = State.IDLE
var health: float = 100.0
var spawn_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var is_grounded: bool = true

var state_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var has_dealt_attack_damage: bool = false

var _zone_shape_node: CollisionShape3D = null
var _ledge_ray: RayCast3D = null
var _floor_ray: RayCast3D = null
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

func _ready() -> void:
	health = max_health
	spawn_position = global_position
	target_position = spawn_position
	
	if not anim_player:
		anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		_configure_animation_loops()
	
	_find_player()
	_resolve_assigned_area()
	_setup_raycasts()
	_enter_state(State.IDLE)

func _physics_process(delta: float) -> void:
	_apply_floor_and_gravity(delta)
	
	if current_state == State.DEATH:
		global_position.y += velocity.y * delta
		return

	# Re-check for player if not found yet
	if not is_instance_valid(target_player):
		_find_player()

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta

	var can_engage_player: bool = false
	var dist_to_player: float = INF
	
	if is_instance_valid(target_player):
		dist_to_player = _horizontal_distance_to(target_player.global_position)
		if dist_to_player <= chase_range and _is_point_allowed_for_chase(target_player.global_position):
			can_engage_player = true

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
			state_timer -= delta
			
			if can_engage_player:
				if dist_to_player <= attack_range and attack_cooldown_timer <= 0.0:
					_enter_state(State.ATTACK)
				elif dist_to_player > attack_range * 0.8:
					_enter_state(State.RUN)
				else:
					_face_direction(global_position.direction_to(target_player.global_position), delta)
			elif state_timer <= 0.0:
				target_position = get_random_point_in_area()
				if randf() < jump_chance_on_move and is_grounded:
					_enter_state(State.JUMP)
				else:
					_enter_state(State.WALK)

		State.WALK:
			state_timer -= delta
			if can_engage_player:
				_enter_state(State.RUN)
			else:
				var moved: bool = _move_toward_point(target_position, walk_speed, delta, false)
				if not moved or _horizontal_distance_to(target_position) < 0.7 or state_timer <= 0.0:
					_enter_state(State.IDLE)

		
		State.RUN:
			state_timer -= delta

			if can_engage_player:
				target_position = target_player.global_position

				# Occasionally jump while chasing the player
				if is_grounded and randf() < 0.35 * delta:
					_enter_state(State.JUMP)
				elif dist_to_player <= attack_range:
					velocity.x = 0.0
					velocity.z = 0.0

					if attack_cooldown_timer <= 0.0:
						_enter_state(State.ATTACK)
					else:
						_enter_state(State.IDLE)
				else:
					var moved_chase: bool = _move_toward_point(
						target_position, run_speed, delta, true
					)

					if not moved_chase:
						_enter_state(State.IDLE)

			else:
				var moved_patrol: bool = _move_toward_point(
					target_position, run_speed, delta, false
				)

				if not moved_patrol or _horizontal_distance_to(target_position) < 0.7 or state_timer <= 0.0:
					_enter_state(State.IDLE)


		State.JUMP:
			state_timer -= delta
			_move_toward_point(target_position, walk_speed, delta, false)
			if state_timer <= 0.0 and is_grounded:
				_enter_state(State.IDLE)

		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0
			state_timer -= delta
			
			if is_instance_valid(target_player):
				_face_direction(global_position.direction_to(target_player.global_position), delta)
				
				# Deal damage halfway through the attack animation
				if not has_dealt_attack_damage and state_timer <= (attack_duration * 0.5):
					has_dealt_attack_damage = true
					if _horizontal_distance_to(target_player.global_position) <= (attack_range + 0.6):
						if target_player.has_method("take_damage"):
							target_player.call("take_damage", attack_damage)
							
			if state_timer <= 0.0:
				_enter_state(State.IDLE)

	global_position += velocity * delta

# --- FIND PLAYER AUTOMATICALLY ---
func _find_player() -> void:
	target_player = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(target_player) and get_tree().current_scene:
		# Fallback: find any CharacterBody3D in the scene if group wasn't set
		var bodies: Array[Node] = get_tree().current_scene.find_children("*", "CharacterBody3D", true, false)
		for b: Node in bodies:
			if b != self:
				target_player = b as Node3D
				break

# --- FLOOR SNAPPING & GRAVITY ---
func _apply_floor_and_gravity(delta: float) -> void:
	_floor_ray.global_position = global_position + Vector3(0.0, 1.2, 0.0)
	_floor_ray.force_raycast_update()
	
	if _floor_ray.is_colliding():
		var floor_y: float = _floor_ray.get_collision_point().y
		if velocity.y <= 0.0 and global_position.y <= floor_y + 0.35:
			global_position.y = move_toward(global_position.y, floor_y, 12.0 * delta)
			velocity.y = 0.0
			is_grounded = true
			return
	else:
		# If the floor mesh doesn't have a physics collider setup yet, keep crab at spawn height so it never falls into the void
		if global_position.y <= spawn_position.y and velocity.y <= 0.0:
			global_position.y = spawn_position.y
			velocity.y = 0.0
			is_grounded = true
			return
			
	is_grounded = false
	velocity.y -= _gravity * delta

# --- STATE TRANSITIONS & ANIMATIONS ---
func _enter_state(new_state: State) -> void:
	if current_state == State.DEATH:
		return
	current_state = new_state
	
	match current_state:
		State.IDLE:
			state_timer = randf_range(0.8, 2.0)
			_play_anim(ANIM_IDLE)
			
		State.WALK:
			state_timer = randf_range(3.0, 5.5)
			_play_anim(ANIM_WALK)
			
		State.RUN:
			state_timer = randf_range(2.5, 4.5)
			_play_anim(ANIM_RUN)
			
		State.JUMP:
			state_timer = 0.85
			if is_grounded:
				velocity.y = jump_velocity
				is_grounded = false
			_play_anim(ANIM_JUMP)
			
		State.ATTACK:
			state_timer = attack_duration
			attack_cooldown_timer = attack_cooldown
			has_dealt_attack_damage = false
			_play_anim(ANIM_ATTACK)
			
		State.DEATH:
			velocity = Vector3.ZERO
			_play_anim(ANIM_DEATH)

func _play_anim(anim_name: StringName) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		if anim_player.current_animation != anim_name or not anim_player.is_playing():
			anim_player.play(anim_name)

func _configure_animation_loops() -> void:
	var loop_anims: Array[StringName] = [ANIM_IDLE, ANIM_WALK, ANIM_RUN]
	for loop_anim: StringName in loop_anims:
		if anim_player.has_animation(loop_anim):
			var anim: Animation = anim_player.get_animation(loop_anim)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR

# --- MOVEMENT, LEDGE SAFETY & AREA CONFINEMENT ---
func _move_toward_point(destination: Vector3, speed: float, delta: float, is_chasing: bool) -> bool:
	var dir: Vector3 = destination - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return false
	dir = dir.normalized()
	
	# Only enforce raycast cliff check if the floor actually has physics collision
	var floor_has_collision: bool = _floor_ray.is_colliding()
	if floor_has_collision:
		_ledge_ray.global_position = global_position + Vector3(0.0, 1.0, 0.0) + (dir * ledge_check_distance)
		_ledge_ray.force_raycast_update()
		if is_grounded and not _ledge_ray.is_colliding():
			# Reached a floating island cliff edge! Turn back toward safe center.
			velocity.x = 0.0
			velocity.z = 0.0
			target_position = _get_area_center()
			return false
	
	var next_step: Vector3 = global_position + dir * (speed * delta * 3.0)
	var allowed: bool = _is_point_allowed_for_chase(next_step) if is_chasing else is_point_inside_area(next_step)
	
	if not allowed:
		# Walk back toward the center if currently outside the boundary
		var to_center: Vector3 = _get_area_center() - global_position
		to_center.y = 0.0
		if to_center.length_squared() > 0.25:
			dir = to_center.normalized()
			target_position = _get_area_center()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			return false
		
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face_direction(dir, delta)
	return true

func _face_direction(dir: Vector3, delta: float) -> void:
	var flat_dir: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat_dir.length_squared() > 0.001:
		var target_yaw: float = atan2(-flat_dir.x, -flat_dir.z) + deg_to_rad(model_facing_offset_degrees)
		rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)

func _get_shape_radius(shape: Shape3D) -> float:
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	elif shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	elif shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	return -1.0

func _is_point_allowed_for_chase(world_point: Vector3) -> bool:
	if is_instance_valid(_zone_shape_node) and _zone_shape_node.shape:
		return is_point_inside_area(world_point)
	var center: Vector3 = _get_area_center()
	return Vector2(world_point.x - center.x, world_point.z - center.z).length() <= max_chase_radius

func is_point_inside_area(world_point: Vector3) -> bool:
	if is_instance_valid(_zone_shape_node) and _zone_shape_node.shape:
		var local_pt: Vector3 = _zone_shape_node.to_local(world_point)
		var shape: Shape3D = _zone_shape_node.shape
		
		if shape is BoxShape3D:
			var box: BoxShape3D = shape as BoxShape3D
			var half_x: float = maxf(0.2, (box.size.x * 0.5) - boundary_margin)
			var half_z: float = maxf(0.2, (box.size.z * 0.5) - boundary_margin)
			return absf(local_pt.x) <= half_x and absf(local_pt.z) <= half_z
		else:
			var radius: float = _get_shape_radius(shape)
			if radius > 0.0:
				var r: float = maxf(0.2, radius - boundary_margin)
				return Vector2(local_pt.x, local_pt.z).length() <= r

	var center: Vector3 = _get_area_center()
	var max_r: float = maxf(1.0, fallback_patrol_radius - boundary_margin)
	return Vector2(world_point.x - center.x, world_point.z - center.z).length() <= max_r

func get_random_point_in_area() -> Vector3:
	if is_instance_valid(_zone_shape_node) and _zone_shape_node.shape:
		var shape: Shape3D = _zone_shape_node.shape
		if shape is BoxShape3D:
			var box: BoxShape3D = shape as BoxShape3D
			var half_x: float = maxf(0.2, (box.size.x * 0.5) - boundary_margin)
			var half_z: float = maxf(0.2, (box.size.z * 0.5) - boundary_margin)
			var local_rand: Vector3 = Vector3(randf_range(-half_x, half_x), 0.0, randf_range(-half_z, half_z))
			return _zone_shape_node.to_global(local_rand)
		else:
			var radius: float = _get_shape_radius(shape)
			if radius > 0.0:
				var r: float = sqrt(randf()) * maxf(0.2, radius - boundary_margin)
				var angle: float = randf() * TAU
				var local_rand: Vector3 = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
				return _zone_shape_node.to_global(local_rand)

	var center: Vector3 = _get_area_center()
	var r_fallback: float = sqrt(randf()) * maxf(1.0, fallback_patrol_radius - boundary_margin)
	var angle_fallback: float = randf() * TAU
	return center + Vector3(cos(angle_fallback) * r_fallback, 0.0, sin(angle_fallback) * r_fallback)

func _get_area_center() -> Vector3:
	if is_instance_valid(_zone_shape_node):
		return _zone_shape_node.global_position
	elif is_instance_valid(assigned_area):
		return assigned_area.global_position
	return spawn_position

func _horizontal_distance_to(point: Vector3) -> float:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length()

func _resolve_assigned_area() -> void:
	if not assigned_area:
		return
	if assigned_area is CollisionShape3D:
		_zone_shape_node = assigned_area as CollisionShape3D
	else:
		var children: Array[Node] = assigned_area.find_children("*", "CollisionShape3D", true, false)
		for child: Node in children:
			_zone_shape_node = child as CollisionShape3D
			break

func _setup_raycasts() -> void:
	_floor_ray = RayCast3D.new()
	_floor_ray.name = "FloorDetectorRay"
	_floor_ray.target_position = Vector3(0.0, -4.0, 0.0)
	_floor_ray.enabled = true
	add_child(_floor_ray)
	
	_ledge_ray = RayCast3D.new()
	_ledge_ray.name = "LedgeDetectorRay"
	_ledge_ray.target_position = Vector3(0.0, -(max_safe_drop_height + 1.2), 0.0)
	_ledge_ray.enabled = true
	add_child(_ledge_ray)
	
	var bodies: Array[Node] = find_children("*", "CollisionObject3D", true, false)
	for body: Node in bodies:
		var col_obj: CollisionObject3D = body as CollisionObject3D
		if col_obj:
			_floor_ray.add_exception(col_obj)
			_ledge_ray.add_exception(col_obj)

func take_damage(amount: float) -> void:
	if current_state == State.DEATH:
		return
	health -= amount
	if health <= 0.0:
		_enter_state(State.DEATH)
	else:
		_enter_state(State.RUN)
