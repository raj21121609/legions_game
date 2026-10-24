extends Area3D

# This lets you select the next level directly inside the Inspector window
@export_file("*.tscn") var next_scene_path: String

func _ready() -> void:
	# Automatically connects the collision signal to this script
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Checks if the object falling in is the player
	if body.name == "player" or body.is_in_group("player"):
		if next_scene_path != "":
			get_tree().change_scene_to_file(next_scene_path)
		else:
			print("Error: No next scene path set in the Inspector!")
