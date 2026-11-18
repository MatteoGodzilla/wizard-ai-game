extends Control

@onready var text = $RichTextLabel

var _list : Array[Enums.Spell]
var _active = false

func _on_cast_typer_setup_graphics(elements: Array[Enums.Spell], timer: float) -> void:
	_list = elements
	_active = true
	_on_cast_typer_update_graphics(0)

func _on_cast_typer_update_graphics(correct_amount: int) -> void:
	if !_active:
		return
	text.text = ""
	for i in _list.size():
		if i < correct_amount:
			text.text += "[color=green]%d[/color] " % _list[i]
		else:
			text.text += "%d " % _list[i]

func _on_cast_typer_on_successful_cast() -> void:
	_active = false
	text.text += "\n[color=blue]Success[/color]"

func _on_cast_typer_on_failed_cast() -> void:
	_active = false
	text.text += "\n[color=red]Failiure[/color]"
