class_name InputBindingLabels
extends RefCounted


static func get_key_labels(action: StringName) -> String:
	var labels := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: Key = event.keycode
			if code == KEY_NONE:
				code = event.physical_keycode
				if DisplayServer.get_name() != "headless":
					code = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
			var label := OS.get_keycode_string(code)
			if not label.is_empty() and not label in labels:
				labels.append(label)
	return " / ".join(labels) if not labels.is_empty() else "Unbound"


static func get_first_key_label(action: StringName) -> String:
	return get_key_labels(action).get_slice(" / ", 0)
