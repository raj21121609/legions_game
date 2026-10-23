extends RigidBody3D

@export_group("Camera Settings")
@export var third_person: bool = true ## Toggle between 3rd-person (see wobble) and 1st-person
@export var camera_distance: float = 3.5
@export var camera_height: float = 1.5
@export var sensitivity: float = 0.18

@export_group("Movement Settings")
@export var move_speed: float = 45.0
@export var max_speed: float = 10.0
@export var counter_movement: float = 0.22
@export var jump_force: float = 10.0
@export var slide_force: float = 14.0

@export_group("Wobble & Procedural Animation")
@export var enable_wobble: bool = true
@export var arm_down_angle: float = 72.0 ## Lowers arms from T-pose
@export var wobble_stiffness: float = 110.0
@export var wobble_damping: float = 7.5
@export var walk_cycle_speed: float = 10.0
@export var limb_swing_amount: float = 35.0

# Internal auto-managed nodes
var orientation: Node3D
var camera_pivot: SpringArm3D
var player_cam: Camera3D
var visual_root: Node3D
var skeleton: Skeleton3D

# State variables
var yaw: float = 0.0
var pitch: float = -15.0
var grounded: bool = false
var crouching: bool = false
var ready_to_jump: bool = true
var walk_time: float = 0.0

# Wobble physics state
var prev_velocity: Vector3 = Vector3.ZERO
var wobble_rot: Vector3 = Vector3.ZERO
var wobble_vel: Vector3 = Vector3.ZERO

# Cached Mixamo bone indices
var b_spine: int = -1
var b_head: int = -1
var b_l_arm: int = -1
var b_r_arm: int = -1
var b_l_leg: int = -1
var b_r_leg: int = -1


func _ready() -> void:
	# 1. Lock physics capsule from tipping over
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	gravity_scale = 2.0
	
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.0
	physics_material_override = mat
	
	# 2. Auto-create Orientation node
	orientation = Node3D.new()
	orientation.name = "Orientation"
	add_child(orientation)
	
	# 3. Auto-find character visual & Skeleton3D
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		skeleton = skeletons[0] as Skeleton3D
		# Find the top-level child of RigidBody3D that holds the model
		var p: Node = skeleton
		while p.get_parent() and p.get_parent() != self:
			p = p.get_parent()
		visual_root = p as Node3D
		cache_mixamo_bones()
	
	# 4. Auto-setup following Camera3D so it NEVER stays behind on the map
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


func cache_mixamo_bones() -> void:
	if not skeleton:
		return
	b_spine = find_bone_fuzzy(["mixamorig:Spine1", "mixamorig:Spine", "Spine"])
	b_head = find_bone_fuzzy(["mixamorig:Head", "Head"])
	b_l_arm = find_bone_fuzzy(["mixamorig:LeftArm", "LeftArm", "LeftUpperArm"])
	b_r_arm = find_bone_fuzzy(["mixamorig:RightArm", "RightArm", "RightUpperArm"])
	b_l_leg = find_bone_fuzzy(["mixamorig:LeftUpLeg", "LeftUpLeg", "LeftThigh"])
	b_r_leg = find_bone_fuzzy(["mixamorig:RightUpLeg", "RightUpLeg", "RightThigh"])


func find_bone_fuzzy(names: Array[String]) -> int:
	for n in names:
		var idx := skeleton.find_bone(n)
		if idx != -1:
			return idx
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch = clamp(pitch - event.relative.y * sensitivity, -80.0, 80.0)
		
		orientation.rotation_degrees.y = yaw
		camera_pivot.rotation_degrees = Vector3(pitch, yaw, 0.0)
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE 
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED 
			else Input.MOUSE_MODE_CAPTURED
		)


func _process(delta: float) -> void:
	if enable_wobble:
		update_wobble_and_pose(delta)


func _physics_process(delta: float) -> void:
	check_ground_raycast()
	
	var input_x: float = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var input_y: float = float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	var jumping: bool = Input.is_key_pressed(KEY_SPACE)
	crouching = Input.is_key_pressed(KEY_CTRL)
	
	# Scale visual on crouch
	if visual_root:
		var target_scale := Vector3(1.0, 0.6, 1.0) if crouching else Vector3.ONE
		visual_root.scale = visual_root.scale.lerp(target_scale, delta * 12.0)
	
	# Find velocity relative to look direction
	var forward_dir: Vector3 = -orientation.global_transform.basis.z
	var right_dir: Vector3 = orientation.global_transform.basis.x
	var horiz_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var mag := Vector2(horiz_vel.dot(right_dir), horiz_vel.dot(forward_dir))
	
	# Apply Dani-style counter-movement so player stops cleanly
	if grounded:
		if abs(input_x) < 0.05 or (mag.x < 0 and input_x > 0) or (mag.x > 0 and input_x < 0):
			apply_central_force(-right_dir * mag.x * move_speed * counter_movement)
		if abs(input_y) < 0.05 or (mag.y < 0 and input_y > 0) or (mag.y > 0 and input_y < 0):
			apply_central_force(-forward_dir * mag.y * move_speed * counter_movement)
	
	# Jump
	if grounded and jumping and ready_to_jump:
		ready_to_jump = false
		linear_velocity.y = max(linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * jump_force)
		wobble_vel.x -= 12.0
		get_tree().create_timer(0.25).timeout.connect(func(): ready_to_jump = true)
	
	# Cancel input above max speed
	if input_x > 0 and mag.x > max_speed: input_x = 0.0
	if input_x < 0 and mag.x < -max_speed: input_x = 0.0
	if input_y > 0 and mag.y > max_speed: input_y = 0.0
	if input_y < 0 and mag.y < -max_speed: input_y = 0.0
	
	var air_mult: float = 1.0 if grounded else 0.45
	var move_dir: Vector3 = (forward_dir * input_y + right_dir * input_x).normalized()
	apply_central_force(move_dir * move_speed * air_mult)
	
	# Clamp max horizontal speed
	if horiz_vel.length() > max_speed:
		var clamped := horiz_vel.normalized() * max_speed
		linear_velocity.x = clamped.x
		linear_velocity.z = clamped.z


func check_ground_raycast() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 0.5, 0.0),
		global_position + Vector3(0.0, -1.35, 0.0)
	)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	grounded = not hit.is_empty()


func update_wobble_and_pose(delta: float) -> void:
	if not visual_root:
		return
		
	var horiz_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var speed: float = horiz_vel.length()
	
	# Rotate character mesh toward movement direction (or camera direction if idle)
	if speed > 0.4:
		var target_yaw := atan2(horiz_vel.x, horiz_vel.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, delta * 10.0)
	
	# Spring-damper physics for body wobble
	var accel: Vector3 = (linear_velocity - prev_velocity) / max(delta, 0.001)
	prev_velocity = linear_velocity
	var local_accel: Vector3 = visual_root.global_transform.basis.inverse() * accel
	
	var target_wobble := Vector3(
		clamp(local_accel.z * 0.04, -1.5, 1.5),
		0.0,
		clamp(-local_accel.x * 0.04, -1.5, 1.5)
	)
	
	var spring_force: Vector3 = (target_wobble - wobble_rot) * wobble_stiffness
	wobble_vel += spring_force * delta
	wobble_vel *= exp(-wobble_damping * delta)
	wobble_rot += wobble_vel * delta
	
	visual_root.rotation.x = deg_to_rad(wobble_rot.x * 12.0)
	visual_root.rotation.z = deg_to_rad(wobble_rot.z * 12.0)
	
	# Procedural Mixamo Bone Animation (Fixes T-Pose & adds wobbly walk cycle)
	if not skeleton:
		return
		
	var move_factor: float = clamp(speed / max_speed, 0.0, 1.0)
	walk_time += delta * walk_cycle_speed * max(move_factor, 0.15)
	var swing: float = sin(walk_time) * limb_swing_amount * move_factor
	var wobble_sway: float = wobble_rot.z * 18.0
	
	# Lower arms out of T-pose and swing them with movement + wobble
	if b_l_arm != -1:
		rotate_bone_char_space(b_l_arm, Vector3(swing, 0.0, -arm_down_angle + wobble_sway))
	if b_r_arm != -1:
		rotate_bone_char_space(b_r_arm, Vector3(-swing, 0.0, arm_down_angle + wobble_sway))
		
	# Swing legs when walking/running
	if b_l_leg != -1:
		rotate_bone_char_space(b_l_leg, Vector3(-swing * 1.1, 0.0, 0.0))
	if b_r_leg != -1:
		rotate_bone_char_space(b_r_leg, Vector3(swing * 1.1, 0.0, 0.0))
		
	# Wobble spine and head
	if b_spine != -1:
		rotate_bone_char_space(b_spine, Vector3(wobble_rot.x * 15.0, 0.0, wobble_rot.z * 15.0))
	if b_head != -1:
		rotate_bone_char_space(b_head, Vector3(-wobble_rot.x * 10.0, 0.0, -wobble_rot.z * 10.0))


## Rotates a bone in Character Space regardless of Blender's local bone roll
func rotate_bone_char_space(bone_idx: int, euler_deg: Vector3) -> void:
	var rest_local: Transform3D = skeleton.get_bone_rest(bone_idx)
	var rest_global_basis: Basis = skeleton.get_bone_global_rest(bone_idx).basis
	var char_rot := Basis.from_euler(Vector3(
		deg_to_rad(euler_deg.x),
		deg_to_rad(euler_deg.y),
		deg_to_rad(euler_deg.z)
	))
	var new_pose_basis: Basis = rest_local.basis * rest_global_basis.inverse() * char_rot * rest_global_basis
	skeleton.set_bone_pose_rotation(bone_idx, new_pose_basis.get_rotation_quaternion())
