extends Area3D

func _ready() -> void:
	# Automatically connect the body_entered signal
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Check if the falling object is the player
	if body.is_in_group("player") or body is CharacterBody3D:
		print("Player fell into the Killzone! Restarting...")
		get_tree().call_deferred("reload_current_scene")
