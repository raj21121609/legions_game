extends CharacterBody3D

class_name ScooterController

## Scooter controller that allows the player to ride the scooter around the map.
## Press F near the scooter to mount, and F again to dismount.

# -- Movement tuning --
@export_group("Movement")
@export var max_speed : float = 24.0            # ~86 km/h max speed
@export var acceleration : float = 12.0         # pickup rate
@export var brake_force : float = 16.0          # regular brake force
@export var handbrake_force : float = 28.0      # spacebar handbrake force
@export var friction : float = 3.5              # natural coasting friction
@export var reverse_speed : float = 7.0         # backing-up speed

@export_group("Steering")
@export var steer_speed_low : float = 3.0       # turning rate at low speed (rad/s)
@export var steer_speed_high : float = 1.2      # turning rate at high speed (rad/s)
@export var tilt_amount : float = 18.0          # degrees of visual lean when turning
@export var tilt_lerp_speed : float = 7.0       # how fast the scooter leans
@export var handlebar_turn_max : float = 22.0   # degrees of handlebar visual rotation

@export_group("Physics")
@export var gravity_force : float = 24.0
@export var ground_snap : float = 0.6

# -- Interaction & Mounting --
@export_group("Interaction")
@export var interact_action : StringName = "scooter_interact"
@export var interact_distance : float = 4.0
@export var mount_offset : Vector3 = Vector3(0.0, 0.45, 0.2)   # rider position relative to scooter

# -- State --
var is_mounted : bool = false
var current_speed : float = 0.0
var current_steer_angle : float = 0.0
var gravity_velocity : float = 0.0

# -- References --
var player_ref : CharacterBody3D = null
var scooter_visual : Node3D = null
var front_wheel : Node3D = null
var rear_wheel : Node3D = null
var handlebar_node : Node3D = null

@onready var interaction_area : Area3D = get_node_or_null("InteractionArea")
@onready var mount_point : Marker3D = get_node_or_null("MountPoint")

# Input actions
var _forward_action : StringName = "scooter_forward"
var _backward_action : StringName = "scooter_backward"
var _steer_left_action : StringName = "scooter_steer_left"
var _steer_right_action : StringName = "scooter_steer_right"
var _handbrake_action : StringName = "scooter_handbrake"

# -- Nearby player tracking --
var _nearby_player : CharacterBody3D = null

# -- HUD elements --
var _hud_layer : CanvasLayer = null
var _prompt_panel : PanelContainer = null
var _dashboard_panel : PanelContainer = null
var _speed_label : Label = null
var _status_label : Label = null

signal player_mounted(player : CharacterBody3D)
signal player_dismounted(player : CharacterBody3D)


func _ready() -> void:
	# Ensure proper collision layer: scooter is on layer 4 (interactive vehicle), masks layer 1 (world)
	collision_layer = 4
	collision_mask = 1

	# Find visual node and parts
	for child in get_children():
		if child.name == "SCOOTER":
			scooter_visual = child
			break

	if scooter_visual:
		front_wheel = scooter_visual.get_node_or_null("tyre-1")
		rear_wheel = scooter_visual.get_node_or_null("tyre-2")
		handlebar_node = scooter_visual.get_node_or_null("handle")

	# Disable any pre-baked static body children inside the visual model so they don't fight CharacterBody3D
	for sb in find_children("*", "StaticBody3D", true, false):
		sb.collision_layer = 0
		sb.collision_mask = 0

	_register_input_actions()
	_setup_hud()

	# Connect interaction area
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered_interaction)
		interaction_area.body_exited.connect(_on_body_exited_interaction)


func _register_input_actions() -> void:
	var actions_to_register := {
		_forward_action: [Key.KEY_W, Key.KEY_UP],
		_backward_action: [Key.KEY_S, Key.KEY_DOWN],
		_steer_left_action: [Key.KEY_A, Key.KEY_LEFT],
		_steer_right_action: [Key.KEY_D, Key.KEY_RIGHT],
		_handbrake_action: [Key.KEY_SPACE],
		interact_action: [Key.KEY_F],
	}

	for action_name in actions_to_register:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			for key_code in actions_to_register[action_name]:
				var event := InputEventKey.new()
				event.keycode = key_code
				event.physical_keycode = key_code
				InputMap.action_add_event(action_name, event)


# -----------------------------------------------------------------------------
# Interaction & Mounting
# -----------------------------------------------------------------------------

func _on_body_entered_interaction(body : Node3D) -> void:
	if body is CharacterBody3D and (body.is_in_group("player") or body.name == "PlayerCharacter"):
		_nearby_player = body


func _on_body_exited_interaction(body : Node3D) -> void:
	if body == _nearby_player and not is_mounted:
		_nearby_player = null


func _input(event : InputEvent) -> void:
	var f_pressed := false
	if event.is_action_pressed(interact_action):
		f_pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == Key.KEY_F or event.physical_keycode == Key.KEY_F:
			f_pressed = true

	if f_pressed:
		if is_mounted:
			dismount()
		elif _nearby_player != null:
			mount(_nearby_player)


func mount(player : CharacterBody3D) -> void:
	if is_mounted:
		return

	player_ref = player
	is_mounted = true

	# 1. Disable player character physics & movement processing
	player_ref.set_physics_process(false)
	player_ref.set_process(false)

	# 2. Disable state machine so it doesn't process walking/jumping logic while riding
	if player_ref.get("state_machine") != null:
		var sm = player_ref.state_machine
		sm.set_physics_process(false)
		sm.set_process(false)

	# 3. Disable collision shape so the rider doesn't block or push the scooter
	player_ref.collision_layer = 0
	player_ref.collision_mask = 0
	if player_ref.get("collision_shape_3d") != null:
		player_ref.collision_shape_3d.disabled = true

	# 4. Turn off footstep dust particles
	if player_ref.get("movement_dust") != null and player_ref.movement_dust != null:
		player_ref.movement_dust.emitting = false

	# 5. Set plush model to idle pose and face straight forward on the scooter
	if player_ref.get("godot_plush_skin") != null and player_ref.godot_plush_skin != null:
		player_ref.godot_plush_skin.set_state("idle")
	if player_ref.get("visual_root") != null and player_ref.visual_root != null:
		player_ref.visual_root.rotation = Vector3.ZERO
		player_ref.visual_root.visible = true

	# 6. Snap player to mount point
	_update_rider_transform()

	player_mounted.emit(player_ref)


func dismount() -> void:
	if not is_mounted or player_ref == null:
		return

	is_mounted = false

	# 1. Place the player beside the scooter (2 meters to the right, slightly elevated)
	var dismount_pos := global_position + global_transform.basis.x * 2.0 + Vector3(0.0, 0.3, 0.0)
	player_ref.global_position = dismount_pos
	player_ref.velocity = Vector3.ZERO

	# 2. Re-enable collision
	player_ref.collision_layer = 2
	player_ref.collision_mask = 1
	if player_ref.get("collision_shape_3d") != null:
		player_ref.collision_shape_3d.disabled = false

	# 3. Re-enable state machine and processing
	if player_ref.get("state_machine") != null:
		var sm = player_ref.state_machine
		sm.set_physics_process(true)
		sm.set_process(true)

	player_ref.set_physics_process(true)
	player_ref.set_process(true)

	# 4. Reset rider state
	if player_ref.get("godot_plush_skin") != null and player_ref.godot_plush_skin != null:
		player_ref.godot_plush_skin.set_state("idle")

	var prev_player = player_ref
	player_ref = null

	# Reset scooter momentum
	current_speed = 0.0
	gravity_velocity = 0.0

	player_dismounted.emit(prev_player)


func _update_rider_transform() -> void:
	if player_ref == null:
		return

	# Calculate mount position: use MountPoint if available, otherwise apply mount_offset
	var target_pos : Vector3
	if mount_point:
		target_pos = mount_point.global_position
	else:
		target_pos = global_position + global_transform.basis * mount_offset

	player_ref.global_position = target_pos
	# Align rider heading with scooter forward direction
	player_ref.global_rotation.y = global_rotation.y

	# Keep rider visual oriented straight forward
	if player_ref.get("visual_root") != null and player_ref.visual_root != null:
		player_ref.visual_root.rotation = Vector3.ZERO

	# Synchronize velocity for HUD readouts
	player_ref.velocity = velocity


# -----------------------------------------------------------------------------
# Physics Processing
# -----------------------------------------------------------------------------

func _physics_process(delta : float) -> void:
	# Proximity check fallback (ensures player is detected even if spawning inside area)
	_update_proximity_check()

	if is_mounted:
		_handle_driving(delta)
	else:
		_handle_idle(delta)

	_update_hud(delta)


func _update_proximity_check() -> void:
	if is_mounted:
		return

	if interaction_area:
		var bodies := interaction_area.get_overlapping_bodies()
		var found_player : CharacterBody3D = null
		for b in bodies:
			if b is CharacterBody3D and (b.is_in_group("player") or b.name == "PlayerCharacter"):
				found_player = b
				break
		_nearby_player = found_player


func _handle_idle(delta : float) -> void:
	# Apply gravity when in air
	if not is_on_floor():
		gravity_velocity += gravity_force * delta
	else:
		gravity_velocity = 2.0  # slight downward bias to keep grounded

	# Slow down to stop with friction
	current_speed = move_toward(current_speed, 0.0, friction * delta)

	var move_vec := -global_transform.basis.z * current_speed
	move_vec.y = -gravity_velocity

	velocity = move_vec
	floor_snap_length = ground_snap
	move_and_slide()

	# Relax tilt back to zero
	if scooter_visual:
		scooter_visual.rotation.z = lerp(scooter_visual.rotation.z, 0.0, tilt_lerp_speed * delta)


func _handle_driving(delta : float) -> void:
	# -- Read Inputs --
	var throttle := 0.0
	if Input.is_action_pressed(_forward_action) or Input.is_key_pressed(Key.KEY_W) or Input.is_key_pressed(Key.KEY_UP):
		throttle += 1.0
	if Input.is_action_pressed(_backward_action) or Input.is_key_pressed(Key.KEY_S) or Input.is_key_pressed(Key.KEY_DOWN):
		throttle -= 1.0

	var steer_input := 0.0
	if Input.is_action_pressed(_steer_right_action) or Input.is_key_pressed(Key.KEY_D) or Input.is_key_pressed(Key.KEY_RIGHT):
		steer_input += 1.0
	if Input.is_action_pressed(_steer_left_action) or Input.is_key_pressed(Key.KEY_A) or Input.is_key_pressed(Key.KEY_LEFT):
		steer_input -= 1.0

	var handbrake := Input.is_action_pressed(_handbrake_action) or Input.is_key_pressed(Key.KEY_SPACE)

	# -- Acceleration / Braking --
	if handbrake:
		# Rapid stop with drift effect
		current_speed = move_toward(current_speed, 0.0, handbrake_force * delta)
	elif throttle > 0.0:
		# Accelerate forward
		current_speed = move_toward(current_speed, max_speed, acceleration * throttle * delta)
	elif throttle < 0.0:
		if current_speed > 0.5:
			# Braking while moving forward
			current_speed = move_toward(current_speed, 0.0, brake_force * abs(throttle) * delta)
		else:
			# Reverse
			current_speed = move_toward(current_speed, -reverse_speed, acceleration * 0.6 * delta)
	else:
		# Coasting with natural friction
		current_speed = move_toward(current_speed, 0.0, friction * delta)

	# -- Steering --
	var speed_ratio := clamp(abs(current_speed) / max_speed, 0.0, 1.0)
	var effective_steer := lerp(steer_speed_low, steer_speed_high, speed_ratio)

	# Can steer effectively once moving slightly
	if abs(current_speed) > 0.2:
		var steer_dir := -steer_input * effective_steer * delta
		if current_speed < 0.0:
			steer_dir = -steer_dir  # invert steering in reverse
		rotate_y(steer_dir)

	# -- Visual Body Tilt (leaning into corners) --
	if scooter_visual:
		var target_tilt := -steer_input * deg_to_rad(tilt_amount) * speed_ratio
		if handbrake and abs(current_speed) > 3.0:
			target_tilt *= 1.4  # extra drift lean on handbrake
		scooter_visual.rotation.z = lerp(scooter_visual.rotation.z, target_tilt, tilt_lerp_speed * delta)

	# -- Handlebar Visual Rotation --
	if handlebar_node:
		var target_handle_angle := -steer_input * deg_to_rad(handlebar_turn_max)
		handlebar_node.rotation.y = lerp(handlebar_node.rotation.y, target_handle_angle, 10.0 * delta)

	# -- Wheel Spin Animation --
	var wheel_spin_delta := (current_speed / 0.4) * delta  # wheel radius ~0.4m
	if front_wheel:
		front_wheel.rotate_x(wheel_spin_delta)
	if rear_wheel:
		rear_wheel.rotate_x(wheel_spin_delta)

	# -- Gravity --
	if not is_on_floor():
		gravity_velocity += gravity_force * delta
	else:
		gravity_velocity = 2.0

	# -- Movement & Collision --
	var forward_vec := -global_transform.basis.z
	var move_vec := forward_vec * current_speed
	move_vec.y = -gravity_velocity

	velocity = move_vec
	floor_snap_length = ground_snap
	move_and_slide()

	# Dampen speed if colliding with an obstacle ahead
	if get_slide_collision_count() > 0 and current_speed > 2.0:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			if col.get_normal().dot(forward_vec) < -0.7:
				current_speed = move_toward(current_speed, 0.0, brake_force * delta * 2.0)
				break

	# Keep rider locked in place
	_update_rider_transform()


# -----------------------------------------------------------------------------
# In-Game HUD (Interaction prompt + Driving cluster)
# -----------------------------------------------------------------------------

func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var root_control := Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root_control)

	# 1. Interaction Prompt (centered near bottom-middle)
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_top = -140
	_prompt_panel.offset_bottom = -90
	_prompt_panel.offset_left = -160
	_prompt_panel.offset_right = 160
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.08, 0.10, 0.15, 0.88)
	prompt_style.border_color = Color(0.35, 0.75, 1.0, 0.85)
	prompt_style.set_border_width_all(2)
	prompt_style.set_corner_radius_all(14)
	prompt_style.content_margin_left = 18
	prompt_style.content_margin_right = 18
	prompt_style.content_margin_top = 8
	prompt_style.content_margin_bottom = 8
	_prompt_panel.add_theme_stylebox_override("panel", prompt_style)

	var prompt_box := HBoxContainer.new()
	prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.add_theme_constant_override("separation", 10)
	_prompt_panel.add_child(prompt_box)

	var key_badge := PanelContainer.new()
	var key_badge_style := StyleBoxFlat.new()
	key_badge_style.bg_color = Color(0.2, 0.55, 0.95, 0.95)
	key_badge_style.set_corner_radius_all(8)
	key_badge_style.content_margin_left = 10
	key_badge_style.content_margin_right = 10
	key_badge_style.content_margin_top = 4
	key_badge_style.content_margin_bottom = 4
	key_badge.add_theme_stylebox_override("panel", key_badge_style)
	prompt_box.add_child(key_badge)

	var key_label := Label.new()
	key_label.text = "F"
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color.WHITE)
	key_badge.add_child(key_label)

	var prompt_text := Label.new()
	prompt_text.text = "Ride Scooter"
	prompt_text.add_theme_font_size_override("font_size", 18)
	prompt_text.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	prompt_box.add_child(prompt_text)

	root_control.add_child(_prompt_panel)
	_prompt_panel.visible = false

	# 2. Driving Dashboard (sleek bottom bar)
	_dashboard_panel = PanelContainer.new()
	_dashboard_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dashboard_panel.offset_top = -120
	_dashboard_panel.offset_bottom = -40
	_dashboard_panel.offset_left = -300
	_dashboard_panel.offset_right = 300
	_dashboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dash_style := StyleBoxFlat.new()
	dash_style.bg_color = Color(0.06, 0.08, 0.13, 0.90)
	dash_style.border_color = Color(0.3, 0.7, 1.0, 0.75)
	dash_style.set_border_width_all(2)
	dash_style.set_corner_radius_all(16)
	dash_style.content_margin_left = 24
	dash_style.content_margin_right = 24
	dash_style.content_margin_top = 10
	dash_style.content_margin_bottom = 10
	_dashboard_panel.add_theme_stylebox_override("panel", dash_style)

	var dash_vbox := VBoxContainer.new()
	dash_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dash_vbox.add_theme_constant_override("separation", 4)
	_dashboard_panel.add_child(dash_vbox)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 16)
	dash_vbox.add_child(top_row)

	_speed_label = Label.new()
	_speed_label.text = "0 KM/H"
	_speed_label.add_theme_font_size_override("font_size", 22)
	_speed_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	top_row.add_child(_speed_label)

	_status_label = Label.new()
	_status_label.text = "READY"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	top_row.add_child(_status_label)

	var controls_hint := Label.new()
	controls_hint.text = "[W] Accelerate  •  [S] Brake/Rev  •  [A/D] Steer  •  [SPACE] Drift  •  [F] Dismount"
	controls_hint.add_theme_font_size_override("font_size", 12)
	controls_hint.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	dash_vbox.add_child(controls_hint)

	root_control.add_child(_dashboard_panel)
	_dashboard_panel.visible = false


func _update_hud(_delta : float) -> void:
	if _prompt_panel == null or _dashboard_panel == null:
		return

	if is_mounted:
		_prompt_panel.visible = false
		_dashboard_panel.visible = true

		# Update speed (convert m/s to km/h: speed * 3.6)
		var kmh := abs(current_speed) * 3.6
		_speed_label.text = "%d KM/H" % int(kmh)

		if Input.is_action_pressed(_handbrake_action) or Input.is_key_pressed(Key.KEY_SPACE):
			_status_label.text = "DRIFT"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		elif current_speed > 0.5:
			_status_label.text = "DRIVE"
			_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		elif current_speed < -0.5:
			_status_label.text = "REVERSE"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			_status_label.text = "IDLE"
			_status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	else:
		_dashboard_panel.visible = false
		_prompt_panel.visible = (_nearby_player != null)
