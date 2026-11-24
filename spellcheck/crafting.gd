extends Node

signal changed

const Spellbook = preload("res://spellcheck/spellbook.gd")
const Resolver = preload("res://spellcheck/spell_resolver.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const Recipe = preload("res://Scripts/ai/spell_recipe.gd")
const SAVE_ERROR := "Could not save this spell. Check that the game folder is writable and retry."

var book := Spellbook.new()
var resolver_factory := func() -> Node: return Resolver.new()
var _attempts: Dictionary = {}
var _next_job := 0


func is_full() -> bool:
	return workshop_records().size() >= Spellbook.MAX_CRAFTS


func begin(raw_name: String, raw_description: String) -> Dictionary:
	var spell_name := raw_name.strip_edges()
	var description := raw_description.strip_edges()
	if spell_name.is_empty() or spell_name.length() > Spellbook.NAME_LIMIT:
		return {"error": "Enter a spell name with 1–120 characters."}
	if description.length() > Spellbook.DESCRIPTION_LIMIT:
		return {"error": "Keep the description within 400 characters."}
	if is_full():
		return {"error": "Your workshop spellbook is full."}
	var preset := book.preset_for(spell_name)
	var preset_id: String = preset.get("entry_id", "")
	if not book.lookup(spell_name).is_empty():
		return {"error": "That spell is already unlocked."}
	for record: Dictionary in book.records():
		if _same_spell(record, spell_name, preset_id):
			return {"error": "That spell is already in your workshop spellbook."}
	for attempt: Dictionary in _attempts.values():
		if _same_spell(attempt["record"], spell_name, preset_id):
			return {"error": "That spell is already being crafted."}
	if not preset_id.is_empty() and not description.is_empty():
		return {"error": "This preset keeps its authored behavior. Choose another name for a custom description."}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var record := {
		"id": id, "name": spell_name, "description": description, "preset_id": preset_id,
		"state": "pending", "error": "", "behavior": {},
	}
	var attempt := {"record": record, "earned": false, "job": 0, "worker": null, "result": {}}
	_attempts[id] = attempt
	if preset.is_empty():
		_start_behavior(attempt)
	else:
		attempt["result"] = {"source": "Preset", "intent": preset["intent"]}
	return {"id": id}


func abandon(id: String) -> void:
	var attempt: Dictionary = _attempts.get(id, {})
	if attempt.is_empty() or attempt["earned"]:
		return
	_attempts.erase(id)
	var worker: Node = attempt["worker"]
	if is_instance_valid(worker):
		worker.cancel()
		worker.queue_free()


func earn(id: String, raw_recipe: Dictionary, elapsed: float, mistakes: int, metadata: Dictionary) -> String:
	var attempt: Dictionary = _attempts.get(id, {})
	if attempt.is_empty() or attempt["earned"]:
		return "This crafting attempt is no longer active."
	var checked := Recipe.validate(raw_recipe)
	if not checked["valid"] or checked["recipe"]["name"] != attempt["record"]["name"] or not is_finite(elapsed) or elapsed < 0 or mistakes < 0:
		abandon(id)
		return "The completed recipe could not be validated."
	attempt["earned"] = true
	attempt["record"].merge({
		"recipe": checked["recipe"], "craft_time": elapsed, "mistakes": mistakes,
		"recipe_source": str(metadata.get("source", "")), "recipe_model": str(metadata.get("model", "")),
	})
	return _persist(attempt)


func retry(id: String, raw_description: String) -> String:
	var description := raw_description.strip_edges()
	if description.length() > Spellbook.DESCRIPTION_LIMIT:
		return "Keep the description within 400 characters."
	var attempt: Dictionary = _attempts.get(id, {})
	if attempt.is_empty():
		var stored := book.record(id)
		if stored.is_empty() or stored["state"] != "pending":
			return "This spell is no longer pending."
		attempt = {"record": stored, "earned": true, "job": 0, "worker": null, "result": {}}
		_attempts[id] = attempt
	if not attempt["earned"] or is_instance_valid(attempt["worker"]):
		return "This spell is still being prepared."
	var record: Dictionary = attempt["record"]
	if description.is_empty():
		description = record["description"]
	if not record["preset_id"].is_empty() and not description.is_empty():
		return "The preset keeps its authored behavior."
	var previous_result: Dictionary = attempt["result"]
	if previous_result.has("intent") and description == record["description"]:
		return _persist(attempt)
	record["description"] = description
	attempt["result"] = {}
	var error := _persist(attempt)
	if error.is_empty():
		_start_behavior(attempt)
	return error


func workshop_records() -> Array[Dictionary]:
	var listed := {}
	for record: Dictionary in book.records():
		if record["state"] == "pending" and record["error"].is_empty() and not _attempts.has(record["id"]):
			record["error"] = "Generation stopped when the game closed. Retry to finish this spell."
		listed[record["id"]] = record
	for attempt: Dictionary in _attempts.values():
		if attempt["earned"]:
			var record: Dictionary = attempt["record"]
			listed[record["id"]] = record.duplicate(true)
	var result: Array[Dictionary] = []
	result.assign(listed.values())
	return result


func _start_behavior(attempt: Dictionary) -> void:
	var record: Dictionary = attempt["record"]
	var worker := resolver_factory.call() as Node
	_next_job += 1
	attempt["job"] = _next_job
	attempt["worker"] = worker
	add_child(worker)
	worker.power_anchors = book.power_anchors()
	worker.completed.connect(_on_behavior_completed.bind(record["id"]), CONNECT_ONE_SHOT)
	var description: String = record["description"]
	if description.is_empty():
		description = book.reference_description(record["name"])
	worker.resolve(record["name"], description, _next_job)


func _on_behavior_completed(job: int, result: Dictionary, id: String) -> void:
	var attempt: Dictionary = _attempts.get(id, {})
	if attempt.is_empty() or attempt["job"] != job:
		return
	var worker: Node = attempt["worker"]
	if is_instance_valid(worker):
		worker.queue_free()
	attempt["worker"] = null
	attempt["result"] = result if Intent.compile(result.get("intent")).has("spell") else {
		"error": str(result.get("error", "The arena spell did not validate.")),
	}
	if attempt["earned"]:
		_persist(attempt)


func _persist(attempt: Dictionary) -> String:
	var record: Dictionary = attempt["record"]
	var result: Dictionary = attempt["result"]
	var next := record.duplicate(true)
	next["state"] = "unlocked" if result.has("intent") else "pending"
	next["behavior"] = result if result.has("intent") else {}
	next["error"] = result.get("error", "")
	if not book.save_record(next):
		record["error"] = SAVE_ERROR
		changed.emit()
		return SAVE_ERROR
	attempt["record"] = next
	if not result.is_empty():
		_attempts.erase(record["id"])
	changed.emit()
	return ""


func _same_spell(record: Dictionary, spell_name: String, preset_id: String) -> bool:
	return book.normalize(record["name"]) == book.normalize(spell_name) or (
		not preset_id.is_empty() and record["preset_id"] == preset_id
	)
