extends SceneTree

const Providers = preload("res://Scripts/ai/provider_config.gd")
const WorkshopPrompt = preload("res://Scripts/ai/spell_prompt.gd")
const SandboxCatalog = preload("res://spellcheck/spell_catalog.gd")

var _failures := 0


func _initialize() -> void:
	for provider: String in ["openrouter", "google", "groq"]:
		var config := {"provider": provider, "model": "fixture-model"}
		var workshop := WorkshopPrompt.build_request("Stone Song", "Turn a stone blue.", config)
		var sandbox := Providers.hosted_body(config, [{"role": "system", "content": "Return JSON."}], SandboxCatalog.schema(), "spell_intent")
		for body: Dictionary in [workshop, sandbox]:
			_check(body["model"] == "fixture-model", "each request uses its configured model")
			_check(body.has("provider") == (provider == "openrouter"), "only OpenRouter receives routing options")
			_check(body.has("response_format"), "each provider receives a JSON response format")
		_check(workshop.has("reasoning") == (provider == "openrouter"), "only OpenRouter recipe calls receive reasoning options")
		if provider == "openrouter":
			_check(workshop["response_format"]["json_schema"]["strict"], "the OpenRouter recipe requests a strict schema")
		elif provider == "google":
			var properties: Dictionary = sandbox["response_format"]["json_schema"]["schema"]["properties"]
			_check(properties["rules"]["items"]["properties"]["value"].has("anyOf"), "the Google sandbox can return both textual and numeric rule values")
			_check(properties["beam"]["properties"].has("lanes"), "the Google sandbox can return nested beam settings")
		else:
			_check(sandbox["response_format"]["type"] == "json_object", "Groq uses JSON Object Mode")
		var player: Dictionary = JSON.parse_string(workshop["messages"][1]["content"])
		_check(player["spell_text"] == "Stone Song" and player["description"] == "Turn a stone blue.", "workshop receives the name and description")
	var envelope := {"choices": [{"finish_reason": "stop", "message": {"content": "{}"}}]}
	_check(Providers.completion_text(envelope) == "{}", "compatible reply normalizes JSON text")
	envelope["choices"][0]["finish_reason"] = "length"
	_check(Providers.completion_text(envelope) == null, "truncated reply is rejected")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
