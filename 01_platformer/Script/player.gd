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

@export_group("Health & UI")
@export var max_health: float = 100.0
## Drag your HealthBar (ProgressBar or HSlider) here, or leave empty to auto-detect/auto-create it.
@export var health_slider: Range

var current_health: float = 100.0

func _ready() -> void:
	# Automatically register in the "player" group so Crabs always find you
	add_to_group("player")
	
	current_health = max_health
	_setup_health_ui()

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
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
	if not is_on_floor():
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
	# Reloads the current level when health hits 0
	get_tree().reload_current_scene()

func _setup_health_ui() -> void:
	# 1. Try to find an existing ProgressBar or HSlider child if not assigned in Inspector
	if not is_instance_valid(health_slider):
		health_slider = find_child("HealthBar", true, false) as Range
		
	# 2. If you haven't added a HealthBar node yet, create one on screen automatically!
	if not is_instance_valid(health_slider):
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.name = "AutoHealthUI"
		add_child(canvas)
		
		var bar: ProgressBar = ProgressBar.new()
		bar.name = "HealthBar"
		bar.position = Vector2(24.0, 24.0)
		bar.size = Vector2(260.0, 28.0)
		bar.show_percentage = true
		
		var bg_style: StyleBoxFlat = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
		bg_style.set_corner_radius_all(6)
		
		var fill_style: StyleBoxFlat = StyleBoxFlat.new()
		fill_style.bg_color = Color(0.85, 0.2, 0.2, 0.95)
		fill_style.set_corner_radius_all(6)
		
		bar.add_theme_stylebox_override("background", bg_style)
		bar.add_theme_stylebox_override("fill", fill_style)
		
		canvas.add_child(bar)
		health_slider = bar

	health_slider.min_value = 0.0
	health_slider.max_value = max_health
	health_slider.value = current_health
