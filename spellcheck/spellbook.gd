extends RefCounted

const Intent = preload("res://spellcheck/spell_intent.gd")
const Recipe = preload("res://Scripts/ai/spell_recipe.gd")
const Providers = preload("res://Scripts/ai/provider_config.gd")
const SEED_PATH := "res://spellcheck/seed_spellbook.json"
const SAVE_PATH := "spellcheck/local/spellbook.json"
const SAVE_FORMAT := "workshop-v1"
const STARTER_ID := "classic.fireball"
const NAME_LIMIT := 120
const DESCRIPTION_LIMIT := 400
const MAX_CRAFTS := 10

var entries: Dictionary = {}
var warning := ""
var _names: Dictionary = {}
var _presets: Dictionary = {}
var _preset_names: Dictionary = {}
var _references: Dictionary = {}
var _records: Dictionary = {}
var _power_anchors: Array[String] = []
var _whitespace := RegEx.create_from_string("(*UCP)\\s+")
var _save_path: String
var _read_only := false


func _init(save_path: String = "") -> void:
	if save_path.is_empty():
		_save_path = Providers.game_root().path_join(SAVE_PATH)
	else:
		_save_path = ProjectSettings.globalize_path(save_path)
	_load_seeds()
	var starter: Dictionary = _presets.get(STARTER_ID, {})
	if not starter.is_empty():
		_index(starter)
	if FileAccess.file_exists(_save_path):
		_load_records()


func _load_seeds() -> void:
	var seed: Variant = _read_json(SEED_PATH)
	if not seed is Dictionary or not seed.get("entries") is Array:
		warning = "The shipped spell catalog could not be read."
		return
	for entry: Variant in seed["entries"]:
		if not entry is Dictionary or not Intent.compile(entry.get("intent")).has("spell"):
			warning = "A shipped spell definition could not be read."
			continue
		_presets[entry["entry_id"]] = entry
		for spelling: String in [entry["name"]] + entry["aliases"]:
			_preset_names[normalize(spelling)] = entry["entry_id"]
		if entry.get("balance") is String:
			_power_anchors.append("%s (%s)" % [entry["name"], entry["balance"]])
	for reference: Dictionary in seed.get("reference_descriptions", []):
		for spelling: String in reference["names"]:
			_references[normalize(spelling)] = reference["description"]


func _load_records() -> void:
	var saved: Variant = _read_json(_save_path)
	if not saved is Dictionary or saved.get("format") != SAVE_FORMAT or not saved.get("spells") is Dictionary:
		_invalid_save()
		return
	var stored: Dictionary = saved["spells"]
	if stored.size() > MAX_CRAFTS:
		_invalid_save()
		return
	var claimed_names := {normalize(_presets.get(STARTER_ID, {}).get("name", "Fireball")): true}
	var claimed_presets := {STARTER_ID: true}
	for id: String in stored:
		var record: Variant = stored[id]
		if not _valid_record(record) or record["id"] != id or claimed_names.has(normalize(record["name"])):
			_invalid_save()
			return
		var preset_id: String = record["preset_id"]
		if not preset_id.is_empty() and claimed_presets.has(preset_id):
			_invalid_save()
			return
		claimed_names[normalize(record["name"])] = true
		if not preset_id.is_empty():
			claimed_presets[preset_id] = true
	_records = stored
	for record: Dictionary in _records.values():
		_publish(record)


func _invalid_save() -> void:
	_read_only = true
	warning = "This spellbook cannot be loaded. Close the game and move spellcheck/local/spellbook.json to start fresh."


func normalize(value: String) -> String:
	return _whitespace.sub(value, " ", true).strip_edges().to_lower()


func lookup(text: String) -> String:
	return _names.get(normalize(text), "")


func preset_for(text: String) -> Dictionary:
	return _presets.get(_preset_names.get(normalize(text), ""), {})


func reference_description(name: String) -> String:
	return _references.get(normalize(name), "")


func power_anchors() -> String:
	return "\n".join(_power_anchors)


func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _records.values():
		result.append(record.duplicate(true))
	return result


func record(id: String) -> Dictionary:
	return _records.get(id, {}).duplicate(true)


func save_record(record_data: Dictionary) -> bool:
	if _read_only or not _valid_record(record_data):
		return false
	var next := _records.duplicate()
	next[record_data["id"]] = record_data.duplicate(true)
	if next.size() > MAX_CRAFTS or not _save(next):
		return false
	_records = next
	_publish(next[record_data["id"]])
	return true


func resolution(id: String) -> Dictionary:
	if not entries.has(id):
		return {}
	if id == STARTER_ID:
		return {"source": "Preset", "intent": _presets[id]["intent"]}
	return _records.get(id, {}).get("behavior", {}).duplicate(true)


func _publish(record_data: Dictionary) -> void:
	if record_data["state"] != "unlocked":
		return
	var preset: Dictionary = _presets.get(record_data["preset_id"], {})
	var aliases: Array = []
	if not preset.is_empty():
		aliases = [preset["name"]] + preset["aliases"]
	var description: String = record_data["description"]
	if description.is_empty():
		description = record_data["recipe"]["description"]
	_index({
		"entry_id": record_data["id"], "name": record_data["name"], "description": description,
		"origin": "PLAYER_CREATED", "aliases": aliases,
	})


func _index(entry: Dictionary) -> void:
	var id: String = entry["entry_id"]
	entries[id] = entry
	for spelling: String in [entry["name"]] + entry["aliases"]:
		_names[normalize(spelling)] = id


func _valid_record(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field: String in ["id", "name", "description", "preset_id", "state", "error"]:
		if not value.get(field) is String:
			return false
	if value["id"].is_empty() or normalize(value["name"]).is_empty() or value["name"].length() > NAME_LIMIT or value["description"].length() > DESCRIPTION_LIMIT:
		return false
	var recipe: Variant = value.get("recipe")
	if not Recipe.validate(recipe)["valid"] or recipe["name"] != value["name"]:
		return false
	var preset: Dictionary = preset_for(value["name"])
	if value["preset_id"] != preset.get("entry_id", ""):
		return false
	if not Intent.Rules.number_in(value.get("craft_time"), 0, INF) or not Intent.Rules.number_in(value.get("mistakes"), 0, INF):
		return false
	var behavior: Variant = value.get("behavior")
	return behavior is Dictionary and (
		(value["state"] == "pending" and behavior.is_empty())
		or (value["state"] == "unlocked" and Intent.compile(behavior.get("intent")).has("spell"))
	)


func _save(next: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(_save_path.get_base_dir()) != OK:
		return false
	var temporary := _save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"format": SAVE_FORMAT, "spells": next}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, _save_path)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error == OK


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else null


func suggestions(text: String) -> Array[String]:
	var key := normalize(text)
	var distances: Dictionary = {}
	for alias: String in _names:
		var limit := 2 if mini(alias.length(), key.length()) >= 5 else 1
		if key.is_empty() or absi(alias.length() - key.length()) > limit:
			continue
		var distance := _distance(key, alias)
		if distance <= limit:
			var id: String = _names[alias]
			distances[id] = mini(distances.get(id, limit), distance)
	var ids: Array[String] = []
	ids.assign(distances.keys())
	ids.sort_custom(func(a: String, b: String) -> bool:
		if distances[a] == distances[b]:
			return entries[a]["name"].nocasecmp_to(entries[b]["name"]) < 0
		return distances[a] < distances[b]
	)
	return ids.slice(0, 3)


static func _distance(a: String, b: String) -> int:
	var previous := PackedInt32Array()
	previous.resize(b.length() + 1)
	for j in range(previous.size()):
		previous[j] = j
	var before_previous := PackedInt32Array()
	for i in range(1, a.length() + 1):
		var row := PackedInt32Array()
		row.resize(previous.size())
		row[0] = i
		for j in range(1, row.size()):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			row[j] = mini(mini(previous[j] + 1, row[j - 1] + 1), previous[j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				row[j] = mini(row[j], before_previous[j - 2] + 1)
		before_previous = previous
		previous = row
	return previous[b.length()]
