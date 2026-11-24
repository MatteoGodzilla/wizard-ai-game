class_name SpellGenerator
extends Node
## Requests a spell recipe from OpenRouter and checks it before passing it to the game.
##
## Add this script to a Node and connect recipe_ready before calling generate().
## A missing API key produces a fallback during the call. Network requests finish later.
## Each recipe contains name, description and an ordered elements array.

## Emitted after the input is accepted, before the API key is checked.
signal generation_started(spell_text: String)
## Emitted for both API replies and built-in recipes. metadata.source is "generated"
## or "fallback". The fallback_reason field explains why a built-in recipe was used.
signal recipe_ready(recipe: Dictionary, metadata: Dictionary)
## Reports invalid input or a second request while the first is still running.
signal request_rejected(message: String)

const Recipe = preload("res://Scripts/ai/spell_recipe.gd")
const Prompt = preload("res://Scripts/ai/spell_prompt.gd")
const Providers = preload("res://Scripts/ai/provider_config.gd")
## These templates supply the description and elements when generation fails.
## Their names are replaced with the original player input before use.
const FALLBACKS: Array[Dictionary] = [
	{
		"name": "Ember Spiral",
		"description": "A warm gust twists sparks into a ring of fire.",
		"elements": ["Ignis", "Aer", "Aer", "Ignis", "Ignis", "Arcanum"],
	},
	{
		"name": "Moonlit Tide",
		"description": "A silver wave carries a shimmer of moonlight.",
		"elements": ["Aqua", "Lux", "Aqua", "Aer", "Lux", "Aqua", "Arcanum"],
	},
	{
		"name": "Stone Bloom",
		"description": "Roots unfurl through a circle of enchanted stones.",
		"elements": ["Terra", "Terra", "Corpus", "Aqua", "Terra", "Arcanum"],
	},
	{
		"name": "Velvet Eclipse",
		"description": "A veil of shadow folds around a fading spark.",
		"elements": ["Tenebrae", "Aer", "Tenebrae", "Lux", "Tenebrae", "Arcanum", "Aer", "Tenebrae"],
	},
	{
		"name": "Arcane Pulse",
		"description": "Raw magic echoes through a bright surge of living energy.",
		"elements": ["Arcanum", "Corpus", "Lux", "Arcanum", "Aer", "Corpus", "Lux", "Arcanum"],
	},
]

## URL of the chat completions endpoint.
var endpoint := ""
## Maximum time to wait for one API request, in seconds.
var timeout_seconds := 30.0
## JSON file overwritten after each completed request when auto_save is enabled.
var save_path := Providers.game_root().path_join("spellcheck/local/latest_recipe.json")
var auto_save := true
## Most recent recipe. Its name is the exact text passed to generate().
var last_recipe: Dictionary = {}
## Source, original input, routed model, elapsed time and any fallback or save error.
var last_metadata: Dictionary = {}

var _api_key := ""
var _http: HTTPRequest
var _busy := false
var _pending_input := ""
var _started_ms := 0
var _response_model := ""
var _config: Dictionary = {}


## Sets the key for later requests. An empty value uses the environment or local config.
func set_api_key(value: String) -> void:
	_api_key = value.strip_edges()


## Checks whether a key is available. It does not send a request to verify the key.
func has_api_key() -> bool:
	return not _get_api_key().is_empty()


## Returns true while a request is running. The flag is cleared before recipe_ready is emitted.
func is_busy() -> bool:
	return _busy


func cancel() -> void:
	_busy = false
	_pending_input = ""
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.request_completed.disconnect(_on_request_completed)
		_http.queue_free()
		_http = null


# Both the game and the demo read the same local key without saving it in scenes.
func _get_api_key() -> String:
	if not _api_key.is_empty():
		return _api_key
	return Providers.resolve("WORKSHOP")["key"]


## Accepts a spell name of 1-120 characters, preserving its case and spaces.
## OK means the request was accepted. The result and its source arrive through recipe_ready.
## Empty or oversized names return ERR_INVALID_PARAMETER. A concurrent call returns
## ERR_BUSY. Both errors emit request_rejected without starting another request.
func generate(spell_text: String, description: String = "") -> Error:
	if _busy:
		request_rejected.emit("A recipe request is already in progress.")
		return ERR_BUSY
	if spell_text.strip_edges().is_empty() or spell_text.length() > Recipe.MAX_INPUT_LENGTH:
		request_rejected.emit("Enter a spell name with 1-%d characters." % Recipe.MAX_INPUT_LENGTH)
		return ERR_INVALID_PARAMETER
	if description.length() > 400:
		request_rejected.emit("The optional description can contain up to 400 characters.")
		return ERR_INVALID_PARAMETER
	_busy = true
	_pending_input = spell_text
	_response_model = ""
	_started_ms = Time.get_ticks_msec()
	generation_started.emit(spell_text)

	_config = Providers.resolve("WORKSHOP")
	var key: String = _config["key"] if _api_key.is_empty() else _api_key
	if not _config["error"].is_empty() and (key.is_empty() or _config["endpoint"].is_empty() or _config["model"].is_empty()):
		_finish_fallback(_config["error"])
		return OK
	if _http == null:
		_http = HTTPRequest.new()
		_http.name = "OpenRouterRequest"
		_http.max_redirects = 0
		_http.body_size_limit = 256 * 1024
		_http.request_completed.connect(_on_request_completed)
		add_child(_http)
	_http.timeout = timeout_seconds
	var headers := PackedStringArray([
		"Authorization: Bearer " + key,
		"Content-Type: application/json",
	])
	var error := _http.request(
		_config["endpoint"] if endpoint.is_empty() else endpoint, headers, HTTPClient.METHOD_POST,
		JSON.stringify(Prompt.build_request(spell_text, description, _config))
	)
	if error != OK:
		_finish_fallback("Could not start the API request (%s)." % error_string(error))
	return OK


# Check the HTTP response first, then parse the model text as a recipe.
func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if not _busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "The API request failed (network result %d)." % result
		if result == HTTPRequest.RESULT_TIMEOUT:
			reason = "The API request timed out."
		_finish_fallback(reason)
		return
	if response_code < 200 or response_code >= 300:
		# Provider error bodies can contain request data, so report only the status.
		_finish_fallback("The workshop provider returned HTTP %d." % response_code)
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_finish_fallback("The workshop provider returned an invalid response envelope.")
		return
	var envelope: Dictionary = parser.data
	var response_model: Variant = envelope.get("model", "")
	if response_model is String:
		_response_model = response_model
	var recipe_text: Variant = Providers.completion_text(envelope)
	if not recipe_text is String:
		_finish_fallback("The model did not return a complete recipe.")
		return
	var checked := Recipe.parse_json(recipe_text)
	if not checked["valid"]:
		_finish_fallback("Invalid model recipe: " + checked["error"])
		return
	var model_used: Variant = envelope.get("model", _config["model"])
	if not model_used is String:
		model_used = _config["model"]
	_finish(checked["recipe"], "generated", "", model_used)


# Built-in recipes go through the same validator and save path as API results.
func _finish_fallback(reason: String) -> void:
	var checked := Recipe.validate(FALLBACKS.pick_random())
	_finish(checked["recipe"], "fallback", reason, _response_model)


# Save errors are included in metadata. The caller still receives the valid recipe.
func _finish(recipe: Dictionary, source: String, reason: String, model_used: String) -> void:
	last_recipe = recipe.duplicate(true)
	# Always keep the player name, including when the recipe comes from a template.
	last_recipe["name"] = _pending_input
	last_metadata = {
		"source": source,
		"input": _pending_input,
		"model": model_used,
		"fallback_reason": reason,
		"elapsed_seconds": (Time.get_ticks_msec() - _started_ms) / 1000.0,
		"saved_path": "",
		"save_error": "",
	}
	if auto_save:
		var error := save_recipe(last_recipe)
		if error == OK:
			last_metadata["saved_path"] = save_path
		else:
			last_metadata["save_error"] = error_string(error)
	_busy = false
	recipe_ready.emit(last_recipe.duplicate(true), last_metadata.duplicate(true))


## Validates the recipe, creates the parent directory and overwrites save_path.
## The file contains only name, description and elements. Returns a file error or OK.
func save_recipe(recipe: Dictionary) -> Error:
	var checked := Recipe.validate(recipe)
	if not checked["valid"]:
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(checked["recipe"], "\t") + "\n")
	return file.get_error()


## Reads save_path and returns {valid, error, recipe}. Missing or invalid files
## return valid = false with a readable error. The last_recipe value stays unchanged.
func load_saved_recipe() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {"valid": false, "error": "No saved recipe yet.", "recipe": {}}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": "Could not read the saved recipe.", "recipe": {}}
	return Recipe.parse_json(file.get_as_text())
