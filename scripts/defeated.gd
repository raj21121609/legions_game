
extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

const WALK_ANIMATION: StringName = &"newLib/real_walk"
const IDLE_ANIMATION: StringName = &"newLib/idle"

func _ready() -> void:
	print("Defeated script loaded")
	print("Available animations: ", animation_player.get_animation_list())
	play_idle()

func play_walk() -> void:
	if not animation_player.has_animation(WALK_ANIMATION):
		print("WALK NOT FOUND: ", WALK_ANIMATION)
		return

	if animation_player.current_animation != WALK_ANIMATION:
		animation_player.play(WALK_ANIMATION)
		print("Playing walk")

func play_idle() -> void:
	if not animation_player.has_animation(IDLE_ANIMATION):
		print("IDLE NOT FOUND: ", IDLE_ANIMATION)
		return

	if animation_player.current_animation != IDLE_ANIMATION:
		animation_player.play(IDLE_ANIMATION)
		print("Playing idle")
