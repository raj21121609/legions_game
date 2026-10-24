extends CharacterBody3D

@onready var anim_player: AnimationPlayer = $mesh/AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var camera: Node3D = $SpringArm3D/Camera3D

@export_group("Movement")
@export var speed: float = 5.0
const JUMP_VELOCITY: float = 8.0
const RUN_SPEED: float = 3.5
const BLEND_SPEED: float = 0.2
var last_lean: float = 0.0

# --- GRAVITY FLIP MECHANIC ---
@export_group("Special Abilities")
## Turn this on inside Level 4's inspector configuration for the player!
@export var can_flip_gravity: bool = false
var gravity_multiplier: float = 1.0

# --- JUMP COUNTER AND WORLDENVIRONMENT TRACKING ---
var jump_count: int = 0
@onready var world_env: WorldEnvironment = get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment

@export_group("Health & UI")
@export var max_health: float = 100.0
## Drag your HealthBar (ProgressBar or HSlider) here, or leave empty to auto-detect/auto-create it.
@export var health_slider: Range

var current_health: float = 100.0

# --- TIMER CONFIGURATION ---
@export_group("Level Timer")
## Total seconds allowed to complete the level before dying
@export var time_limit: float = 60.0
var time_left: float = 0.0
@onready var timer_label: Label = $CanvasLayer/TimerLabel

func _ready() -> void:
	# Automatically register in the "player" group so Crabs always find you
	add_to_group("player")
	
	current_health = max_health
	time_left = time_limit
	_setup_health_ui()

func _physics_process(delta: float) -> void:
	# --- Update Level Timer ---
	if time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		if is_instance_valid(timer_label):
			timer_label.text = "Time Left: %d" % ceilf(time_left)
		
		if time_left <= 0.0:
			print("Time's up!")
			_on_player_death()

	# 1. Handle Gravity Flip input (lifts up or falls back down without rotating anything)
	if can_flip_gravity and Input.is_action_just_pressed("flip_gravity"):
		gravity_multiplier *= -1.0
		
		# Invert Godot's built-in floor processing detection so ceiling handles stickiness properly
		up_direction = Vector3.UP * gravity_multiplier

	# Add the gravity (multiplied by direction state).
	if not is_on_floor():
		velocity += get_gravity() * gravity_multiplier * delta

	# Handle jump (Supports inverted vertical controls automatically).
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY * gravity_multiplier
		anim_tree.set("parameters/movement/transition_request", "jump")
		
		# Increment jump count and signal the WorldEnvironment
		jump_count += 1
		if is_instance_valid(world_env):
			world_env.update_jump_trigger(jump_count)

	# Get the input direction and handle movement relative to the camera
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (camera.global_basis * Vector3(input_dir.x, 0.0, input_dir.y))
	direction = Vector3(direction.x, 0.0, direction.z).normalized() * input_dir.length()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	turn_to(direction)
	
	var current_speed: float = velocity.length()
	
	# Handle checking ceiling/floor animations dependent on gravity inversion status
	var falling: bool = (velocity.y < 0.0 if gravity_multiplier > 0 else velocity.y > 0.0)
	
	if not is_on_floor():
		if falling:
			anim_tree.set("parameters/movement/transition_request", "fall")
	elif current_speed > RUN_SPEED:
		anim_tree.set("parameters/movement/transition_request", "run")
		var lean: float = direction.dot(global_basis.x)
		last_lean = lerpf(last_lean, lean, 0.3)
		anim_tree.set("parameters/run_lean/add_amount", last_lean)
	elif current_speed > 0.0:
		anim_tree.set("parameters/movement/transition_request", "walk")
		var walk_speed_scale: float = lerpf(0.5, 1.75, current_speed / RUN_SPEED)
		anim_tree.set("parameters/walk_speed/scale", walk_speed_scale)
	else:
		anim_tree.set("parameters/movement/transition_request", "idle")

func turn_to(direction: Vector3) -> void:
	if direction:
		var yaw: float = atan2(-direction.x, -direction.z)
		yaw = lerp_angle(rotation.y, yaw, 0.1)
		rotation.y = yaw

# --- HEALTH & DAMAGE SYSTEM ---
func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return
		
	current_health = clampf(current_health - amount, 0.0, max_health)
	if is_instance_valid(health_slider):
		health_slider.value = current_health
		
	print("Player took ", amount, " damage! Current Health: ", current_health)
	
	if current_health <= 0.0:
		_on_player_death()

func heal(amount: float) -> void:
	current_health = clampf(current_health + amount, 0.0, max_health)
	if is_instance_valid(health_slider):
		health_slider.value = current_health

func _on_player_death() -> void:
	print("Player Died!")
	# Reloads the current level when health hits 0 or time runs out
	get_tree().reload_current_scene()

func _setup_health_ui() -> void:
	# 1. Try to find an existing ProgressBar or HSlider child if not assigned in Inspector
	if not is_instance_valid(health_slider):
		health_slider = find_child("HealthBar", true, false) as Range
		
	# 2. Setup your pre-existing health bar configuration
	if is_instance_valid(health_slider):
		health_slider.min_value = 0.0
		health_slider.max_value = max_health
		health_slider.value = current_health
