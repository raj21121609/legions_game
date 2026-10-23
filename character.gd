extends RigidBody3D

@export_group("Camera Settings")
@export var third_person: bool = true
@export var camera_distance: float = 3.5
@export var camera_height: float = 1.4
@export var sensitivity: float = 0.15

@export_group("Dani Movement (Tuned Values)")
@export var move_speed: float = 45.0
@export var max_speed: float = 9.0
@export var counter_movement: float = 0.25 ## Higher = stops quicker and crisper
@export var acceleration: float = 12.0
@export var jump_force: float = 11.0

@export_group("Juicy Spring Wobble & Lean")
@export var tilt_amount: float = 6.0 ## How far the body leans into movement/turns
@export var spring_stiffness: float = 110.0 ## Higher = snappier wobble
@export var spring_damping: float = 8.5 ## Controls how fast wobble settles
@export var squash_stretch_amount: float = 0.08 ## Squeezes character on jumps and landings

# Internal nodes
var orientation: Node3D
var camera_pivot: SpringArm3D
var player_cam: Camera3D
var visual_root: Node3D
var skeleton: Skeleton3D
var base_visual_scale: Vector3 = Vector3.ONE

# Movement state
var yaw: float = 0.0
var pitch: float = -15.0
var facing_yaw: float = 0.0
var grounded: bool = false
var ready_to_jump: bool = true

# Spring wobble state
var prev_velocity: Vector3 = Vector3.ZERO
var wobble_rot: Vector3 = Vector3.ZERO
var wobble_vel: Vector3 = Vector3.ZERO
var squash_vel: float = 0.0
var squash_current: float = 0.0


func _ready() -> void:
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	gravity_scale = 2.2
	
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.0
	physics_material_override = mat
	
	orientation = Node3D.new()
	orientation.name = "Orientation"
	add_child(orientation)
	
	# Keep any default animation playing if present, or let it rest naturally
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		skeleton = skeletons[0] as Skeleton3D
		var p: Node = skeleton
		while p.get_parent() and p.get_parent() != self:
			p = p.get_parent()
		visual_root = p as Node3D
		base_visual_scale = visual_root.scale
		facing_yaw = visual_root.rotation.y
	
	setup_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func setup_camera() -> void:
	camera_pivot = SpringArm3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, camera_height, 0.0)
	camera_pivot.spring_length = camera_distance if third_person else 0.0
	camera_pivot.add_excluded_object(get_rid())
	add_child(camera_pivot)
	
	player_cam = Camera3D.new()
	player_cam.name = "FollowCamera"
	camera_pivot.add_child(player_cam)
	player_cam.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch = clamp(pitch - event.relative.y * sensitivity, -75.0, 75.0)
		orientation.rotation_degrees.y = yaw
		camera_pivot.rotation_degrees = Vector3(pitch, yaw, 0.0)
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE 
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED 
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	check_ground_raycast()
	
	var input_x: float = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var input_y: float = float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	var raw_input := Vector2(input_x, input_y).limit_length(1.0)
	var jumping: bool = Input.is_key_pressed(KEY_SPACE)
	
	var forward_dir: Vector3 = -orientation.global_transform.basis.z
	var right_dir: Vector3 = orientation.global_transform.basis.x
	var desired_dir: Vector3 = (forward_dir * raw_input.y + right_dir * raw_input.x)
	var horiz_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	
	# Smoothly turn character toward movement direction
	if raw_input.length() > 0.1:
		var target_facing := atan2(desired_dir.x, desired_dir.z)
		facing_yaw = lerp_angle(facing_yaw, target_facing, delta * 12.0)
	
	# Dani-style movement force
	var air_multiplier: float = 1.0 if grounded else 0.5
	apply_central_force(desired_dir * move_speed * air_multiplier)
	
	# Counter-movement damping (prevents endless sliding, makes stops feel crisp)
	if grounded:
		apply_central_force(-horiz_vel * move_speed * counter_movement)
	
	# Jump
	if grounded and jumping and ready_to_jump:
		ready_to_jump = false
		linear_velocity.y = max(linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * jump_force)
		squash_vel -= 15.0 # Squash-stretch jump pop
		get_tree().create_timer(0.25).timeout.connect(func(): ready_to_jump = true)
	
	# Clamp max horizontal speed
	if horiz_vel.length() > max_speed:
		var clamped := horiz_vel.normalized() * max_speed
		linear_velocity.x = clamped.x
		linear_velocity.z = clamped.z


func _process(delta: float) -> void:
	update_juicy_wobble(delta)


func update_juicy_wobble(delta: float) -> void:
	if not visual_root:
		return
		
	# 1. Smoothly rotate character visual toward movement facing direction
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, facing_yaw, delta * 14.0)
	
	# 2. Calculate acceleration for spring-damper body lean
	var accel: Vector3 = (linear_velocity - prev_velocity) / max(delta, 0.001)
	prev_velocity = linear_velocity
	
	var char_basis := Basis.from_euler(Vector3(0.0, visual_root.rotation.y, 0.0))
	var local_accel: Vector3 = char_basis.inverse() * accel
	
	# Target lean based on acceleration (tilts forward when speeding up, backward when stopping)
	var target_wobble := Vector3(
		clamp(-local_accel.z * 0.06, -1.2, 1.2) * tilt_amount,
		0.0,
		clamp(local_accel.x * 0.06, -1.2, 1.2) * tilt_amount
	)
	
	# Spring-damper physics formula for organic bounciness
	var spring_force: Vector3 = (target_wobble - wobble_rot) * spring_stiffness
	wobble_vel += spring_force * delta
	wobble_vel *= exp(-spring_damping * delta)
	wobble_rot += wobble_vel * delta
	
	# Apply tilt to visual container
	visual_root.rotation.x = deg_to_rad(wobble_rot.x)
	visual_root.rotation.z = deg_to_rad(wobble_rot.z)
	
	# 3. Squash and stretch on jumps and high velocities
	var target_squash: float = clamp(-local_accel.y * 0.002, -0.15, 0.2)
	squash_vel += (target_squash - squash_current) * 120.0 * delta
	squash_vel *= exp(-8.0 * delta)
	squash_current += squash_vel * delta
	
	visual_root.scale = Vector3(
		base_visual_scale.x * (1.0 - squash_current * 0.5),
		base_visual_scale.y * (1.0 + squash_current),
		base_visual_scale.z * (1.0 - squash_current * 0.5)
	)


func check_ground_raycast() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.5, 0.0),
		global_position + Vector3(0.0, -1.4, 0.0)
	)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	grounded = not hit.is_empty()
