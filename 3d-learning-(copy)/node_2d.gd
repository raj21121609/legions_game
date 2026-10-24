extends Node

#func _on_level_1_pressed():
	#get_tree().change_scene_to_file("res://scenes/Level1.tscn")
#
#
#func _on_level_2_pressed():
	#get_tree().change_scene_to_file("res://scenes/Level_2.tscn")
#
#"res://scenes/level_2.tscn"
#func _on_level_3_pressed():
	#get_tree().change_scene_to_file("res://scenes/Level3.tscn")


func _on_level_1_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_2.tscn")


func _on_level_2_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_3.tscn")


func _on_level_3_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_4.tscn")


func _on_level_4_pressed() -> void:
	get_tree().change_scene_to_file("res://node_2d.tscn")
