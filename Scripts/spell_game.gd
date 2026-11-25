extends Node3D
## Runs the crafting phase from a spell name to a completed recipe in the spellbook.

signal crafting_finished(spells: Array[Dictionary])

enum Phase { ENTERING, GENERATING, COUNTDOWN, CASTING, FINISHED }

@export var countdown_seconds := 3.0

@onready var generator: SpellGenerator = $SpellGenerator
@onready var caster: CastTyper = $CastTyper
@onready var element_input: ElementInput = $ElementInput
@onready var ui: Control = $Interface/SpellMakerUi
@onready var effects: Node3D = $SpellEffects

var phase := Phase.ENTERING
var current_recipe: Dictionary = {}
var current_metadata: Dictionary = {}
var _elements: Array[Enums.Element] = []
var _countdown := 0.0
var _last_countdown := -1
var _attempt_id := ""


func _ready() -> void:
	ui.craft_submitted.connect(_on_spell_submitted)
	ui.cancel_requested.connect(_cancel_crafting)
	ui.finish_requested.connect(_finish_crafting)
	ui.continue_requested.connect(_continue_crafting)
	ui.sandbox_requested.connect(_enter_sandbox)
	ui.retry_requested.connect(_retry_spell)
	ui.menu_requested.connect(_return_to_menu)
	Crafting.changed.connect(_refresh_book)
	generator.auto_save = false
	generator.recipe_ready.connect(_on_recipe_ready)
	generator.request_rejected.connect(_on_request_rejected)
	caster.update_graphics.connect(ui._on_typing_progress)
	caster.on_successful_cast.connect(_on_cast_completed)
	caster.on_failed_cast.connect(_on_cast_failed)
	ui.reset_crafting()
	_resume_entry()
	element_input.enabled = false
	if not Audio.bgm.playing:
		Audio.next_bgm()


func _exit_tree() -> void:
	if Crafting.changed.is_connected(_refresh_book):
		Crafting.changed.disconnect(_refresh_book)
	if not _attempt_id.is_empty():
		Crafting.abandon(_attempt_id)


func _on_spell_submitted(spell_name: String, description: String) -> void:
	if phase != Phase.ENTERING or Crafting.is_full():
		return
	phase = Phase.GENERATING
	ui.set_entry_enabled(false)
	var attempt: Dictionary = Crafting.begin(spell_name, description)
	if attempt.has("error"):
		_resume_entry()
		ui.show_status(attempt["error"])
		return
	_attempt_id = attempt["id"]
	ui.set_cancel_enabled(true)
	_refresh_book()
	ui.show_status("Interpreting your spell...")
	# A missing key can emit recipe_ready before generate() returns.
	generator.generate(spell_name.strip_edges(), description.strip_edges())


func _on_request_rejected(message: String) -> void:
	if phase == Phase.GENERATING:
		_abandon_attempt()
		_resume_entry()
		ui.show_status(message)


func _on_recipe_ready(recipe: Dictionary, metadata: Dictionary) -> void:
	if phase != Phase.GENERATING:
		return
	current_recipe = recipe.duplicate(true)
	current_metadata = metadata.duplicate(true)
	_elements.clear()
	for name: String in recipe["elements"]:
		var element: Enums.Element = Enums.string_to_spell(name)
		if element == Enums.Element.INVALID:
			_on_request_rejected("The recipe contains an unsupported element. Try another spell.")
			return
		_elements.append(element)
	ui.show_recipe(recipe, _elements, metadata.get("source", "") == "fallback")
	phase = Phase.COUNTDOWN
	_countdown = countdown_seconds
	_last_countdown = -1
	_update_countdown()


func _process(delta: float) -> void:
	if phase == Phase.COUNTDOWN:
		_countdown -= delta
		if _countdown <= 0.0:
			phase = Phase.CASTING
			element_input.enabled = true
			caster.start_casting_challenge(_elements)
			ui.show_cast_status(0.0, 0)
		else:
			_update_countdown()
	elif phase == Phase.CASTING:
		ui.show_cast_status(caster.elapsed_time, caster.mistakes)


func _update_countdown() -> void:
	var seconds := maxi(1, ceili(_countdown))
	if seconds != _last_countdown:
		_last_countdown = seconds
		ui.show_countdown(seconds, current_metadata.get("source", "") == "fallback")


func _on_cast_completed() -> void:
	if phase != Phase.CASTING:
		return
	element_input.enabled = false
	ui._on_typing_active_false()
	var id := _attempt_id
	_attempt_id = ""
	var error: String = Crafting.earn(id, current_recipe, caster.elapsed_time, caster.mistakes, current_metadata)
	if not error.is_empty():
		_resume_entry()
		ui.show_status(error)
		return
	effects.play_craft(_elements)
	_resume_entry(true)


func _on_cast_failed() -> void:
	if phase != Phase.CASTING:
		return
	element_input.enabled = false
	_abandon_attempt()
	ui._on_typing_active_false()
	_resume_entry()
	ui.show_status("Casting stopped. Complete the recipe to add this spell.")


func _cancel_crafting() -> void:
	if phase not in [Phase.GENERATING, Phase.COUNTDOWN, Phase.CASTING]:
		return
	phase = Phase.ENTERING
	generator.cancel()
	caster.cancel_cast()
	element_input.enabled = false
	_abandon_attempt()
	ui.hide_current_recipe()
	_resume_entry()
	ui.show_status("Crafting canceled.")


func _abandon_attempt() -> void:
	var id := _attempt_id
	_attempt_id = ""
	if not id.is_empty():
		Crafting.abandon(id)


func _resume_entry(clear_input: bool = false) -> void:
	phase = Phase.ENTERING
	ui.set_cancel_enabled(false)
	ui.set_entry_enabled(not Crafting.is_full(), clear_input)
	_refresh_book()
	if not Crafting.book.warning.is_empty():
		ui.show_status(Crafting.book.warning)
	elif Crafting.is_full():
		ui.show_status("Your spellbook is full. Review your spells to enter the sandbox.")
	else:
		ui.show_status("Enter a spell name and press Enter or Create recipe.")


func _finish_crafting() -> void:
	if phase != Phase.ENTERING:
		return
	phase = Phase.FINISHED
	ui.set_entry_enabled(false)
	_refresh_book()
	ui.show_crafting_result()
	crafting_finished.emit(Crafting.workshop_records())


func _refresh_book() -> void:
	var records: Array[Dictionary] = Crafting.workshop_records()
	ui.show_workshop_records(records, phase == Phase.ENTERING)
	ui.set_finish_enabled(phase == Phase.ENTERING)
	ui.sandbox_shortcut.disabled = phase not in [Phase.ENTERING, Phase.FINISHED]


func _retry_spell(id: String, description: String) -> void:
	if phase != Phase.ENTERING:
		return
	var error: String = Crafting.retry(id, description)
	if not error.is_empty():
		ui.show_status(error)


func _enter_sandbox() -> void:
	if phase not in [Phase.ENTERING, Phase.FINISHED]:
		return
	var error := get_tree().change_scene_to_file("res://spellcheck/sandbox.tscn")
	if error != OK:
		ui.show_status("Could not open the sandbox (%s)." % error_string(error))


func _continue_crafting() -> void:
	if phase != Phase.FINISHED:
		return
	ui.hide_crafting_result()
	_resume_entry()


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
