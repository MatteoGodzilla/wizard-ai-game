extends Node

signal completed(token: int, result: Dictionary)

const Intent = preload("res://spellcheck/spell_intent.gd")
const Catalog = preload("res://spellcheck/spell_catalog.gd")
const Rules = preload("res://spellcheck/magic_rules.gd")
const Providers = preload("res://Scripts/ai/provider_config.gd")
const MODEL := "gemma3:4b"
const TIME_BUDGET_MS := 70000

var power_anchors := ""
var model_requests := 0
var _request: HTTPRequest
var _started := 0
var _schema := Catalog.schema()
var _config: Dictionary = {}


func resolve(spell_name: String, description: String, token: int) -> void:
	cancel()
	_started = Time.get_ticks_msec()
	_config = Providers.resolve("SPELLCHECK")
	if not _config["error"].is_empty():
		_finish(token, {"error": _config["error"]})
		return
	var input := {"name_or_request": spell_name} if description.is_empty() else {"spell_name": spell_name, "description": description}
	_send(token, input)


func _send(token: int, input: Dictionary, correction: String = "", draft: String = "", impact_only: bool = false) -> void:
	_request = HTTPRequest.new()
	_request.timeout = maxf(0.1, (TIME_BUDGET_MS - (Time.get_ticks_msec() - _started)) / 1000.0)
	_request.max_redirects = 0
	_request.body_size_limit = 131072
	add_child(_request)
	_request.request_completed.connect(_on_chat.bind(token, input, not correction.is_empty()), CONNECT_ONE_SHOT)
	var player_data := input.duplicate()
	var system := Catalog.prompt(power_anchors)
	var schema := _schema
	if not correction.is_empty():
		player_data["validation_feedback"] = correction
		if impact_only:
			player_data["previous_interpretation"] = draft
			system = Catalog.IMPACT_REPAIR_BRIEF
			var named_attack := _is_short_invocation(input.get("name_or_request", ""))
			if named_attack:
				system += "\nFor this short invocation, choose the closest playable attack using a standard impact effect."
			schema = Catalog.schema(true, named_attack)
		else:
			player_data["invalid_draft"] = draft
			system += "\nRepair the invalid draft using the validation feedback and the original player request. Return a complete spell."
	var messages := [
		{"role": "system", "content": system},
		{"role": "user", "content": JSON.stringify(player_data)},
	]
	var headers := PackedStringArray(["Content-Type: application/json"])
	var endpoint: String = _config["endpoint"]
	var body: Dictionary
	if _config["provider"] == "ollama":
		endpoint = Providers.ollama_chat_url()
		body = {
			"model": _config["model"], "messages": messages,
			"format": schema, "stream": false, "keep_alive": "15m",
			"options": {"temperature": 0, "num_predict": 1050, "num_ctx": 4096},
		}
	else:
		headers.append("Authorization: Bearer " + str(_config["key"]))
		body = Providers.hosted_body(_config, messages, schema, "spell_intent")
	if _request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body, "", false)) != OK:
		_finish(token, {"error": "Could not reach the selected sandbox provider."})
		return
	model_requests += 1


func _on_chat(
	result: int, status: int, _headers: PackedStringArray, body: PackedByteArray,
	token: int, input: Dictionary, repaired: bool
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "Could not reach the selected sandbox provider."
		if result == HTTPRequest.RESULT_TIMEOUT:
			reason = "Spell interpretation timed out. Try preparing the spell again."
		elif result != HTTPRequest.RESULT_CANT_CONNECT and result != HTTPRequest.RESULT_CANT_RESOLVE:
			reason = "The sandbox provider did not complete the spell request."
		_finish(token, {"error": reason})
		return
	if status == 404 and _config["provider"] == "ollama":
		_finish(token, {"error": "Pull " + str(_config["model"]) + " into local Ollama to interpret new spells."})
		return
	if status != 200:
		var reason := provider_error(_config["provider"], status, body.get_string_from_utf8())
		if status == 400 and _config["provider"] == "groq" and _error_code(body.get_string_from_utf8()) == "json_validate_failed":
			if not repaired and Time.get_ticks_msec() - _started < TIME_BUDGET_MS - 1500:
				_clear_http()
				_send(token, input, "Return a single complete spell as a JSON object with no surrounding text.")
				return
		_finish(token, {"error": reason})
		return
	var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
	if _config["provider"] != "ollama":
		envelope = {"message": {"content": Providers.completion_text(envelope)}}
	var payload := decode(envelope, input.get("description", input.get("name_or_request", "")))
	if payload.has("error") and not payload.get("unintelligible", false) and not repaired:
		if Time.get_ticks_msec() - _started < TIME_BUDGET_MS - 1500:
			var draft := ""
			var impact_only: bool = payload.get("repair_impact", false)
			if envelope is Dictionary and envelope.get("message") is Dictionary:
				var content := str(envelope["message"].get("content", ""))
				if impact_only:
					var data: Variant = JSON.parse_string(content)
					if data is Dictionary:
						draft = str(data.get("meaning", "")).left(150)
				else:
					draft = content.left(1400)
			_clear_http()
			_send(token, input, payload["error"], draft, impact_only)
			return
	_finish(token, payload)


static func _error_code(body: String) -> String:
	var envelope: Variant = JSON.parse_string(body)
	if envelope is Dictionary and envelope.get("error") is Dictionary:
		return str(envelope["error"].get("code", ""))
	return ""


static func provider_error(provider: String, status: int, body: String) -> String:
	var provider_name: String = {"groq": "Groq", "google": "Google AI Studio", "openrouter": "OpenRouter", "ollama": "Ollama"}.get(provider, "The sandbox provider")
	match status:
		400:
			if provider == "groq" and _error_code(body) == "json_validate_failed":
				return "Groq could not generate valid spell JSON. Retry, or describe the arena effect in one short sentence."
			return "%s rejected the sandbox request (HTTP 400). Check that SPELLCHECK_MODEL supports JSON output." % provider_name
		401, 403:
			return "%s denied the sandbox request (HTTP %d). Check your API key and model access." % [provider_name, status]
		429:
			return "%s limited sandbox requests (HTTP 429). Try again in a moment." % provider_name
	return "%s returned HTTP %d while interpreting the spell." % [provider_name, status]


func _finish(token: int, payload: Dictionary) -> void:
	_clear_http()
	payload["source"] = "Gemma" if _config.get("provider") == "ollama" else _config.get("provider", "Sandbox AI")
	payload["model"] = _config.get("model", "")
	payload["elapsed_ms"] = Time.get_ticks_msec() - _started
	completed.emit(token, payload)


func cancel() -> void:
	_clear_http()


func _clear_http() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
		_request = null


static func name_error(spell_name: String) -> String:
	var name := spell_name.strip_edges()
	if name.length() < 3:
		return "That input is too short to identify a spell. Type its full name or describe it."
	if RegEx.create_from_string("^[bcdfghjklmnpqrstvwxz]{8,}$").search(name.to_lower()) != null:
		return "Couldn't identify a spell in that input. Try a name or describe what it does."
	return ""


static func _describes_traveling_impact(meaning: String) -> bool:
	var launch := RegEx.create_from_string("(?i)\\b(?:launch(?:es|ed)?|throws?|thrown|shoots?|shot|travels?)\\b")
	var impact := RegEx.create_from_string("(?i)\\b(?:hits?|impacts?|strikes?|cuts?|cleaves?)\\b")
	return launch.search(meaning) != null and impact.search(meaning) != null


static func _is_short_invocation(request: String) -> bool:
	var name := RegEx.create_from_string("^\\p{L}+[\\p{L}\\p{N}'’-]*(?:\\s+\\p{L}+[\\p{L}\\p{N}'’-]*){0,2}$")
	return name.search(request.strip_edges()) != null


static func decode(envelope: Variant, request: String = "") -> Dictionary:
	if not envelope is Dictionary or not envelope.get("message") is Dictionary:
		return {"error": "Expected one message containing a spell JSON object."}
	var content: Variant = envelope["message"].get("content")
	var data: Variant = JSON.parse_string(content) if content is String else null
	if not data is Dictionary:
		return {"error": "Expected a spell JSON object."}
	if data.get("status") == "UNINTELLIGIBLE":
		return {"error": "Couldn't interpret that spell. Try another name or a short description.", "unintelligible": true}
	if data.get("status") not in ["BUILT_IN", "COMPOSED"] or not data.get("meaning") is String or not data.get("reference") is String:
		return {"error": "Expected status BUILT_IN or COMPOSED, meaning and reference."}
	if data["status"] == "COMPOSED" and (not data.get("rules") is Array or data["rules"].is_empty()):
		return {"error": "COMPOSED requires at least one usable rule. Choose BUILT_IN if form and impact suffice."}
	if data["status"] == "BUILT_IN" and data.has("rules"):
		return {"error": "BUILT_IN uses only form, appearance, and standard impacts. Omit rules or choose COMPOSED."}
	if data["status"] == "BUILT_IN" and data.get("form") == "RITUAL":
		return {"error": "Direct changes require COMPOSED and at least one rule."}
	var rules: Array = data.get("rules", [])
	var form: Variant = data.get("form")
	var needs_impact := _describes_traveling_impact(data["meaning"])
	if form not in Rules.HIT_FORMS and (needs_impact or rules.any(func(rule: Variant) -> bool:
		return rule is Dictionary and rule.get("event") == "HIT"
	)):
		return {
			"error": "Your interpretation launches an attack that hits. Use a traveling form and put the described attack on impact. For ordinary structural damage use BUILT_IN with BREAK. Keep only effects from the original request.",
			"repair_impact": true,
		}
	var grounded := Catalog.grounded_rules(data, request)
	var removed_trail := grounded.size() != rules.size()
	if removed_trail:
		if form == "RITUAL" and grounded.is_empty():
			return {"error": "Caster afterimages need an explicit trail request or a caster mobility spell. Use rules that carry out the original spell."}
		rules = grounded
		data["rules"] = rules
	for rule: Variant in rules:
		if rule is Dictionary and (
			(rule.get("op") == "MULTIPLY" and rule.get("value") == 1)
			or (rule.get("op") == "ADD" and rule.get("value") == 0)
		):
			return {"error": "A rule that multiplies by 1 or adds 0 has no effect. Omit it, or use a value that achieves the requested change. For a speed boost multiply SPEED by more than 1."}
	if form in ["RITUAL", "DOMAIN", "WARD"]:
		var emitters: Variant = data.get("emitters", [])
		if emitters is Array and emitters.any(func(profile: Variant) -> bool:
			return profile is Dictionary and profile.get("phase") in ["TRAVEL", "HIT"]
		):
			return {"error": "TRAVEL and HIT emitters need a form that travels or hits. Use the requested traveling shape, or choose emitters for CAST or EXPIRE."}
	if data.has("schema_version"):
		return {"error": "Omit schema_version. The game supplies it."}
	var meaning: String = data["meaning"].strip_edges().left(150)
	var reference: String = data["reference"].strip_edges().left(60)
	if reference.to_upper() in ["NONE", "UNKNOWN", "N/A", "\""] or reference == meaning:
		reference = ""
	data.erase("status")
	data.erase("meaning")
	data.erase("reference")
	if form != "DOMAIN":
		data.erase("duration")
		if not rules.any(func(rule: Variant) -> bool:
			return rule is Dictionary and rule.get("scope") == "NEARBY" and rule.get("radius", 0) == 0
		):
			data.erase("radius")
	if form != "BEAM":
		data.erase("beam")
	data["schema_version"] = Intent.SCHEMA_VERSION
	var validated := Intent.compile(data)
	if validated.has("error"):
		if needs_impact:
			validated["repair_impact"] = true
		return validated
	return {"intent": data, "meaning": "" if removed_trail else meaning, "reference": reference, "model": MODEL}
