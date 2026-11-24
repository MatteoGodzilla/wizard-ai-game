extends Control

## Pause / options menu. Toggled with the Esc key; pauses the game while open.

# Path (not PackedScene) to avoid a cyclic dependency: main menu -> game -> options -> main menu
@export_file("*.tscn") var main_menu_scene: String = "res://Scenes/main_menu.tscn"

@onready var resume_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ResumeButton


func _ready() -> void:
	# Keep processing input while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if visible:
			close_menu()
		else:
			open_menu()


func open_menu() -> void:
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()


func close_menu() -> void:
	visible = false
	get_tree().paused = false


func _on_resume_button_pressed() -> void:
	close_menu()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	if main_menu_scene.is_empty():
		push_error("[Options] main menu scene not set")
		return
	get_tree().change_scene_to_file(main_menu_scene)


func _on_quit_button_pressed() -> void:
	get_tree().quit()
