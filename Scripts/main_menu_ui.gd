extends Control

@export_group ("Scenes")
@export var main_scene: PackedScene
@export var next_scene: PackedScene

func _on_play_button_pressed() -> void:
	if next_scene == null:
		push_error("[Main Menu] next scene not set")
	get_tree().change_scene_to_packed(next_scene)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
