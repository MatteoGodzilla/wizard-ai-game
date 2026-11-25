extends Node

const Session = preload("res://spellcheck/crafting.gd")
const Spellbook = preload("res://spellcheck/spellbook.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const MENU := "res://Scenes/main_menu.tscn"
const WORKSHOP := "res://Scenes/spell_maker.tscn"
const SANDBOX := "res://spellcheck/sandbox.tscn"
const DESCRIPTION := "Turn every rock in the arena green."


class FixtureResolver extends Node:
	signal completed(job: int, result: Dictionary)
	var power_anchors := ""
	var description := ""
	var job := 0
	var cancelled := false
	var immediate: Dictionary = {}

	func resolve(_spell_name: String, text: String, token: int) -> void:
		job = token
		description = text
		if not immediate.is_empty():
			completed.emit(job, immediate)

	func cancel() -> void:
		cancelled = true

	func finish(result: Dictionary) -> void:
		completed.emit(job, result)


var _workers: Array[FixtureResolver] = []
var _immediate: Dictionary = {}
var _failures := 0
var _folder := "res://spellcheck/local/integration-" + str(OS.get_process_id())


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var cast_audio: AudioStreamPlayer
	for descriptor: SFXDescriptor in Audio.sfx_descriptions:
		_check(AudioServer.get_bus_index(descriptor.id) >= 0 and descriptor.player.bus == descriptor.id, "sound effects use registered audio buses")
		if descriptor.id == &"spell_cast":
			cast_audio = descriptor.player
	_check(cast_audio != null, "the game registers a spell-cast sound")
	var service := tree.root.get_node("Crafting") as Session
	var save := _folder.path_join("spellbook.json")
	service.book = Spellbook.new(save)
	service.resolver_factory = _resolver
	OS.set_environment("WORKSHOP_PROVIDER", "offline-fixture")
	_check(service.book.entries.size() == 1 and not service.book.lookup("fireball").is_empty(), "a fresh spellbook exposes Fireball only")
	_check(service.begin("FIREBALL", "").has("error"), "the Fireball starter name is reserved")
	_check(service.begin("hollow PURPLE", "Turn rocks green.").has("error"), "preset names cannot override authored behavior")

	# Keep the test runner outside the normal scene lifecycle.
	tree.current_scene = null
	tree.change_scene_to_file(MENU)
	await tree.scene_changed
	tree.current_scene.get_node("VBoxContainer/PlayButton").pressed.emit()
	await tree.scene_changed
	var workshop = tree.current_scene
	_check(workshop.scene_file_path == WORKSHOP, "Play opens the workshop")
	_check(workshop.ui.sandbox_shortcut.is_visible_in_tree() and not workshop.ui.sandbox_shortcut.disabled, "the sandbox shortcut is available in a fresh workshop")
	workshop.ui.sandbox_shortcut.pressed.emit()
	await tree.scene_changed
	_check(tree.current_scene.scene_file_path == SANDBOX, "the shortcut skips spellbook review")
	tree.current_scene._ui.workshop_requested.emit()
	await tree.scene_changed
	workshop = tree.current_scene

	_submit(workshop, "  Jade Quarry  ", DESCRIPTION)
	_check(workshop.ui.sandbox_shortcut.disabled, "the shortcut is disabled during a crafting attempt")
	_check(workshop.current_metadata.get("source") == "fallback", "synchronous recipe fallback starts the existing QTE")
	_check(_workers.size() == 1 and _workers.back().description == DESCRIPTION, "the behavior request receives the player description independently")
	_check(service.begin("jade   quarry", "").has("error"), "active names are matched without case or spacing")
	var late: FixtureResolver = _workers.back()
	var id: String = workshop._attempt_id
	_complete_qte(workshop)
	_check(Spellbook.new(save).record(id).get("state") == "pending", "QTE win persists before the behavior is ready")
	_check(service.begin("JADE QUARRY", "").has("error"), "pending names cannot be recrafted")
	workshop.ui.get_node("SpellBookPanel/VBoxContainer/FinishButton").pressed.emit()
	workshop.ui.get_node("ResultPanel/VBoxContainer/SandboxButton").pressed.emit()
	await tree.scene_changed
	var sandbox = tree.current_scene
	_check(sandbox.scene_file_path == SANDBOX, "the workshop opens the sandbox")
	sandbox._submit("Jade Quarry")
	_check(sandbox._equipped.is_empty(), "typed input cannot equip pending spells")
	sandbox._open_book()
	_check(sandbox._ui._list.item_count == 1, "the sandbox book lists only unlocked spells")
	late.finish(_behavior())
	_check(sandbox._ui._list.item_count == 2, "the open sandbox book refreshes after a background unlock")
	_check(Spellbook.new(save).record(id).get("state") == "unlocked", "validated behavior updates the saved record")
	sandbox._submit("jAde quArry")
	if cast_audio != null:
		_check(cast_audio.stream == null, "equipping is silent")
	for step in 2:
		await tree.physics_frame
	var rock: Node3D
	for prop: Node3D in sandbox._arena._targets:
		if sandbox._arena._targets[prop]["kind"] == "ROCK":
			rock = prop
			break
	_check(rock != null, "the arena contains a real rock")
	if rock != null:
		var expected: Color = Intent.PALETTES["GREEN"]
		_check(sandbox._arena._rules.value(rock, "TINT") != expected, "equipping does not cast the spell")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		sandbox._unhandled_input(click)
		sandbox._unhandled_input(click)
		_check(sandbox._arena._pending_casts.size() == 1, "the click cooldown rejects an immediate repeat")
		for step in 3:
			await tree.physics_frame
		_check(sandbox._arena._rules.value(rock, "TINT") == expected, "casting changes the tint of the arena rock")
		var mesh: MeshInstance3D = sandbox._arena._targets[rock]["meshes"].keys()[0]
		_check(mesh.material_override.albedo_color == expected, "the arena applies the new tint to the rock mesh")
		if cast_audio != null:
			_check(cast_audio.playing, "an instant cast plays the spell-cast sound")
			cast_audio.stop()
			cast_audio.stream = null
			sandbox._arena._last_cast = Time.get_ticks_msec() - 1000
			sandbox._equipped["charge"] = 0.3
			sandbox._unhandled_input(click)
			for step in 2:
				await tree.physics_frame
			_check(not sandbox._arena._charge.is_empty() and cast_audio.stream == null, "charging is silent until the spell releases")
			for step in 24:
				if sandbox._arena._charge.is_empty():
					break
				await tree.physics_frame
			_check(cast_audio.playing, "releasing a charged spell plays the spell-cast sound")
	sandbox._submit("an unregistered incantation")
	_check(_workers.size() == 1, "sandbox equip and unknown text make zero generation requests")
	sandbox._ui.workshop_requested.emit()
	await tree.scene_changed
	workshop = tree.current_scene
	_check(workshop.scene_file_path == WORKSHOP, "the arena returns to the workshop")

	_immediate = _behavior()
	_submit(workshop, "Early Answer", DESCRIPTION)
	_check(service.book.lookup("Early Answer").is_empty(), "a behavior delivered before the recipe waits for a QTE win")
	_complete_qte(workshop)
	_check(not service.book.lookup("Early Answer").is_empty(), "QTE completion unlocks the early behavior")
	_immediate = {}

	_submit(workshop, "Failed Trial", DESCRIPTION)
	var failed: FixtureResolver = _workers.back()
	var failed_id: String = workshop._attempt_id
	failed.finish(_behavior())
	workshop._process(0.1)
	workshop.caster.cancel_cast()
	workshop.caster.on_failed_cast.emit()
	_check(service.book.record(failed_id).is_empty(), "failed QTE discards a ready behavior")
	_submit(workshop, "Cancelled Trial", DESCRIPTION)
	var cancelled: FixtureResolver = _workers.back()
	workshop.ui.cancel_requested.emit()
	_check(cancelled.cancelled and service.begin("Cancelled Trial", "").has("id"), "cancelling stops generation and releases the active name")
	for active_id: String in service._attempts.keys():
		service.abandon(active_id)

	_submit(workshop, "Abandoned Trial", DESCRIPTION)
	var abandoned: FixtureResolver = _workers.back()
	var abandoned_id: String = workshop._attempt_id
	var abandoned_job := abandoned.job
	workshop._return_to_menu()
	await tree.scene_changed
	var replacement: Dictionary = service.begin("Abandoned Trial", DESCRIPTION)
	_check(replacement.has("id"), "leaving the workshop releases the abandoned name")
	service._on_behavior_completed(abandoned_job, _behavior(), abandoned_id)
	_check(service.book.lookup("Abandoned Trial").is_empty() and not service._attempts[replacement["id"]]["result"].has("intent"), "a stale result cannot attach to a replacement attempt")
	service.abandon(replacement["id"])

	_test_restart_and_save_failure(service, save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_folder))
	Audio.bgm.stop()
	await tree.create_timer(0.1).timeout
	print("Workshop/sandbox integration finished with %d failures." % _failures)
	tree.quit(_failures)


func _test_restart_and_save_failure(service: Session, save: String) -> void:
	var pending: String = service.begin("Retry Trial", DESCRIPTION)["id"]
	_check(service.earn(pending, _recipe("Retry Trial"), 1.5, 2, {}).is_empty(), "a retryable QTE win is saved")
	_workers.back().finish({"error": "Fixture provider unavailable."})
	var reloaded := Session.new()
	reloaded.book = Spellbook.new(save)
	reloaded.resolver_factory = _resolver
	add_child(reloaded)
	var stored := reloaded.book.record(pending)
	_check(stored.get("error") == "Fixture provider unavailable." and stored.get("mistakes") == 2, "provider error and QTE result survive a reload")
	_check(reloaded.retry(pending, "").is_empty() and _workers.back().description == DESCRIPTION, "blank retry keeps the original description")
	var invalid: FixtureResolver = _workers.back()
	invalid.finish({"intent": {"form": "INVALID"}})
	_check(reloaded.book.lookup("Retry Trial").is_empty(), "invalid behavior remains pending")
	_check(reloaded.retry(pending, "Dye the rocks green.").is_empty(), "a retry accepts clarified instructions")
	var corrected: FixtureResolver = _workers.back()
	reloaded._on_behavior_completed(invalid.job, _behavior(), pending)
	_check(reloaded.book.lookup("Retry Trial").is_empty(), "an old generation token cannot complete a retry")
	corrected.finish(_behavior())
	stored = reloaded.book.record(pending)
	_check(stored.get("recipe") == _recipe("Retry Trial") and stored.get("state") == "unlocked" and stored.get("description") == corrected.description, "retry preserves the recipe and unlocks after validation")
	reloaded.queue_free()

	var blocked_path := _folder.path_join("blocked")
	var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.close()
	var blocked := Session.new()
	blocked.book = Spellbook.new(blocked_path.path_join("spellbook.json"))
	blocked.resolver_factory = _resolver
	add_child(blocked)
	var blocked_id: String = blocked.begin("Save Trial", DESCRIPTION)["id"]
	_workers.back().finish(_behavior())
	var error := blocked.earn(blocked_id, _recipe("Save Trial"), 0.5, 0, {})
	_check(error == Session.SAVE_ERROR and blocked.book.lookup("Save Trial").is_empty(), "a save failure blocks publication and reports the failure")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	var calls := _workers.size()
	_check(blocked.retry(blocked_id, "").is_empty() and not blocked.book.lookup("Save Trial").is_empty(), "retry publishes after the folder becomes writable")
	_check(_workers.size() == calls, "a save retry can reuse validated behavior")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path.path_join("spellbook.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	blocked.queue_free()


func _resolver() -> FixtureResolver:
	var worker := FixtureResolver.new()
	worker.immediate = _immediate
	_workers.append(worker)
	return worker


func _submit(workshop: Node, spell_name: String, description: String) -> void:
	workshop.countdown_seconds = 0.0
	workshop.ui.spell_description_input.text = description
	workshop.ui.spell_text_input.text_submitted.emit(spell_name)


func _complete_qte(workshop: Node) -> void:
	workshop._process(0.1)
	_check(workshop.caster.is_casting(), "the workshop starts the element challenge")
	for element: int in workshop._elements:
		workshop.element_input.element_typed.emit(element)


func _recipe(spell_name: String) -> Dictionary:
	return {"name": spell_name, "description": DESCRIPTION, "elements": ["Lux", "Terra", "Aqua", "Terra", "Aer", "Lux"]}


func _behavior() -> Dictionary:
	return {"source": "Integration fixture", "intent": {
		"schema_version": Intent.SCHEMA_VERSION, "form": "RITUAL", "palette": "GREEN",
		"particle": "NONE", "effect": "NONE", "power": 0,
		"rules": [{"event": "CAST", "scope": "ARENA", "tag": "ROCK", "op": "SET", "property": "TINT", "value": "GREEN"}],
	}}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
