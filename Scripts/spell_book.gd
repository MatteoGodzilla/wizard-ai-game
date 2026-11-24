class_name SpellBook
extends RefCounted
## Stores recipes completed during crafting and writes them for the next game phase.
## A saved spell keeps the player's name, ordered elements and crafting statistics.

const Recipe = preload("res://Scripts/ai/spell_recipe.gd")
const MAX_SPELLS := 10
const SAVE_PATH := "user://spells/spellbook.json"
const FORMAT_VERSION := 1

var spells: Array[Dictionary] = []


func is_full() -> bool:
	return spells.size() >= MAX_SPELLS


## Call only after the player completes the entire element sequence.
func add_spell(recipe: Dictionary, elapsed: float, mistakes: int, metadata: Dictionary = {}) -> Error:
	if is_full():
		return ERR_UNAVAILABLE
	var checked := Recipe.validate(recipe)
	if not checked["valid"] or not is_finite(elapsed) or elapsed < 0.0 or mistakes < 0:
		return ERR_INVALID_DATA
	var record: Dictionary = checked["recipe"]
	record.merge({
		"craft_time": elapsed,
		"mistakes": mistakes,
		"source": str(metadata.get("source", "")),
		"model": str(metadata.get("model", "")),
	})
	spells.append(record)
	return OK


func total_cast_time() -> float:
	var total := 0.0
	for spell in spells:
		total += float(spell["craft_time"])
	return total


func total_mistakes() -> int:
	var total := 0
	for spell in spells:
		total += int(spell["mistakes"])
	return total


## Replaces the saved collection only after a complete temporary file has been written.
func save_to_file(path: String = SAVE_PATH) -> Error:
	if spells.size() > MAX_SPELLS:
		return ERR_INVALID_DATA
	for spell in spells:
		if _checked_record(spell).is_empty():
			return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "spells": spells}, "\t") + "\n")
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK and FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	return error


## The battlefield can load this file without depending on the crafting scene.
## A missing or invalid file leaves the current collection untouched.
func load_from_file(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return ERR_PARSE_ERROR
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != FORMAT_VERSION:
		return ERR_INVALID_DATA
	var saved: Variant = data.get("spells")
	if not saved is Array or saved.size() > MAX_SPELLS:
		return ERR_INVALID_DATA
	var checked_spells: Array[Dictionary] = []
	for entry: Variant in saved:
		var checked := _checked_record(entry)
		if checked.is_empty():
			return ERR_INVALID_DATA
		checked_spells.append(checked)
	spells = checked_spells
	return OK


func _checked_record(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var checked := Recipe.validate({
		"name": value.get("name"),
		"description": value.get("description"),
		"elements": value.get("elements"),
	})
	if not checked["valid"]:
		return {}
	var elapsed: Variant = value.get("craft_time")
	var mistakes: Variant = value.get("mistakes")
	if not (elapsed is float or elapsed is int) or not is_finite(float(elapsed)) or elapsed < 0:
		return {}
	if not (mistakes is float or mistakes is int) or not is_finite(float(mistakes)) \
			or mistakes < 0 or float(mistakes) != floorf(float(mistakes)):
		return {}
	if not value.get("source") is String or not value.get("model") is String:
		return {}
	var record: Dictionary = checked["recipe"]
	record.merge({
		"craft_time": float(elapsed), "mistakes": int(mistakes),
		"source": value["source"], "model": value["model"],
	})
	return record
