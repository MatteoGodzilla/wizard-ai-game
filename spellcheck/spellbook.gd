extends RefCounted

const Intent = preload("res://spellcheck/spell_intent.gd")
const SEED_PATH := "res://spellcheck/seed_spellbook.json"
const SAVE_PATH := "res://spellcheck/local/spellbook.json"
const NAME_LIMIT := 100
const DESCRIPTION_MIN := 10
const DESCRIPTION_LIMIT := 400

var entries: Dictionary = {}
var warning := ""

var _names: Dictionary = {}
var _reference_descriptions: Dictionary = {}
var _custom: Dictionary = {}
var _resolutions: Dictionary = {}
var _presets: Dictionary = {}
var _power_anchors: Array[String] = []
var _whitespace := RegEx.create_from_string("(*UCP)\\s+")
var _save_path: String
var _read_only := false


func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = ProjectSettings.globalize_path(save_path)
	var seed: Variant = _read_json(SEED_PATH)
	if seed is Dictionary and seed.get("entries") is Array:
		for entry: Variant in seed["entries"]:
			if _valid_entry(entry) and not _has_name_conflict(entry):
				_index(entry)
				if entry["resolution_policy"] == "PRESET":
					var intent: Variant = entry.get("intent")
					if Intent.compile(intent).has("spell"):
						_presets[entry["entry_id"]] = intent
						if entry.get("balance") is String:
							_power_anchors.append("%s (%s)" % [entry["name"], entry["balance"]])
					else:
						warning = "A shipped spell definition could not be loaded."
		var references: Variant = seed.get("reference_descriptions", [])
		if references is Array:
			for reference: Variant in references:
				if not reference is Dictionary or not reference.get("description") is String or not reference.get("names") is Array:
					continue
				for spelling: Variant in reference["names"]:
					if spelling is String and not normalize(spelling).is_empty():
						_reference_descriptions[normalize(spelling)] = reference["description"]
	else:
		warning = "The shipped spellbook could not be read."

	if not FileAccess.file_exists(_save_path):
		return
	var saved: Variant = _read_json(_save_path)
	if (
		not saved is Dictionary or saved.get("schema_version") != Intent.SCHEMA_VERSION
		or not saved.get("entries") is Dictionary or not saved.get("resolutions") is Dictionary
	):
		_read_only = true
		warning = "The saved spellbook is invalid. Delete spellcheck/local/spellbook.json to reset it."
		return
	for id: Variant in saved["entries"]:
		var entry: Variant = saved["entries"][id]
		if (
			_valid_entry(entry) and id == entry["entry_id"]
			and entry["origin"] == "PLAYER_CREATED"
			and entry["resolution_policy"] == "AI_FROM_DESCRIPTION"
			and not _has_name_conflict(entry)
		):
			_custom[id] = entry
			_index(entry)
	_resolutions = saved["resolutions"]


func normalize(value: String) -> String:
	return _whitespace.sub(value, " ", true).strip_edges().to_lower()


func lookup(text: String) -> String:
	return _names.get(normalize(text), "")


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


func add_entry(raw_name: String, raw_description: String) -> Dictionary:
	var display_name := raw_name.strip_edges()
	var description := raw_description.strip_edges()
	if normalize(display_name).is_empty() or display_name.length() > NAME_LIMIT:
		return {"error": "Enter a name with 1–100 characters."}
	if description.length() < DESCRIPTION_MIN or description.length() > DESCRIPTION_LIMIT:
		return {"error": "Enter a description with 10–400 characters."}
	if _names.has(normalize(display_name)):
		return {"error": "That name already belongs to a spell or alias."}
	var id := "player." + Crypto.new().generate_random_bytes(16).hex_encode()
	var now := int(Time.get_unix_time_from_system())
	var entry := {
		"entry_id": id,
		"name": display_name,
		"description": description,
		"origin": "PLAYER_CREATED",
		"resolution_policy": "AI_FROM_DESCRIPTION",
		"aliases": [],
		"created_at": now,
		"updated_at": now,
	}
	var next := _custom.duplicate()
	next[id] = entry
	if not _save(next, _resolutions):
		return {"error": "Could not save the spellbook. The entry was not added."}
	_custom = next
	_index(entry)
	return {"entry_id": id}


func resolution(id: String) -> Dictionary:
	if not entries.has(id):
		return {}
	var entry: Dictionary = entries[id]
	if entry["resolution_policy"] == "PRESET":
		if _presets.has(id):
			return {"source": "Preset", "intent": _presets[id]}
		return {}
	return cached(entry)


func power_anchors() -> String:
	return "; ".join(_power_anchors)


func ad_hoc(text: String) -> Dictionary:
	var normalized := normalize(text)
	return {
		"entry_id": "adhoc." + normalized.sha256_text(),
		"name": text.strip_edges(),
		"description": _reference_descriptions.get(normalized, ""),
		"resolution_policy": "AI_FROM_DESCRIPTION",
	}


func cached(entry: Dictionary) -> Dictionary:
	var record: Variant = _resolutions.get(entry["entry_id"])
	if not record is Dictionary:
		return {}
	var intent: Variant = record.get("intent")
	if not Intent.compile(intent).has("spell"):
		return {}
	return {
		"source": "Cache",
		"intent": intent,
		"meaning": record.get("meaning", ""),
		"reference": record.get("reference", ""),
		"model": record.get("model", ""),
	}


func remember(entry: Dictionary, result: Dictionary) -> bool:
	var intent: Dictionary = result["intent"]
	if not Intent.compile(intent).has("spell"):
		return false
	_resolutions[entry["entry_id"]] = {
		"intent": intent,
		"meaning": result.get("meaning", ""), "model": result.get("model", ""),
		"reference": result.get("reference", ""),
	}
	return _save(_custom, _resolutions)


func _save(custom: Dictionary, resolutions: Dictionary) -> bool:
	if _read_only:
		return false
	var directory_error := DirAccess.make_dir_recursive_absolute(_save_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var temporary := _save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": Intent.SCHEMA_VERSION,
		"entries": custom,
		"resolutions": resolutions,
	}, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK and DirAccess.rename_absolute(temporary, _save_path) == OK


func _has_name_conflict(entry: Dictionary) -> bool:
	if entries.has(entry["entry_id"]):
		return true
	for spelling: String in [entry["name"]] + entry["aliases"]:
		if _names.has(normalize(spelling)):
			return true
	return false


func _index(entry: Dictionary) -> void:
	var id: String = entry["entry_id"]
	entries[id] = entry
	for spelling: String in [entry["name"]] + entry["aliases"]:
		_names[normalize(spelling)] = id


func _valid_entry(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["entry_id", "name", "description", "origin", "resolution_policy"]:
		if not value.get(key) is String or value[key].strip_edges().is_empty():
			return false
	if value["name"].length() > NAME_LIMIT or value["description"].length() > DESCRIPTION_LIMIT:
		return false
	if not value.get("aliases") is Array:
		return false
	for alias: Variant in value["aliases"]:
		if not alias is String or normalize(alias).is_empty() or alias.length() > NAME_LIMIT:
			return false
	return true


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file != null else null


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
