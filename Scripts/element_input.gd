class_name ElementInput
extends Node

signal element_typed(element: Enums.Element)

const INPUT_ACTION_PREFIX := "element_"

var enabled := true
var element_by_input_action : Dictionary[StringName, Enums.Element] = {}

func _ready() -> void:
	for element_name : String in Enums.Element:
		if element_name == "INVALID": continue
		var input_action_name := StringName(INPUT_ACTION_PREFIX + element_name.to_lower())
		assert(InputMap.has_action(input_action_name), "No input action '%s'" % input_action_name)
		element_by_input_action[input_action_name] = Enums.Element[element_name]

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or event.is_echo():
		return
	for input_action_name in element_by_input_action:
		if event.is_action_pressed(input_action_name):
			element_typed.emit(element_by_input_action[input_action_name])
			get_viewport().set_input_as_handled()
			return
