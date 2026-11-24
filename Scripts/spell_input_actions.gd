class_name SpellInputActions
extends RefCounted

const INPUT_ACTION_PREFIX := "element_"

static func get_action_name(spell: Enums.Element) -> StringName:
	return StringName(INPUT_ACTION_PREFIX + Enums.Element.find_key(spell).to_lower())
