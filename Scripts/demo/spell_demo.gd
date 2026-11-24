extends Control
## Test screen for submitting spell names and inspecting the returned recipes.
## SpellGenerator handles requests and files. This script displays its signals.
## The status distinguishes generated recipes from built-in fallbacks.

@onready var _generator: SpellGenerator = $SpellGenerator
@onready var _spell_input: LineEdit = %SpellInput

@onready var _generate_button: Button = %GenerateButton
@onready var _read_button: Button = %ReadButton
@onready var _status: Label = %Status
@onready var _spell_name: Label = %SpellName
@onready var _description: Label = %Description
@onready var _elements: Label = %Elements
@onready var _json_output: TextEdit = %JsonOutput
@onready var _save_info: Label = %SaveInfo


func _ready() -> void:
	_generate_button.pressed.connect(_generate)
	_spell_input.text_submitted.connect(func(_text: String) -> void: _generate())
	_read_button.pressed.connect(_read_saved)
	_generator.generation_started.connect(_on_started)
	_generator.recipe_ready.connect(_on_recipe_ready)
	_generator.request_rejected.connect(_on_rejected)
	_spell_input.grab_focus()


## Submits the current name with the shared local OpenRouter configuration.
func _generate() -> void:
	_generator.generate(_spell_input.text)


# Clear the previous result and block further submissions while the request runs.
func _on_started(_spell_text: String) -> void:
	_set_busy(true)
	_status.text = "Waiting for openrouter/free..."
	_spell_name.text = "Preparing recipe..."
	_description.text = ""
	_elements.text = ""
	_json_output.text = ""
	_save_info.text = ""


# A valid recipe can still have a save error, so display both results separately.
func _on_recipe_ready(recipe: Dictionary, metadata: Dictionary) -> void:
	_set_busy(false)
	_show_recipe(recipe)
	if metadata["source"] == "generated":
		_status.text = "AI recipe received and validated. Model: %s" % metadata["model"]
	else:
		_status.text = "BUILT-IN FALLBACK: %s" % metadata["fallback_reason"]
	if metadata["save_error"].is_empty():
		_save_info.text = "Saved JSON: " + ProjectSettings.globalize_path(metadata["saved_path"])
	else:
		_save_info.text = "Recipe is ready, but saving failed: " + metadata["save_error"]


func _on_rejected(message: String) -> void:
	_status.text = message


## Reloads the JSON file through the same validation used for model replies.
func _read_saved() -> void:
	var checked := _generator.load_saved_recipe()
	if not checked["valid"]:
		_status.text = checked["error"]
		return
	_show_recipe(checked["recipe"])
	_status.text = "Saved JSON read and validated."
	_save_info.text = "Read from: " + ProjectSettings.globalize_path(_generator.save_path)


# Number each occurrence separately, including repeated elements.
func _show_recipe(recipe: Dictionary) -> void:
	_spell_name.text = recipe["name"]
	_description.text = recipe["description"]
	var steps := PackedStringArray()
	for index: int in range(recipe["elements"].size()):
		steps.append("%d. %s" % [index + 1, recipe["elements"][index]])
	_elements.text = "  >  ".join(steps)
	_json_output.text = JSON.stringify(recipe, "\t")


func _set_busy(busy: bool) -> void:
	_generate_button.disabled = busy
	_read_button.disabled = busy
	_spell_input.editable = not busy
