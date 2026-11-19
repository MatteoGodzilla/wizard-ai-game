extends Node

signal completed(token: int, result: Dictionary)

const Intent = preload("res://spellcheck/spell_intent.gd")
const MODEL := "laya:421m-typed-decisions-bf16"
const BURST_WORD := "\\b(burst(?:s|ing)?|explod(?:e|es|ing)|explosions?|flash(?:es|ing)?|pop(?:s|ping)?|detonat(?:e|es|ion))\\b"
const IMPACT_WORDS := "\\b(on|upon) (an? |the )?(impact|contact|hit|collision|hitting)\\b|\\bwhen\\b[^.!?]{0,50}\\b(hit[s]?|strikes?|collides?|lands?)\\b"
const NO_BURST := "\\b(no|without|never|does not|doesn't|do not|don't)\\b[^.!?]{0,24}" + BURST_WORD
const QUESTIONS := {
	"support": {
		"type": "choice",
		"instructions": "Can the requested spell be shown faithfully as a forward moving magic bolt or ball with an optional cosmetic impact flash?",
		"criteria": {
			"SUPPORTED": "A forward projectile, fireball, bolt, or thrown orb. Any impact burst is cosmetic or does not require a specific change to the world.",
			"UNSUPPORTED": "Requires a beam, field, hover, ice, wetness, destruction, healing, another change to the world, or another unsupported delivery.",
			"UNCLEAR": "Unclear or unrelated text without an identifiable spell delivery.",
		},
	},
	"palette": {
		"type": "choice",
		"instructions": "What is the specified color of the projectile? A specified color overrides its element.",
		"criteria": {
			"GREEN": "Green, lime, or emerald.",
			"BLUE": "Blue, icy blue, or cyan.",
			"VIOLET": "Violet, purple, or lavender.",
			"ORANGE": "Orange, or an ordinary fireball with no explicit other color.",
			"RED": "Red, crimson, or scarlet.",
			"WHITE": "White or silver.",
			"YELLOW": "Yellow or gold.",
			"DEFAULT": "No described color and no ordinary fire.",
		},
	},
	"particle": {
		"type": "choice",
		"instructions": "Which traveling particle style does the description call for? Explicit smoke overrides ordinary fire sparks.",
		"criteria": {
			"SMOKE": "Smoke, smoky, vapor, or wispy clouds.",
			"SPARKS": "Sparks, sparking, embers, or fiery sparks.",
			"MAGIC": "Glitter, magical motes, or a glittering trail.",
			"NONE": "No particle trail described.",
		},
	},
	"impact": {
		"type": "choice",
		"instructions": "Should the projectile visibly burst when it strikes something?",
		"criteria": {
			"BURST": "Explicit explosion, flash, pop or burst on hit, or an exploding fireball.",
			"NONE": "No impact effect is specified, or the projectile vanishes quietly.",
		},
	},
}

var _request: HTTPRequest


func resolve(description: String, token: int) -> void:
	cancel()
	var started := Time.get_ticks_msec()
	_request = HTTPRequest.new()
	_request.body_size_limit = 65536
	_request.max_redirects = 0
	add_child(_request)
	_request.timeout = 2.0
	_request.request_completed.connect(
		_on_models.bind(description, token, started), CONNECT_ONE_SHOT
	)
	if _request.request(base_url() + "/api/tags") != OK:
		_finish(token, started, {"error": "Could not start the local Ollama request."})


func cancel() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null


func _on_models(
	result: int, status: int, _headers: PackedStringArray, body: PackedByteArray,
	description: String, token: int, started: int
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_finish(token, started, {"error": "Local Ollama is unavailable at " + base_url() + "."})
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	var digest := ""
	if data is Dictionary and data.get("models") is Array:
		for model: Variant in data["models"]:
			if model is Dictionary and model.get("name") == MODEL:
				digest = str(model.get("digest", ""))
				break
	if digest.is_empty():
		_finish(token, started, {"error": "Pull " + MODEL + " into the local Ollama server, then retry."})
		return

	var ask_impact := has_impact_burst_cue(description)
	var questions := QUESTIONS.duplicate()
	if not ask_impact:
		questions.erase("impact")
	_request.timeout = 45.0
	_request.request_completed.connect(
		_on_decisions.bind(token, started, digest, ask_impact), CONNECT_ONE_SHOT
	)
	var payload := JSON.stringify({"model": MODEL, "state": description, "questions": questions})
	var sent := _request.request(
		base_url() + "/v1/systemone", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, payload
	)
	if sent != OK:
		_finish(token, started, {"error": "Could not start the Laya interpretation."})


func _on_decisions(
	result: int, status: int, _headers: PackedStringArray, body: PackedByteArray,
	token: int, started: int, digest: String, ask_impact: bool
) -> void:
	if result == HTTPRequest.RESULT_TIMEOUT:
		_finish(token, started, {"error": "Laya timed out. Press Enter on the spell name to retry."})
		return
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_finish(token, started, {
			"error": "Laya did not return a decision (HTTP %d). Ollama 0.40.0+ is required." % status
		})
		return
	var payload := decode(JSON.parse_string(body.get_string_from_utf8()), ask_impact)
	payload["model_digest"] = digest
	_finish(token, started, payload)


func _finish(token: int, started: int, payload: Dictionary) -> void:
	cancel()
	payload["elapsed_ms"] = Time.get_ticks_msec() - started
	completed.emit(token, payload)


static func has_impact_burst_cue(description: String) -> bool:
	var text := description.to_lower()
	return (
		RegEx.create_from_string(BURST_WORD).search(text) != null
		and RegEx.create_from_string(IMPACT_WORDS).search(text) != null
		and RegEx.create_from_string(NO_BURST).search(text) == null
	)


static func decode(data: Variant, ask_impact: bool = true) -> Dictionary:
	if not data is Dictionary or not data.get("answers") is Dictionary:
		return {"error": "Laya returned an invalid decision response."}
	var choices := {"impact": "NONE"}
	for key: String in QUESTIONS:
		if key == "impact" and not ask_impact:
			continue
		var answer: Variant = data["answers"].get(key)
		if not answer is Dictionary or answer.get("type") != "choice":
			return {"error": "Laya did not return a valid %s decision." % key}
		var choice: Variant = answer.get("choice")
		if not choice is String or not QUESTIONS[key]["criteria"].has(choice):
			return {"error": "Laya returned an unsupported %s decision." % key}
		choices[key] = choice

	match choices["support"]:
		"UNCLEAR":
			return {"error": "Describe a forward-moving ball or bolt and its visible effect."}
		"UNSUPPORTED":
			return {"error": "This description needs effects beyond the projectile arena."}
	return {"intent": Intent.create("ORB", choices["palette"], choices["particle"], choices["impact"], 0)}


static func base_url() -> String:
	var setting := OS.get_environment("SPELLCHECK_OLLAMA_PORT")
	var port := setting.to_int() if setting.is_valid_int() else 11434
	if port < 1 or port > 65535:
		port = 11434
	return "http://127.0.0.1:%d" % port
