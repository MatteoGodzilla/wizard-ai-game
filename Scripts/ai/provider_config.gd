extends RefCounted

const ENDPOINTS := {
	"openrouter": "https://openrouter.ai/api/v1/chat/completions",
	"google": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
	"groq": "https://api.groq.com/openai/v1/chat/completions",
}
const KEY_NAMES := {"openrouter": "OPENROUTER_API_KEY", "google": "GEMINI_API_KEY", "groq": "GROQ_API_KEY"}


static func game_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()


static func ollama_chat_url() -> String:
	var setting_value := setting("SPELLCHECK_OLLAMA_PORT", "11434")
	var port := setting_value.to_int() if setting_value.is_valid_int() else 11434
	if port < 1 or port > 65535:
		port = 11434
	return "http://127.0.0.1:%d/api/chat" % port


static func setting(name: String, default: String = "") -> String:
	if OS.has_environment(name):
		return OS.get_environment(name).strip_edges()
	var file := FileAccess.open(game_root().path_join(".env"), FileAccess.READ)
	if file == null:
		return default
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or not line.contains("="):
			continue
		if line.get_slice("=", 0).strip_edges() != name:
			continue
		var value := line.substr(line.find("=") + 1).strip_edges()
		if value.length() >= 2 and ((value.begins_with('"') and value.ends_with('"')) or (value.begins_with("'") and value.ends_with("'"))):
			value = value.substr(1, value.length() - 2)
		return value
	return default


static func resolve(role: String) -> Dictionary:
	var default_provider := "openrouter" if role == "WORKSHOP" else "ollama"
	var provider := setting(role + "_PROVIDER", default_provider).to_lower()
	var default_model := ""
	if provider == "openrouter" and role == "WORKSHOP":
		default_model = "openrouter/free"
	elif provider == "ollama":
		default_model = "gemma3:4b"
	var model := setting(role + "_MODEL", default_model)
	var key := setting(KEY_NAMES.get(provider, "")) if ENDPOINTS.has(provider) else ""
	if key.is_empty() and provider == "openrouter" and role == "WORKSHOP":
		var legacy := ConfigFile.new()
		if legacy.load(game_root().path_join("openrouter.local.cfg")) == OK:
			key = str(legacy.get_value("openrouter", "api_key", "")).strip_edges()
	var error := ""
	if not ENDPOINTS.has(provider) and (provider != "ollama" or role == "WORKSHOP"):
		error = "Unsupported AI provider for " + role.to_lower() + "."
	elif model.is_empty():
		error = "Set " + role + "_MODEL for the selected provider."
	elif provider != "ollama" and key.is_empty():
		error = "Set " + str(KEY_NAMES[provider]) + " for the selected provider."
	return {"provider": provider, "model": model, "key": key, "endpoint": ENDPOINTS.get(provider, ""), "error": error}


static func hosted_body(config: Dictionary, messages: Array, schema: Dictionary, schema_name: String, strict_recipe: bool = false) -> Dictionary:
	var body := {"model": config["model"], "messages": messages.duplicate(true), "stream": false}
	match config["provider"]:
		"openrouter":
			body["provider"] = {"require_parameters": true}
			if strict_recipe:
				body["max_tokens"] = 8192
				body["reasoning"] = {"effort": "low", "exclude": true}
				body["response_format"] = _schema_format(schema_name, schema, true)
			else:
				body["max_tokens"] = 1536
				body["response_format"] = {"type": "json_object"}
		"groq":
			body["max_completion_tokens"] = 1536
			body["response_format"] = {"type": "json_object"}
		"google":
			body["max_tokens"] = 1536
			# Keep the rule types and nested properties while moving game-specific
			# constraints to the prompt and local validation.
			var shape: Dictionary
			if strict_recipe:
				shape = _google_shape([schema])
				shape["required"] = schema["required"]
			else:
				shape = _google_shape(schema["anyOf"])
				shape["required"] = ["status"]
			body["response_format"] = _schema_format(schema_name, shape, false)
	if not strict_recipe or config["provider"] != "openrouter":
		body["messages"][0]["content"] += "\nReturn JSON matching this schema: " + JSON.stringify(schema)
	return body


static func _google_shape(definitions: Array) -> Dictionary:
	var types := {}
	var fields := {}
	var items := []
	for definition: Dictionary in definitions:
		if definition.has("anyOf"):
			var branches: Array = definition["anyOf"]
			return _google_shape(branches)
		var kind: String = definition["type"]
		types[kind] = true
		for field: String in definition.get("properties", {}):
			if not fields.has(field):
				fields[field] = []
			fields[field].append(definition["properties"][field])
		if kind == "array":
			items.append(definition["items"])
	if types.size() > 1:
		var alternatives := []
		for kind: String in types:
			alternatives.append({"type": kind})
		return {"anyOf": alternatives}
	var shape := {"type": types.keys()[0]}
	if shape["type"] == "object":
		shape["properties"] = {}
		for field: String in fields:
			shape["properties"][field] = _google_shape(fields[field])
	elif shape["type"] == "array":
		shape["items"] = _google_shape(items)
	return shape


static func _schema_format(name: String, schema: Dictionary, strict: bool) -> Dictionary:
	return {"type": "json_schema", "json_schema": {"name": name, "schema": schema, "strict": strict}}


static func completion_text(envelope: Variant) -> Variant:
	if not envelope is Dictionary or envelope.has("error"):
		return null
	var choices: Variant = envelope.get("choices")
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary or choices[0].get("finish_reason") != "stop":
		return null
	var message: Variant = choices[0].get("message")
	if not message is Dictionary or message.get("refusal") not in [null, ""] or not message.get("content") is String:
		return null
	return message["content"]
