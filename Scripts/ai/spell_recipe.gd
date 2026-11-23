extends RefCounted
## Recipe format shared by OpenRouter replies, built-in recipes and saved files.
## A recipe has three fields: name, description and an ordered elements array.
## Parsing and validation return {valid, error, recipe}. Invalid results use an empty recipe.

const ELEMENTS: Array[String] = [
	"Aqua", "Aer", "Ignis", "Terra", "Lux", "Tenebrae", "Corpus", "Arcanum",
]
const MIN_STEPS := 6
const MAX_STEPS := 10
const MAX_INPUT_LENGTH := 120
const MAX_NAME_LENGTH := MAX_INPUT_LENGTH
const MAX_DESCRIPTION_LENGTH := 240


## Builds the response schema sent to OpenRouter. Passing a name limits the model
## to that exact string. An empty argument leaves the name unrestricted.
static func json_schema(spell_name: String = "") -> Dictionary:
	var schema := {
		"type": "object",
		"properties": {
			"name": {"type": "string", "minLength": 1, "maxLength": MAX_NAME_LENGTH},
			"description": {
				"type": "string", "minLength": 1, "maxLength": MAX_DESCRIPTION_LENGTH,
			},
			"elements": {
				"type": "array", "minItems": MIN_STEPS, "maxItems": MAX_STEPS,
				"items": {"type": "string", "enum": ELEMENTS.duplicate()},
			},
		},
		"required": ["name", "description", "elements"],
		"additionalProperties": false,
	}
	if not spell_name.is_empty():
		# A single allowed value keeps the model from choosing a different name.
		schema["properties"]["name"]["enum"] = [spell_name]
	return schema


## Parses JSON text and checks its fields. Expects the recipe object itself,
## not the outer OpenRouter response containing choices and message.content.
static func parse_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _invalid("The reply is not a JSON object.")
	return validate(parser.data)


## Checks field types, text lengths and the 6-10 supported element steps.
## Returns a copy of valid data. The name stays unchanged. The description is trimmed.
static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return _invalid("The recipe must be an object.")
	if data.size() != 3 or not data.has_all(["name", "description", "elements"]):
		return _invalid("Expected exactly name, description and elements.")
	for field in ["name", "description"]:
		if not data[field] is String:
			return _invalid("%s must be a string." % field)
		var value: String = data[field]
		var limit := MAX_NAME_LENGTH if field == "name" else MAX_DESCRIPTION_LENGTH
		if value.strip_edges().is_empty() or value.length() > limit:
			return _invalid("%s must contain 1-%d characters." % [field, limit])
	if not data["elements"] is Array:
		return _invalid("elements must be an ordered array.")
	var elements: Array = data["elements"]
	if elements.size() < MIN_STEPS or elements.size() > MAX_STEPS:
		return _invalid("The recipe must contain 6-10 element steps.")
	for element: Variant in elements:
		if not element is String or not element in ELEMENTS:
			return _invalid("Every step must use a supported element identifier.")
	# Order and repeated elements describe separate steps, so keep them as supplied.
	return {
		"valid": true,
		"error": "",
		"recipe": {
			"name": data["name"],
			"description": data["description"].strip_edges(),
			"elements": elements.duplicate(),
		},
	}


static func _invalid(message: String) -> Dictionary:
	return {"valid": false, "error": message, "recipe": {}}
