extends Control

@onready var sequence_label : RichTextLabel = $RichTextLabel

var _key_labels : PackedStringArray
var _is_active := false

func _on_cast_typer_setup_graphics(elements: Array[Enums.Element], timer: float) -> void:
	_key_labels = PackedStringArray()
	for spell in elements:
		var input_action_name := SpellInputActions.get_action_name(spell)
		var key_label := InputBindingLabels.get_first_key_label(input_action_name)
		_key_labels.append(key_label.replace("[", "[lb]"))
	_is_active = true
	_on_cast_typer_update_graphics(0)

func _on_cast_typer_update_graphics(correct_amount: int) -> void:
	if not _is_active:
		return
	var rendered_labels := PackedStringArray()
	for key_index in _key_labels.size():
		var key_label := _key_labels[key_index]
		rendered_labels.append("[color=green]%s[/color]" % key_label if key_index < correct_amount else key_label)
	sequence_label.text = " ".join(rendered_labels)

func _on_cast_typer_on_successful_cast() -> void:
	_is_active = false
	sequence_label.text += "\n[color=blue]Success[/color]"

func _on_cast_typer_on_failed_cast() -> void:
	_is_active = false
	sequence_label.text += "\n[color=red]Failure[/color]"
