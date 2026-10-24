
extends Area3D

@export var dialogue_ui_scene: PackedScene

var has_triggered := false
var dialogue_ui: CanvasLayer


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if has_triggered:
		return

	if not body is CharacterBody3D:
		return

	if dialogue_ui_scene == null:
		push_error("Assign DialogueUI.tscn in the Inspector.")
		return

	has_triggered = true

	dialogue_ui = dialogue_ui_scene.instantiate() as CanvasLayer
	get_tree().current_scene.add_child(dialogue_ui)
	dialogue_ui.start_dialogue()
