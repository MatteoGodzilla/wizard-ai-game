extends Node3D

const Arena = preload("res://spellcheck/arena.gd")
const CastingUI = preload("res://spellcheck/casting_ui.gd")
const Spellbook = preload("res://spellcheck/spellbook.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const Resolver = preload("res://spellcheck/spell_resolver.gd")
const SPELLBOOK_PATH := "user://spellcheck_spellbook_v1.json"

var _arena: Arena
var _ui: CastingUI
var _book: Spellbook
var _resolver: Resolver
var _equipped: Dictionary = {}
var _pending_entry: Dictionary = {}
var _request_token := 0
var _failures: Dictionary = {}


func _ready() -> void:
	_book = Spellbook.new(SPELLBOOK_PATH, Resolver.CACHE_IDENTITY)
	_resolver = Resolver.new()
	_resolver.power_anchors = _book.power_anchors()
	_resolver.completed.connect(_on_resolved)
	add_child(_resolver)
	_replace_arena()
	_ui = CastingUI.new()
	_ui.submitted.connect(_submit)
	_ui.create_requested.connect(_create_entry)
	_ui.book_requested.connect(_open_book)
	_ui.reset_requested.connect(_reset_world)
	_ui.modal_changed.connect(func(open: bool) -> void: _arena.input_enabled = not open)
	add_child(_ui)
	if _book.warning.is_empty():
		_ui.feedback("Try Patronus or Fireball.")
	else:
		_ui.feedback(_book.warning, true)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
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
	if _ui.has_modal() or not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if not _pending_entry.is_empty():
		_ui.feedback("Still interpreting " + _pending_entry["name"] + "…")
		return
	if _equipped.is_empty():
		return
	if not _arena.cast(_equipped, event.position):
		_ui.feedback("Wait a moment before casting again.", true)
	get_viewport().set_input_as_handled()


func _open_book(selected: String = "") -> void:
	_ui.open_book(_book.entries, _state_for, selected)


func _prefix_names(text: String) -> Array[String]:
	var key := _book.normalize(text)
	var names: Array[String] = []
	if key.length() < 2:
		return names
	for entry: Dictionary in _book.entries.values():
		if _book.normalize(entry["name"]).begins_with(key):
			names.append(entry["name"])
	names.sort_custom(func(a: String, b: String) -> bool: return a.nocasecmp_to(b) < 0)
	return names.slice(0, 4)


func _state_for(id: String) -> String:
	if id == _pending_entry.get("entry_id"):
		return "INTERPRETING"
	if not _book.resolution(id).is_empty():
		return "READY"
	return "ERROR" if _failures.has(id) else "NEW"


func _create_entry(name_text: String, description: String) -> void:
	var result := _book.add_entry(name_text, description)
	if result.has("error"):
		_ui.add_error(result["error"])
		return
	_open_book(result["entry_id"])
	_ui.feedback("Spell added. Use its name to cast.")


func _submit(text: String) -> void:
	_ui.close_modal()
	if _book.normalize(text).is_empty():
		return
	var id := _book.lookup(text)
	var entry: Dictionary = _book.ad_hoc(text) if id.is_empty() else _book.entries[id]
	if entry["entry_id"] == _pending_entry.get("entry_id"):
		_ui.feedback("Still interpreting " + entry["name"] + "…")
		return
	_cancel_pending()
	var name_error := Resolver.name_error(text) if id.is_empty() and entry["description"].is_empty() else ""
	if not name_error.is_empty():
		_report_failure(entry, {
			"error": name_error,
			"source": "Input check",
		})
		return
	var lookup_started := Time.get_ticks_msec()
	var result := _book.cached(entry) if id.is_empty() else _book.resolution(id)
	if not result.is_empty():
		result["elapsed_ms"] = Time.get_ticks_msec() - lookup_started
		_equip_definition(entry, result)
		return
	if entry["resolution_policy"] == "PRESET":
		_report_failure(entry, {"source": "Preset", "error": "The shipped definition is unavailable."})
		return
	_failures.erase(id)
	_pending_entry = entry
	_ui.feedback("Interpreting " + entry["name"] + "…")
	_resolver.resolve(entry["name"], entry["description"], _request_token)


func _on_resolved(token: int, result: Dictionary) -> void:
	if token != _request_token or _pending_entry.is_empty():
		return
	var entry := _pending_entry
	_pending_entry = {}
	if result.has("error"):
		_report_failure(entry, result)
	else:
		_equip_definition(entry, result)
	_ui.refresh_book()


func _equip_definition(entry: Dictionary, result: Dictionary) -> void:
	var checked := Intent.compile(result["intent"])
	if checked.has("error"):
		result.erase("intent")
		result["error"] = checked["error"]
		_report_failure(entry, result)
		return
	var saved := true
	if result["source"] == "Gemma":
		saved = _book.remember(entry, result)
	_equipped = checked["spell"]
	result["compiled"] = _equipped
	_ui.set_equipped(entry["name"])
	_ui.inspect(entry, result)
	if not saved:
		_ui.feedback("Learned for this session. The definition could not be saved.", true)
	else:
		_ui.feedback("%s  ·  %s\nLeft click to cast." % [result["source"], _equipped["form"].capitalize()])


func _report_failure(entry: Dictionary, result: Dictionary) -> void:
	if _book.entries.has(entry["entry_id"]):
		_failures[entry["entry_id"]] = true
	var hint: String = result["error"]
	if result.get("unintelligible", false):
		var suggestions := _book.suggestions(entry["name"])
		if not suggestions.is_empty():
			hint = "Did you mean %s?" % _book.entries[suggestions[0]]["name"]
	_ui.feedback(hint, true)
	_ui.inspect(entry, result)


func _cancel_pending() -> void:
	_request_token += 1
	_pending_entry = {}
	_resolver.cancel()
	_ui.refresh_book()


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
	_cancel_pending()
	_ui.close_modal()
	_replace_arena()
	_equipped = {}
	_ui.set_equipped()
	_ui.clear_inspection()
	_ui.feedback("World reset.")
