extends Node3D

const Arena = preload("res://spellcheck/arena.gd")
const CastingUI = preload("res://spellcheck/casting_ui.gd")
const Spellbook = preload("res://spellcheck/spellbook.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const WORKSHOP_SCENE := "res://Scenes/spell_maker.tscn"

var _arena: Arena
var _ui: CastingUI
var _book: Spellbook
var _equipped: Dictionary = {}
var _changing_scene := false


func _ready() -> void:
	_book = Crafting.book
	_replace_arena()
	_ui = CastingUI.new()
	_ui.submitted.connect(_submit)
	_ui.book_requested.connect(_open_book)
	_ui.reset_requested.connect(_reset_world)
	_ui.workshop_requested.connect(_back_to_workshop)
	_ui.modal_changed.connect(func(open: bool) -> void: _arena.input_enabled = not open)
	add_child(_ui)
	Crafting.changed.connect(_refresh_book)
	if _book.warning.is_empty():
		_ui.feedback("Equip a spell from your spellbook.")
	else:
		_ui.feedback(_book.warning, true)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_ui) or _changing_scene or not event is InputEventKey or event.echo:
		return
	if event.keycode == KEY_SHIFT:
		if event.pressed and not event.ctrl_pressed and not event.alt_pressed and not _ui.has_modal():
			_ui.open_quick(_prefix_names)
			get_viewport().set_input_as_handled()
		elif not event.pressed and _ui.mode() == "quick":
			_submit(_ui.quick_text())
			get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	if _ui.has_modal():
		if event.keycode == KEY_ESCAPE:
			_ui.close_modal()
			get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_B and not event.ctrl_pressed and not event.alt_pressed:
		_open_book()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_ui) and _ui.mode() == "quick":
		_ui.close_modal()


func _unhandled_input(event: InputEvent) -> void:
	if _changing_scene or not is_instance_valid(_ui) or _ui.has_modal() or not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if _equipped.is_empty():
		return
	if not _arena.cast(_equipped, event.position):
		_ui.feedback("Wait a moment before casting again.", true)
	get_viewport().set_input_as_handled()


func _open_book(selected: String = "") -> void:
	_ui.open_book(_book.entries, _state_for, selected)


func _refresh_book() -> void:
	_ui.refresh_book()


func _back_to_workshop() -> void:
	if _changing_scene:
		return
	_changing_scene = true
	var error := get_tree().change_scene_to_file(WORKSHOP_SCENE)
	if error != OK:
		_changing_scene = false
		_ui.feedback("Could not open the workshop.", true)


func _prefix_names(text: String) -> Array[String]:
	var key := _book.normalize(text)
	var names: Array[String] = []
	if key.length() < 2:
		return names
	for entry: Dictionary in _book.entries.values():
		if _book.normalize(entry["name"]).begins_with(key) and _state_for(entry["entry_id"]) == "READY":
			names.append(entry["name"])
	names.sort_custom(func(a: String, b: String) -> bool: return a.nocasecmp_to(b) < 0)
	return names.slice(0, 4)


func _state_for(id: String) -> String:
	return "ERROR" if _book.resolution(id).is_empty() else "READY"


func _submit(text: String) -> void:
	_ui.close_modal()
	if _book.normalize(text).is_empty():
		return
	var id := _book.lookup(text)
	if id.is_empty():
		for suggestion: String in _book.suggestions(text):
			if _state_for(suggestion) == "READY":
				_ui.feedback("Did you mean %s?" % _book.entries[suggestion]["name"], true)
				return
		_ui.feedback("Craft this spell in the workshop to unlock it.", true)
		return
	var result := _book.resolution(id)
	if result.is_empty():
		_ui.feedback("This spell has no usable definition.", true)
		return
	_equip_definition(_book.entries[id], result)


func _equip_definition(entry: Dictionary, result: Dictionary) -> void:
	var checked := Intent.compile(result["intent"])
	if checked.has("error"):
		result.erase("intent")
		result["error"] = checked["error"]
		_ui.feedback(result["error"], true)
		_ui.inspect(entry, result)
		return
	_equipped = checked["spell"]
	result["compiled"] = _equipped
	_ui.set_equipped(entry["name"])
	_ui.inspect(entry, result)
	_ui.feedback("Left click to cast.")


func _replace_arena() -> void:
	if is_instance_valid(_arena):
		remove_child(_arena)
		_arena.queue_free()
	_arena = Arena.new()
	_arena.charging.connect(func(seconds: float) -> void: _ui.feedback("Charging for %.1f s…" % seconds))
	_arena.released.connect(func() -> void: _ui.feedback("Spell released. Left click to cast again."))
	_arena.notice.connect(func(message: String) -> void: _ui.feedback(message))
	add_child(_arena)


func _reset_world() -> void:
	_ui.close_modal()
	_replace_arena()
	_equipped = {}
	_ui.set_equipped()
	_ui.clear_inspection()
	_ui.feedback("World reset.")
