extends CharacterBody3D

class_name ScooterController

## Player-drivable scooter.
## F mounts/dismounts when the player is inside InteractionArea.
## W/S accelerate and brake/reverse; A/D steer; Space handbrakes.

@export_group("Movement")
@export var max_speed: float = 24.0
@export var acceleration: float = 12.0
@export var brake_force: float = 16.0
@export var handbrake_force: float = 28.0
@export var friction: float = 3.5
@export var reverse_speed: float = 7.0

@export_group("Steering")
@export var steer_speed_low: float = 3.0
@export var steer_speed_high: float = 1.2
@export var tilt_amount: float = 18.0
@export var tilt_lerp_speed: float = 7.0
@export var handlebar_turn_max: float = 22.0
@export var front_wheel_steer_max: float = 14.0
@export var handlebar_model_offset: Vector3 = Vector3(0.0, -0.60, -0.40)
@export var handlebar_pivot_position: Vector3 = Vector3(0.0, 1.35, -0.85)

@export_group("Physics")
@export var gravity_force: float = 24.0
@export var ground_snap: float = 0.6
@export var traction: float = 11.0
@export var air_control: float = 0.25
@export var suspension_bob: float = 0.035
@export var suspension_speed: float = 12.0

@export_group("Rider")
@export var rider_model_yaw_offset: float = PI

@export_group("Interaction")
@export var interact_action: StringName = &"scooter_interact"
@export var mount_offset: Vector3 = Vector3(0.0, 0.85, 0.2)

var is_mounted: bool = false
var current_speed: float = 0.0
var previous_speed: float = 0.0
var gravity_velocity: float = 0.0
var is_braking: bool = false

var player_ref: PlayerCharacter
var nearby_player: PlayerCharacter
var scooter_visual: Node3D
var front_wheel: Node3D
var rear_wheel: Node3D
var handlebar_node: Node3D
var handlebar_pivot: Node3D
var front_wheel_steer_pivot: Node3D
var visual_base_position: Vector3 = Vector3.ZERO
var exhaust_particles: GPUParticles3D
var dust_particles: GPUParticles3D
var skid_particles: GPUParticles3D

@onready var interaction_area: Area3D = get_node_or_null("InteractionArea") as Area3D
@onready var mount_point: Marker3D = get_node_or_null("MountPoint") as Marker3D

var forward_action: StringName = &"scooter_forward"
var backward_action: StringName = &"scooter_backward"
var steer_left_action: StringName = &"scooter_steer_left"
var steer_right_action: StringName = &"scooter_steer_right"
var handbrake_action: StringName = &"scooter_handbrake"

var hud_layer: CanvasLayer
var prompt_panel: PanelContainer
var dashboard_panel: PanelContainer
var speed_label: Label
var status_label: Label

signal player_mounted(player: CharacterBody3D)
signal player_dismounted(player: CharacterBody3D)


func _ready() -> void:
	# The root CharacterBody3D owns movement and collision. The imported model's
	# StaticBody3D children must not also participate in physics.
	collision_layer = 4
	collision_mask = 1
	_disable_imported_colliders()
	_find_visual_parts()
	_setup_handlebar_pivot()
	_setup_front_wheel_pivot()
	_setup_particles()
	_register_input_actions()
	_setup_hud()

	if interaction_area != null:
		interaction_area.body_entered.connect(_on_body_entered_interaction)
		interaction_area.body_exited.connect(_on_body_exited_interaction)


func _disable_imported_colliders() -> void:
	for child: Node in find_children("*", "StaticBody3D", true, false):
		var static_body: StaticBody3D = child as StaticBody3D
		if static_body != null:
			static_body.collision_layer = 0
			static_body.collision_mask = 0


func _find_visual_parts() -> void:
	scooter_visual = get_node_or_null("SCOOTER") as Node3D
	if scooter_visual == null:
		return

	front_wheel = scooter_visual.get_node_or_null("tyre-1") as Node3D
	rear_wheel = scooter_visual.get_node_or_null("tyre-2") as Node3D
	handlebar_node = scooter_visual.get_node_or_null("handle") as Node3D
	visual_base_position = scooter_visual.position


func _setup_handlebar_pivot() -> void:
	if handlebar_node == null:
		return

	# The imported GLB handle mesh has its geometry offset from its origin. Move
	# the mesh into the fork area, then rotate it around a real steering pivot.
	handlebar_node.position += handlebar_model_offset
	handlebar_pivot = Node3D.new()
	handlebar_pivot.name = "HandlebarSteerPivot"
	handlebar_pivot.position = handlebar_pivot_position
	add_child(handlebar_pivot)

	var handlebar_global_transform: Transform3D = handlebar_node.global_transform
	handlebar_node.reparent(handlebar_pivot, true)
	handlebar_node.global_transform = handlebar_global_transform


func _setup_front_wheel_pivot() -> void:
	if front_wheel == null:
		return

	front_wheel_steer_pivot = Node3D.new()
	front_wheel_steer_pivot.name = "FrontWheelSteerPivot"
	front_wheel_steer_pivot.global_position = front_wheel.global_position
	add_child(front_wheel_steer_pivot)

	var wheel_global_transform: Transform3D = front_wheel.global_transform
	front_wheel.reparent(front_wheel_steer_pivot, true)
	front_wheel.global_transform = wheel_global_transform


func _setup_particles() -> void:
	exhaust_particles = _create_particle_system(
		"ExhaustParticles", 36, 0.75, Color(0.16, 0.18, 0.22, 0.34), 0.05,
		Vector3(0.0, 0.72, 1.12), Vector3(0.0, 0.15, 1.0), 22.0, 0.45, 1.1)
	dust_particles = _create_particle_system(
		"RearDustParticles", 45, 0.55, Color(0.55, 0.52, 0.45, 0.42), 0.08,
		Vector3(0.0, 0.42, 1.15), Vector3(0.0, 1.0, 0.0), 32.0, 0.25, 0.9)

	# A second, darker system is used only while the rider is braking hard.
	skid_particles = _create_particle_system(
		"SkidParticles", 28, 0.4, Color(0.12, 0.12, 0.12, 0.5), 0.045,
		Vector3(0.0, 0.34, 1.18), Vector3(0.0, 0.7, 0.2), 25.0, 0.2, 0.7)

	if exhaust_particles != null:
		exhaust_particles.emitting = false
	if dust_particles != null:
		dust_particles.emitting = false
	if skid_particles != null:
		skid_particles.emitting = false


func _create_particle_system(system_name: String, particle_amount: int, particle_lifetime: float, particle_color: Color, particle_size: float, particle_position: Vector3, particle_direction: Vector3, particle_spread: float, velocity_min: float, velocity_max: float) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = system_name
	particles.amount = particle_amount
	particles.lifetime = particle_lifetime
	particles.randomness = 0.35
	particles.local_coords = true
	particles.position = particle_position

	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.direction = particle_direction
	process_material.spread = particle_spread
	process_material.initial_velocity_min = velocity_min
	process_material.initial_velocity_max = velocity_max
	process_material.gravity = Vector3(0.0, -0.8, 0.0)
	process_material.scale_min = 0.55
	process_material.scale_max = 1.2
	process_material.color = particle_color
	particles.process_material = process_material

	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = particle_size
	mesh.height = particle_size * 2.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = particle_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	particles.draw_pass_1 = mesh
	add_child(particles)
	return particles


func _register_input_actions() -> void:
	_ensure_key_action(forward_action, [KEY_W, KEY_UP])
	_ensure_key_action(backward_action, [KEY_S, KEY_DOWN])
	_ensure_key_action(steer_left_action, [KEY_A, KEY_LEFT])
	_ensure_key_action(steer_right_action, [KEY_D, KEY_RIGHT])
	_ensure_key_action(handbrake_action, [KEY_SPACE])
	_ensure_key_action(interact_action, [KEY_F])


func _ensure_key_action(action_name: StringName, key_codes: Array[int]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	if not InputMap.action_get_events(action_name).is_empty():
		return

	for key_code: int in key_codes:
		var key_event: InputEventKey = InputEventKey.new()
		key_event.physical_keycode = key_code
		InputMap.action_add_event(action_name, key_event)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(interact_action):
		return

	if is_mounted:
		dismount()
	elif nearby_player != null and is_instance_valid(nearby_player):
		mount(nearby_player)


func _on_body_entered_interaction(body: Node3D) -> void:
	var player: PlayerCharacter = body as PlayerCharacter
	if player != null and not player.is_vehicle_controlled:
		nearby_player = player


func _on_body_exited_interaction(body: Node3D) -> void:
	var player: PlayerCharacter = body as PlayerCharacter
	if player != null and player == nearby_player and not is_mounted:
		nearby_player = null


func _update_proximity_check() -> void:
	if is_mounted or interaction_area == null:
		return

	var found_player: PlayerCharacter = null
	for body: Node3D in interaction_area.get_overlapping_bodies():
		var player: PlayerCharacter = body as PlayerCharacter
		if player != null and not player.is_vehicle_controlled:
			found_player = player
			break
	nearby_player = found_player


func mount(player: PlayerCharacter) -> void:
	if is_mounted or player == null or player.is_vehicle_controlled:
		return

	player_ref = player
	nearby_player = null
	is_mounted = true
	current_speed = 0.0
	gravity_velocity = 0.0

	player_ref.set_vehicle_controlled(true)
	_update_rider_transform()
	if scooter_visual != null:
		scooter_visual.rotation = Vector3.ZERO
	if handlebar_pivot != null:
		handlebar_pivot.rotation.y = 0.0
	if front_wheel_steer_pivot != null:
		front_wheel_steer_pivot.rotation.y = 0.0

	player_mounted.emit(player_ref)


func dismount() -> void:
	if not is_mounted or player_ref == null:
		return

	var rider: PlayerCharacter = player_ref
	is_mounted = false
	current_speed = 0.0
	gravity_velocity = 0.0

	# Put the player on the scooter's right side, facing the same direction.
	var dismount_position: Vector3 = global_position + global_transform.basis.x * 1.5
	dismount_position.y = global_position.y + 0.2
	rider.global_position = dismount_position
	rider.global_rotation = Vector3(0.0, global_rotation.y, 0.0)
	rider.velocity = Vector3.ZERO
	rider.set_vehicle_controlled(false)
	rider.visual_root.rotation = Vector3.ZERO

	player_ref = null
	player_dismounted.emit(rider)


func _update_rider_transform() -> void:
	if player_ref == null:
		return

	var target_position: Vector3
	if mount_point != null:
		target_position = mount_point.global_position
	else:
		target_position = global_position + global_transform.basis * mount_offset

	player_ref.global_position = target_position
	# Keep the player root aligned with the scooter for the camera, while the
	# imported character mesh gets its own facing correction.
	player_ref.global_rotation = Vector3(0.0, global_rotation.y, 0.0)
	player_ref.velocity = velocity
	player_ref.visual_root.rotation = Vector3(0.0, rider_model_yaw_offset, 0.0)


func _physics_process(delta: float) -> void:
	_update_proximity_check()
	if is_mounted:
		_handle_driving(delta)
	else:
		_handle_idle(delta)
	_update_hud()


func _handle_idle(delta: float) -> void:
	if not is_on_floor():
		gravity_velocity += gravity_force * delta
	else:
		gravity_velocity = 2.0

	velocity = Vector3(0.0, -gravity_velocity, 0.0)
	floor_snap_length = ground_snap
	move_and_slide()
	current_speed = move_toward(current_speed, 0.0, friction * delta)
	previous_speed = current_speed
	is_braking = false
	_update_particles(false, false)
	_reset_visuals(delta)


func _handle_driving(delta: float) -> void:
	var throttle: float = Input.get_axis(backward_action, forward_action)
	var steer_input: float = Input.get_axis(steer_left_action, steer_right_action)
	var handbrake: bool = Input.is_action_pressed(handbrake_action)
	var speed_before_input: float = current_speed

	if handbrake:
		current_speed = move_toward(current_speed, 0.0, handbrake_force * delta)
	elif throttle > 0.0:
		current_speed = move_toward(current_speed, max_speed, acceleration * throttle * delta)
	elif throttle < 0.0:
		if current_speed > 0.5:
			current_speed = move_toward(current_speed, 0.0, brake_force * absf(throttle) * delta)
		else:
			current_speed = move_toward(current_speed, -reverse_speed, acceleration * absf(throttle) * 0.6 * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, friction * delta)

	is_braking = handbrake or (throttle < 0.0 and speed_before_input > 0.5)
	var speed_ratio: float = clampf(absf(current_speed) / max_speed, 0.0, 1.0)
	var effective_steer: float = lerpf(steer_speed_low, steer_speed_high, speed_ratio)
	if absf(current_speed) > 0.2:
		var steer_direction: float = -steer_input * effective_steer * delta
		if current_speed < 0.0:
			steer_direction = -steer_direction
		rotate_y(steer_direction)

	_update_visuals(delta, steer_input, speed_ratio, handbrake)

	if not is_on_floor():
		gravity_velocity += gravity_force * delta
	else:
		gravity_velocity = 2.0

	var forward_vector: Vector3 = -global_transform.basis.z
	var target_horizontal_velocity: Vector3 = forward_vector * current_speed
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var grip: float = traction if is_on_floor() else traction * air_control
	horizontal_velocity = horizontal_velocity.lerp(target_horizontal_velocity, clampf(grip * delta, 0.0, 1.0))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity.y = -gravity_velocity
	floor_snap_length = ground_snap
	move_and_slide()

	if get_slide_collision_count() > 0 and current_speed > 2.0:
		for index: int in range(get_slide_collision_count()):
			var collision: KinematicCollision3D = get_slide_collision(index)
			if collision.get_normal().dot(forward_vector) < -0.7:
				current_speed = move_toward(current_speed, 0.0, brake_force * delta * 2.0)
				break

	previous_speed = current_speed
	_update_particles(true, steer_input != 0.0 and speed_ratio > 0.25)
	_update_rider_transform()


func _update_visuals(delta: float, steer_input: float, speed_ratio: float, handbrake: bool) -> void:
	if scooter_visual != null:
		var target_tilt: float = -steer_input * deg_to_rad(tilt_amount) * speed_ratio
		if handbrake and absf(current_speed) > 3.0:
			target_tilt *= 1.4
		var acceleration_ratio: float = clampf((current_speed - previous_speed) / 3.0, -1.0, 1.0)
		var target_pitch: float = -acceleration_ratio * 0.07
		var target_bob: float = visual_base_position.y + sin(Time.get_ticks_msec() * 0.012) * suspension_bob * speed_ratio
		scooter_visual.rotation.z = lerpf(scooter_visual.rotation.z, target_tilt, tilt_lerp_speed * delta)
		scooter_visual.rotation.x = lerpf(scooter_visual.rotation.x, target_pitch, tilt_lerp_speed * delta)
		scooter_visual.position.y = lerpf(scooter_visual.position.y, target_bob, suspension_speed * delta)

	if handlebar_pivot != null:
		var target_handle_angle: float = -steer_input * deg_to_rad(handlebar_turn_max)
		handlebar_pivot.rotation.y = lerpf(handlebar_pivot.rotation.y, target_handle_angle, 10.0 * delta)
	if front_wheel_steer_pivot != null:
		var target_wheel_steer: float = -steer_input * deg_to_rad(front_wheel_steer_max)
		front_wheel_steer_pivot.rotation.y = lerpf(front_wheel_steer_pivot.rotation.y, target_wheel_steer, 10.0 * delta)

	var wheel_spin_delta: float = (current_speed / 0.4) * delta
	if front_wheel != null:
		front_wheel.rotate_x(wheel_spin_delta)
	if rear_wheel != null:
		rear_wheel.rotate_x(wheel_spin_delta)


func _reset_visuals(delta: float) -> void:
	if scooter_visual != null:
		scooter_visual.rotation.x = lerpf(scooter_visual.rotation.x, 0.0, tilt_lerp_speed * delta)
		scooter_visual.rotation.z = lerpf(scooter_visual.rotation.z, 0.0, tilt_lerp_speed * delta)
		scooter_visual.position.y = lerpf(scooter_visual.position.y, visual_base_position.y, suspension_speed * delta)
	if handlebar_pivot != null:
		handlebar_pivot.rotation.y = lerpf(handlebar_pivot.rotation.y, 0.0, 10.0 * delta)
	if front_wheel_steer_pivot != null:
		front_wheel_steer_pivot.rotation.y = lerpf(front_wheel_steer_pivot.rotation.y, 0.0, 10.0 * delta)


func _update_particles(riding: bool, turning: bool) -> void:
	var moving: bool = riding and absf(current_speed) > 1.0
	if exhaust_particles != null:
		exhaust_particles.emitting = moving
	if dust_particles != null:
		dust_particles.emitting = moving and absf(current_speed) > 5.0
	if skid_particles != null:
		skid_particles.emitting = riding and is_braking and absf(current_speed) > 2.0 and turning


func _setup_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var root_control: Control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root_control)

	prompt_panel = PanelContainer.new()
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.offset_top = -140.0
	prompt_panel.offset_bottom = -90.0
	prompt_panel.offset_left = -160.0
	prompt_panel.offset_right = 160.0
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.10, 0.15, 0.88), Color(0.35, 0.75, 1.0, 0.85), 14, 2))

	var prompt_box: HBoxContainer = HBoxContainer.new()
	prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.add_theme_constant_override("separation", 10)
	prompt_panel.add_child(prompt_box)

	var key_badge: PanelContainer = PanelContainer.new()
	key_badge.add_theme_stylebox_override("panel", _make_panel_style(Color(0.2, 0.55, 0.95, 0.95), Color.TRANSPARENT, 8, 0))
	prompt_box.add_child(key_badge)

	var key_label: Label = Label.new()
	key_label.text = "F"
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color.WHITE)
	key_badge.add_child(key_label)

	var prompt_text: Label = Label.new()
	prompt_text.text = "Ride Scooter"
	prompt_text.add_theme_font_size_override("font_size", 18)
	prompt_text.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	prompt_box.add_child(prompt_text)
	root_control.add_child(prompt_panel)

	dashboard_panel = PanelContainer.new()
	dashboard_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dashboard_panel.offset_top = -120.0
	dashboard_panel.offset_bottom = -40.0
	dashboard_panel.offset_left = -300.0
	dashboard_panel.offset_right = 300.0
	dashboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.13, 0.90), Color(0.3, 0.7, 1.0, 0.75), 16, 2))

	var dashboard: VBoxContainer = VBoxContainer.new()
	dashboard.alignment = BoxContainer.ALIGNMENT_CENTER
	dashboard.add_theme_constant_override("separation", 4)
	dashboard_panel.add_child(dashboard)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 16)
	dashboard.add_child(top_row)

	speed_label = Label.new()
	speed_label.text = "0 KM/H"
	speed_label.add_theme_font_size_override("font_size", 22)
	speed_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	top_row.add_child(speed_label)

	status_label = Label.new()
	status_label.text = "READY"
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	top_row.add_child(status_label)

	var controls_hint: Label = Label.new()
	controls_hint.text = "[W] Accelerate  •  [S] Brake/Reverse  •  [A/D] Steer  •  [SPACE] Brake  •  [F] Dismount"
	controls_hint.add_theme_font_size_override("font_size", 12)
	controls_hint.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	dashboard.add_child(controls_hint)
	root_control.add_child(dashboard_panel)

	prompt_panel.visible = false
	dashboard_panel.visible = false


func _make_panel_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _update_hud() -> void:
	if prompt_panel == null or dashboard_panel == null:
		return

	prompt_panel.visible = not is_mounted and nearby_player != null
	dashboard_panel.visible = is_mounted
	if not is_mounted:
		return

	var kmh: float = absf(current_speed) * 3.6
	speed_label.text = "%d KM/H" % int(kmh)

	if Input.is_action_pressed(handbrake_action):
		status_label.text = "BRAKE"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	elif current_speed > 0.5:
		status_label.text = "DRIVE"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	elif current_speed < -0.5:
		status_label.text = "REVERSE"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		status_label.text = "IDLE"
		status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
