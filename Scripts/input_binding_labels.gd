class_name InputBindingLabels
extends RefCounted

static func get_first_key_label(input_action_name: StringName) -> String:
	print("Getting first key label for input action: %s" % input_action_name)
	for bound_event in InputMap.action_get_events(input_action_name):
		var key_event := bound_event as InputEventKey
		if key_event == null:
			continue
		var layout_keycode := key_event.keycode
		if layout_keycode == KEY_NONE:
			layout_keycode = DisplayServer.keyboard_get_keycode_from_physical(key_event.physical_keycode)
		return OS.get_keycode_string(layout_keycode)
	return ":("
