extends Control

@export_group ("Scenes")
@export var next_scene: PackedScene

func _ready() -> void:
	if not Audio.bgm.playing:
		Audio.next_bgm()

func _on_play_button_pressed() -> void:
	if next_scene == null:
		push_error("[Main Menu] next scene not set")
		return
	get_tree().change_scene_to_packed(next_scene)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
