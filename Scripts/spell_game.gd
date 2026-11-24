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

var spell_book := SpellBook.new()
var save_path := SpellBook.SAVE_PATH
var phase := Phase.ENTERING
var current_recipe: Dictionary = {}
var current_metadata: Dictionary = {}
var _elements: Array[Enums.Element] = []
var _countdown := 0.0
var _last_countdown := -1


func _ready() -> void:
	ui.spell_submitted.connect(_on_spell_submitted)
	ui.finish_requested.connect(_finish_crafting)
	ui.continue_requested.connect(_continue_crafting)
	ui.menu_requested.connect(_return_to_menu)
	generator.recipe_ready.connect(_on_recipe_ready)
	generator.request_rejected.connect(_on_request_rejected)
	caster.update_graphics.connect(ui._on_typing_progress)
	caster.on_successful_cast.connect(_on_cast_completed)
	caster.on_failed_cast.connect(_on_cast_failed)
	ui.reset_crafting()
	element_input.enabled = false
	if not Audio.bgm.playing:
		Audio.next_bgm()


func _on_spell_submitted(spell_name: String) -> void:
	if phase != Phase.ENTERING or spell_book.is_full():
		return
	phase = Phase.GENERATING
	ui.set_entry_enabled(false)
	ui.show_status("Interpreting your spell...")
	# A missing key can emit recipe_ready before generate() returns.
	generator.generate(spell_name)


func _on_request_rejected(message: String) -> void:
	if phase == Phase.GENERATING:
		phase = Phase.ENTERING
		ui.show_status(message)
		ui.set_entry_enabled(true)


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
	var error := spell_book.add_spell(current_recipe, caster.elapsed_time, caster.mistakes, current_metadata)
	phase = Phase.ENTERING
	if error != OK:
		ui._on_typing_active_false()
		ui.set_entry_enabled(not spell_book.is_full())
		ui.show_status("Could not add this spell to the spellbook. Try again.")
		return
	ui.add_spell_entry(spell_book.spells.back())
	effects.play_craft(_elements)
	_resume_entry(true)


func _on_cast_failed() -> void:
	element_input.enabled = false
	phase = Phase.ENTERING
	ui._on_typing_active_false()
	ui.show_status("Casting stopped. Complete the recipe to add this spell.")
	ui.set_entry_enabled(true)


func _resume_entry(clear_input: bool = false) -> void:
	phase = Phase.ENTERING
	ui.set_entry_enabled(not spell_book.is_full(), clear_input)
	ui.set_finish_enabled(not spell_book.spells.is_empty())
	if spell_book.is_full():
		ui.show_status("Your spellbook is full. Move to battlefield when you are ready.")
	else:
		ui.show_status("Craft another spell or finish with your current spellbook.")


## Only completed recipes are exported. A save failure leaves the collection editable.
## The next phase can connect crafting_finished and load SpellBook.SAVE_PATH.
func _finish_crafting() -> void:
	if phase != Phase.ENTERING or spell_book.spells.is_empty():
		return
	var error := spell_book.save_to_file(save_path)
	if error != OK:
		ui.show_status("Could not save your spellbook (%s). Try again." % error_string(error))
		return
	phase = Phase.FINISHED
	ui.set_entry_enabled(false)
	ui.show_crafting_result(spell_book)
	crafting_finished.emit(spell_book.spells.duplicate(true))


func _continue_crafting() -> void:
	if phase != Phase.FINISHED:
		return
	ui.hide_crafting_result()
	_resume_entry()


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
