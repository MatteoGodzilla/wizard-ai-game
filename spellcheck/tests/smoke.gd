extends SceneTree

const Sandbox = preload("res://spellcheck/sandbox.tscn")
const Spellbook = preload("res://spellcheck/spellbook.gd")
const Resolver = preload("res://spellcheck/spell_resolver.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const Catalog = preload("res://spellcheck/spell_catalog.gd")
const Rules = preload("res://spellcheck/magic_rules.gd")

var _scene
var _save_path := "res://spellcheck/local/smoke-%d/spellbook.json" % OS.get_process_id()
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_launch()
	var book: Spellbook = _scene._book
	_check(book.entries.size() == 8, "seed entries")
	_check(book.lookup(" FIRE    BALL ") == "classic.fireball", "normalized alias")
	_check(book.suggestions("Firball") == ["classic.fireball"], "Fireball typo")
	_check(book.add_entry("fire ball", "A long enough description.").has("error"), "duplicate alias")
	for id: String in book.entries:
		_check(_scene._state_for(id) == "READY", "%s starts READY" % id)
		_prepare(book.entries[id]["name"])
		_check(not _scene._equipped.is_empty() and _scene._resolver.model_requests == 0, "%s equips without inference" % id)
	_check(Resolver.decode({"message": {"content": "{}"}}).has("error"), "malformed decision rejected")
	_check(Intent.compile(Intent.create("ORB", "ORANGE", "SMOKE", "IGNITE", 9)).has("error"), "unsafe power rejected")
	var old_intent := Intent.create("ORB", "ORANGE", "SMOKE", "IGNITE", 1)
	old_intent["schema_version"] = 2
	_check(Intent.compile(old_intent).has("error"), "compiler accepts only the current spell schema")
	_delivery_schema()
	_afterimage_policy(book)
	_scene._open_book()
	_check(_scene._ui._list.item_count == 8, "unfiltered book shows all entries")
	_scene._ui.close_modal()

	var start: Vector3 = _scene._arena._player.position
	Input.action_press("spellcheck_right")
	await create_timer(0.12).timeout
	Input.action_release("spellcheck_right")
	_check(_scene._arena._player.position.x > start.x, "camera-relative movement")
	_scene._reset_world()
	var starting_targets: int = _scene._arena._targets.size()
	_prepare("Fireball")
	_check(_scene._equipped.get("form") == "ORB", "release Shift equips Fireball")
	_check(_scene._arena._projectiles.is_empty(), "release Shift does not fire")
	_check(_scene._arena._pending_casts.is_empty(), "release Shift does not queue a cast")
	var first_tree := _target_near(Vector3(-2.4, 0.625, -2.6), "TREE")
	_click_toward(first_tree.global_position + Vector3.UP * 1.7)
	await create_timer(1.3).timeout
	_check(_scene._arena._targets.get(first_tree, {}).get("burning", false), "Fireball ignites a real tree")
	_check(_count_scorched() >= 2, "fire spreads to nearby grass and leaves scorch")
	_scene._reset_world()
	_check(_scene._arena._targets.size() == starting_targets, "reset restores props")
	_check(_count_scorched() == 0 and not _scene._arena._fire._grass.any(func(patch: MeshInstance3D) -> bool: return patch.visible), "reset clears all ground overlays")
	await _runtime_examples()
	await _utility_runtime(book)
	await _beam_runtime()
	await _river_runtime()

	if "--planner" in OS.get_cmdline_user_args():
		await _collision_reference_live(book)
		await _planner_live(book)
		await _attack_trails_live(book)
	elif "--live" in OS.get_cmdline_user_args():
		await _collision_reference_live(book)
		await _planner_live(book)
		await _attack_trails_live(book)
		await _live_examples(book)
	else:
		await _offline_examples(book)
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
		DirAccess.remove_absolute(_save_path.get_base_dir())
	print("Spellcheck smoke failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _delivery_schema() -> void:
	var schema := Catalog.schema(true)
	for branch: Dictionary in schema["anyOf"]:
		var fields: Dictionary = branch["properties"]
		if not fields.has("rules"):
			continue
		for variant: Dictionary in fields["rules"]["items"]["anyOf"]:
			var options: Dictionary = variant["properties"]
			for form: String in fields["form"]["enum"]:
				_check("HIT" not in options["event"]["enum"] or form in Rules.HIT_FORMS, "schema pairs impact rules with an impact form")
				_check("ENTER" not in options["event"]["enum"] or form == "DOMAIN", "schema pairs membership rules with a domain")
	var draft := Intent.create("RITUAL", "YELLOW", "NONE", "NONE", 0)
	draft.erase("schema_version")
	draft["rules"] = [{"event": "CAST", "scope": "ARENA", "tag": "WOOD", "op": "DAMAGE", "property": "INTEGRITY", "value": 2}]
	draft.merge({"status": "COMPOSED", "meaning": "Throws a blade that cuts wood on impact.", "reference": ""})
	var decoded := Resolver.decode({"message": {"content": JSON.stringify(draft)}})
	_check(decoded.get("repair_impact", false), "a draft that describes throwing an attack triggers an impact-form repair")


func _collision_reference_live(book: Spellbook) -> void:
	var name := "DESTRUCTO DISC"
	_scene._reset_world()
	_prepare(name)
	await _wait_for_resolution()
	print(_scene._ui._detail.text)
	_check(book.cached(book.ad_hoc(name)).get("source") == "Cache", "new cutting spell saves a valid generated definition")
	if _scene._equipped.is_empty():
		return
	var arena = _scene._arena
	_check(_scene._equipped.get("form") in Rules.HIT_FORMS, "cutting spell travels toward its target")
	_check(arena._projectiles.is_empty() and arena._pending_casts.is_empty(), "preparing a new cutting spell waits for click")
	var timber := _target_near(Vector3(0, 0, -5), "TIMBER")
	var before: float = arena._rules.value(timber, "INTEGRITY")
	arena._player.position = Vector3(0, 0.05, 1)
	await physics_frame
	await physics_frame
	_click_toward(timber.global_position)
	await create_timer(float(_scene._equipped["charge"]) + 0.8).timeout
	_check(not is_instance_valid(timber) or float(arena._rules.value(timber, "INTEGRITY")) < before, "casting the generated cutting spell damages a timber target")


func _afterimage_policy(book: Spellbook) -> void:
	var trail := {"event": "CAST", "scope": "CASTER", "tag": "ANY", "op": "SET", "property": "AFTERIMAGE", "value": "RED", "duration": 3}
	var beam := Intent.create("BEAM", "RED", "NONE", "IGNITE", 1)
	beam["rules"] = [trail]
	var heat := _decode_rules(beam, "Heat Vision")
	var compiled: Dictionary = Intent.compile(heat.get("intent")).get("spell", {})
	_check(compiled.get("rules", []).any(func(rule: Dictionary) -> bool: return rule["property"] == "BURNING"), "removing a hallucinated caster trail restores implicit ignition")
	_check(heat.get("intent", {}).get("rules", []).is_empty(), "beam color does not imply a trail on the caster")

	var damaging := {"event": "CAST", "scope": "ARENA", "tag": "ROCK", "op": "DAMAGE", "property": "INTEGRITY", "value": 3}
	var speed := {"event": "CAST", "scope": "CASTER", "tag": "ANY", "op": "MULTIPLY", "property": "SPEED", "value": 2, "duration": 3}
	var direct := Intent.create("RITUAL", "ORANGE", "NONE", "NONE", 0)
	direct["rules"] = [damaging, speed, trail]
	var blast := _decode_rules(direct, "Nuclear Bomb")
	_check(_rule_properties(blast) == ["INTEGRITY", "SPEED"], "a direct attack with a speed rule does not inherit caster trails")

	var explicit := _decode_rules(beam, "Shoot a red beam and leave ghost copies of me as I move.")
	_check(_rule_properties(explicit) == ["AFTERIMAGE"], "an attack can include explicitly requested caster trails")
	direct["rules"] = [speed, trail]
	var mobility := _decode_rules(direct, "A time-bending burst of speed")
	_check(_rule_properties(mobility) == ["SPEED", "AFTERIMAGE"], "an inferred trail is retained for direct mobility")
	var declined := _decode_rules(direct, "Run twice as fast without colored afterimages")
	_check(_rule_properties(declined) == ["SPEED"], "an explicit trail opt-out wins over mobility inference")

	var attack_entry := book.ad_hoc("Cached eye ray")
	var mobility_entry := book.ad_hoc("Cached speed boost")
	_check(heat.has("intent") and book.remember(attack_entry, heat), "a generated attack can be saved for the cache test")
	var cached_attack := book.cached(attack_entry)
	_check(cached_attack.get("source") == "Cache" and _rule_properties(cached_attack).is_empty() and cached_attack["intent"]["effect"] == "IGNITE", "the cache stores the validated attack")
	_check(book.remember(mobility_entry, {"intent": direct}) and not book.cached(mobility_entry).is_empty(), "valid cached mobility trails stay available")


func _rule_properties(result: Dictionary) -> Array:
	return result.get("intent", {}).get("rules", []).map(func(rule: Dictionary) -> String: return rule["property"])


func _decode_rules(intent: Dictionary, request: String) -> Dictionary:
	var draft := intent.duplicate()
	draft.erase("schema_version")
	draft.merge({"status": "COMPOSED", "meaning": "Test cast", "reference": ""})
	return Resolver.decode({"message": {"content": JSON.stringify(draft)}}, request)


func _attack_trails_live(book: Spellbook) -> void:
	for request in ["Heat Vision", "Nuclear Bomb"]:
		_scene._reset_world()
		_prepare(request)
		await _wait_for_resolution()
		print(_scene._ui._detail.text)
		_check(not book.cached(book.ad_hoc(request)).is_empty(), "%s still resolves" % request)
		_check(not _scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
			return rule["property"] == "AFTERIMAGE"
		), "%s has no unrelated caster trail" % request)


func _planner_live(book: Spellbook) -> void:
	var reference := book.add_entry("X", "Works like the Sandevistan in Cyberpunk 2077.")
	var anime := book.add_entry("Quick Accent", "It works like David's Sandevistan from Cyberpunk: Edgerunners.")
	var paraphrase := book.add_entry("Mauve Hour", "For two seconds double my movement speed, make the whole world move at half speed, and leave rainbow copies of me behind as I move.")
	for id: String in [reference["entry_id"], anime["entry_id"], paraphrase["entry_id"]]:
		_scene._reset_world()
		var requests: int = _scene._resolver.model_requests
		var started := Time.get_ticks_msec()
		var entry: Dictionary = book.entries[id]
		_prepare(entry["name"])
		await _wait_for_resolution()
		print(_scene._ui._detail.text)
		print("First prepare %s: %d ms" % [entry["name"], Time.get_ticks_msec() - started])
		var calls: int = _scene._resolver.model_requests - requests
		_check(calls == 1 or (id == anime["entry_id"] and calls == 2), "%s resolves with the expected model-call budget" % entry["name"])
		var arena = _scene._arena
		_check(_scene._equipped.get("form") == "RITUAL", "time and movement combo uses a direct form")
		if not _scene._equipped.is_empty():
			_click_toward(Vector3.FORWARD)
			await create_timer(float(_scene._equipped["charge"]) + 0.09).timeout
			_check(arena._rules.value(arena._player, "SPEED") > 1.0, "combo speeds up the caster")
			_check(arena._rules.value(arena, "TIME_SCALE") < 1.0, "combo slows down the arena")
			_check(arena._rules.value(arena._player, "AFTERIMAGE") == "RAINBOW", "combo selects multicolored afterimages")
			var start: Vector3 = arena._player.position
			Input.action_press("spellcheck_right")
			await create_timer(0.29).timeout
			Input.action_release("spellcheck_right")
			_check(arena._player.position.distance_to(start) > 1.7, "caster remains responsive during slowdown")
			_check(arena._afterimages._ghosts.size() >= 2, "generated combo renders a trail")
		started = Time.get_ticks_usec()
		var cached_requests: int = _scene._resolver.model_requests
		_prepare(entry["name"])
		print("Cached prepare %s: %.2f ms" % [entry["name"], (Time.get_ticks_usec() - started) / 1000.0])
		_check(_scene._resolver.model_requests == cached_requests and _scene._ui._detail.text.contains("Source  ·  Cache"), "repeat prepare makes zero model calls")

	_scene._reset_world()
	var arena = _scene._arena
	arena._player.position = Vector3(8.7, 0.05, 0)
	var frozen := book.add_entry("Winter Footing", "Freeze river water within six meters of me into walkable ice for four seconds.")
	_prepare(book.entries[frozen["entry_id"]]["name"])
	await _wait_for_resolution()
	print(_scene._ui._detail.text)
	_check(_scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
		return rule["property"] == "MATERIAL" and rule["tag"] == "WATER" and rule["value"] == "ICE" and rule["scope"] != "ARENA"
	), "improvised river freeze selects a local terrain transformation")
	if not _scene._equipped.is_empty():
		_click_toward(Vector3(11, 0, 0))
		await create_timer(float(_scene._equipped["charge"]) + 0.1).timeout
		_check(not arena._rules.matching("ICE", Vector3(11, 0, 0), 1.0).is_empty(), "Gemma-generated transformation makes real ice")
		_check(arena._rules.value(arena, "TIME_SCALE") == 1.0, "freezing water leaves world time alone")

	var abandoned := "A tiny yellow ward of swirling stars"
	_prepare(abandoned)
	_check(not _scene._pending_entry.is_empty(), "uncached spell starts inference before reset")
	_scene._reset_world()
	await process_frame
	_check(_scene._resolver._request == null and _scene._equipped.is_empty(), "reset cancels a live request and clears equipment")
	_check(book.cached(book.ad_hoc(abandoned)).is_empty(), "cancelled spell was not cached")


func _live_examples(book: Spellbook) -> void:
	_scene._reset_world()
	_prepare("Patronus")
	_check(not _scene._ui.has_modal(), "unknown name goes straight to AI")
	await _wait_for_resolution()
	var patronus := book.ad_hoc("patronus")
	var patronus_result := book.cached(patronus)
	_expect(patronus_result, "WARD", "", "", "NONE")
	_check(str(patronus_result.get("reference", "")).to_lower().contains("harry potter"), "AI identifies the Patronus reference")
	_check(_scene._equipped.get("power") == 0, "Patronus is harmless")
	_check(not book.entries.has(patronus["entry_id"]), "ad hoc spell stays out of book")
	_check(_scene._arena._pending_casts.is_empty(), "resolved ad hoc spell waits for click")
	if not _scene._equipped.is_empty():
		var previous_children: int = _scene._arena._player.get_child_count()
		_click_toward(Vector3.FORWARD)
		await create_timer(0.3).timeout
		_check(_scene._arena._player.get_child_count() > previous_children, "ward follows the caster")
		_check(_scene._arena._projectiles.is_empty(), "ward launches no sphere")

	_prepare("Betis")
	await _wait_for_resolution()
	_expect(book.resolution("original.betis"), "ORB", "GREEN", "SMOKE", "BURST")
	_check(_scene._equipped.get("charge") == 0.0, "an ordinary fireball stays immediate")
	_prepare("Kamehameha")
	await _wait_for_resolution()
	var beam := _expect(book.resolution("reference.kamehameha"), "BEAM", "BLUE", "", "BREAK")
	_check(int(beam.get("power", 0)) >= 2, "destructive beam receives high power")
	_check(float(beam.get("charge", 0.0)) >= 0.5, "preset beam has a charge")
	var previous_targets: int = _scene._arena._targets.size()
	_click_toward(Vector3(0, 0, -5))
	await create_timer(0.15).timeout
	_check(_scene._arena._targets.size() == previous_targets, "charging delays damage")
	_check(get_node_count_in_group("spellcheck_particle_fields") > 0, "charging renders particles")
	_check(_scene._equipped["emitters"].any(func(profile: Dictionary) -> bool:
		return profile["phase"] == "CHARGE" and profile["direction"] == "INWARD"
	), "charge draws particles toward the caster")
	await create_timer(float(beam.get("charge", 0.0)) + 0.18).timeout
	_check(_scene._arena._targets.size() < previous_targets, "beam removes timber")
	_check(_scene._arena._projectiles.is_empty(), "beam launches no sphere")

	_prepare("Hollow Purple")
	await _wait_for_resolution()
	var purple := _expect(book.resolution("reference.hollow_purple"), "ORB", "VIOLET", "", "ERASE")
	var purple_charge: float = purple.get("charge", 0.0)
	_check(purple_charge >= 0.8 and purple_charge <= 1.6, "Hollow Purple has a short wind-up")
	var near_rock := _target_near(Vector3(2.2, 0, -1.6), "ROCK")
	var far_rock := _target_near(Vector3(2.95, 0, -3.8), "ROCK")
	_click_toward(near_rock.global_position)
	await create_timer(purple_charge + 0.75).timeout
	_check(not is_instance_valid(near_rock) and not is_instance_valid(far_rock), "Hollow Purple erases and pierces rocks")
	var tree := _target_near(Vector3(-2.4, 0, -2.6), "TREE")
	_click_toward(tree.global_position)
	await create_timer(purple_charge + 0.65).timeout
	_check(not is_instance_valid(tree), "Hollow Purple erases a tree")

	_prepare("harmless violet wave of glitter")
	await _wait_for_resolution()
	_expect(book.cached(book.ad_hoc("harmless violet wave of glitter")), "WAVE", "VIOLET", "", "NONE")
	var created := book.add_entry("Azure Pin", "A harmless bright blue magic bolt with a trail of sparks.")
	_check(created.has("entry_id"), "manual entry saves")
	if created.has("entry_id"):
		_prepare("Azure Pin")
		await _wait_for_resolution()
		_expect(book.resolution(created["entry_id"]), "BOLT", "BLUE", "SPARKS", "NONE")
	_prepare("lightning")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "ARC", "lightning typo produces a branched arc")
	_prepare("Blue bolt on a helix with red shards moving upward at the target on hit")
	await _wait_for_resolution()
	_check(_scene._equipped.get("path") == "HELIX", "AI selects a source-independent math path")
	_check(_scene._equipped.get("emitters", []).any(func(profile: Dictionary) -> bool:
		return profile["shape"] == "SHARD" and profile["color"] == Intent.PALETTES["RED"] and profile["phase"] == "HIT" and profile["anchor"] == "TARGET" and profile["direction"] == "UP"
	), "AI selects independent impact particle attributes")
	_prepare("Domain expansion")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "DOMAIN", "domain expansion chooses enclosing sphere")
	_prepare("Crimson wasteland around me where everything moves slowly except me")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "DOMAIN", "reality marble chooses enclosing sphere")
	_check(_scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
		return rule["property"] == "SPEED" and rule["event"] == "ENTER"
	), "AI uses membership-based speed for the reality marble")
	_prepare("Turn all the trees in the arena upside down")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "RITUAL", "flip uses a world spell")
	_click_toward(Vector3.FORWARD)
	await create_timer(0.19).timeout
	_check(_count_flipped() == _count_props("TREE"), "AI flips every registered tree")
	_prepare("Make all trees in the arena explode")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "RITUAL", "all trees uses an arena-wide spell")
	_click_toward(Vector3.FORWARD)
	await create_timer(0.19).timeout
	_check(_count_props("TREE") == 0 and _count_props("ROCK") > 0, "AI destroys all trees and preserves rocks")
	_prepare("Clear the scorch from all grass")
	await _wait_for_resolution()
	_check(_scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
		return rule["scope"] == "ARENA" and rule["tag"] == "GRASS" and rule["property"] == "SCORCH" and rule["value"] == 0.0
	), "AI can clear scorched terrain across the arena")
	await _utility_live(book)
	_prepare("zxqvplmtrn")
	await _wait_for_resolution()
	_check(book.cached(book.ad_hoc("zxqvplmtrn")).is_empty(), "gibberish does not get a definition")
	_check(not _scene._ui.has_modal(), "unintelligible input also stays in the arena")

	OS.set_environment("SPELLCHECK_OLLAMA_PORT", "1")
	root.remove_child(_scene)
	_scene.queue_free()
	_launch()
	_prepare("PATRONUS")
	_check(_scene._equipped.get("form") == "WARD", "ad hoc spell survives restart offline")
	_check(_scene._ui._detail.text.contains("Source  ·  Cache"), "offline ad hoc cache source")
	_check(_scene._resolver._request == null, "cached cast starts zero requests")


func _utility_live(book: Spellbook) -> void:
	_scene._reset_world()
	var entry := book.add_entry("Treemaker", "Creates a tree at the point I aim at.")
	_check(entry.has("entry_id"), "save a tree-making spell")
	_prepare("Treemaker")
	await _wait_for_resolution()
	_check(_scene._equipped.get("form") == "RITUAL", "saved Treemaker resolves to direct placement")
	var tree_count := _count_props("TREE")
	_click_toward(Vector3(3.0, 0, 2.0))
	await create_timer(float(_scene._equipped.get("charge", 0.0)) + 0.2).timeout
	_check(_count_props("TREE") == tree_count + 1, "Treemaker grows a registered tree")

	_prepare("Super speed")
	await _wait_for_resolution()
	_click_toward(Vector3.FORWARD)
	await create_timer(float(_scene._equipped.get("charge", 0.0)) + 0.2).timeout
	var arena = _scene._arena
	_check(arena._rules.value(arena._player, "SPEED") > 1.0 and arena._projectiles.is_empty(), "super speed changes the caster")
	_prepare("Levitate")
	await _wait_for_resolution()
	_click_toward(Vector3.FORWARD)
	await create_timer(0.55).timeout
	_check(arena._player.position.y > 0.45 and arena._projectiles.is_empty(), "Levitate physically lifts the caster")
	_check(_scene._ui._detail.text.contains("HOVER"), "inspector describes actual levitation")
	_prepare("Stop time")
	await _wait_for_resolution()
	var time_rules: Array = _scene._equipped.get("rules", [])
	_check(book.ad_hoc("Stop time")["description"].contains("black and white"), "Stop Time describes its camera change explicitly")
	_check(time_rules.any(func(rule: Dictionary) -> bool:
		return rule["scope"] == "CAMERA" and rule["property"] == "SCREEN_SATURATION" and rule["value"] == 0
	), "Stop Time resolves a separate camera rule")
	_click_toward(Vector3.FORWARD)
	await create_timer(float(_scene._equipped.get("charge", 0.0)) + 0.1).timeout
	_check(arena._rules.value(arena, "TIME_SCALE") == 0.0 and arena._domains.is_empty(), "stop time freezes the arena without a domain")
	_check(arena._screen_filter.visible, "Stop Time changes the rendered camera")
	_prepare("Slow me down")
	await _wait_for_resolution()
	_check(_scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
		return rule["scope"] == "CASTER" and rule["property"] == "SPEED" and rule["value"] < 1.0
	), "self slow resolves to a real debuff")
	_scene._reset_world()
	arena = _scene._arena
	_prepare("Laser Vision")
	await _wait_for_resolution()
	var beam: Dictionary = _scene._equipped.get("beam", {})
	_check(_scene._equipped.get("form") == "BEAM" and beam.get("lanes") == 2 and beam.get("anchor") == "EYES", "Laser Vision casts two eye rays")
	_prepare("Two red sine beams diverging 8 degrees")
	await _wait_for_resolution()
	beam = _scene._equipped.get("beam", {})
	_check(_scene._equipped.get("path") == "SINE" and beam.get("lanes") == 2 and beam.get("spread", 0.0) > 0.0, "AI combines directional beam geometry and waves")
	_prepare("Make the camera view black and white for two seconds")
	await _wait_for_resolution()
	_click_toward(Vector3.FORWARD)
	await create_timer(float(_scene._equipped.get("charge", 0.0)) + 0.1).timeout
	_check(arena._screen_filter.visible and arena._rules.value(arena, "TIME_SCALE") == 1.0, "camera filters can run independently from world time")


func _utility_runtime(book: Spellbook) -> void:
	var dd := book.ad_hoc("DD")
	var bogus := Intent.create("BOLT", "RED", "SPARKS", "BREAK", 2)
	_check(book.remember(dd, {"intent": bogus}), "test can seed a previously guessed DD")
	_prepare("DD")
	_check(_scene._pending_entry.is_empty() and _scene._equipped.is_empty(), "DD is rejected before cache and inference")
	_check(_scene._ui._detail.text.contains("too short"), "short-input reason is shown")
	_prepare("zxqvplmtrn")
	_check(_scene._pending_entry.is_empty() and _scene._equipped.is_empty(), "a long consonant-only keyboard mash is rejected before inference")

	var arena = _scene._arena
	var utility := Intent.create("RITUAL", "GREEN", "NONE", "NONE", 0)
	utility["rules"] = [
		{"event": "CAST", "scope": "CASTER", "tag": "ANY", "op": "MULTIPLY", "property": "SPEED", "value": 2, "duration": 1},
		{"event": "CAST", "scope": "CASTER", "tag": "ANY", "op": "SET", "property": "HOVER", "value": 1.6, "duration": 1},
		{"event": "CAST", "scope": "CASTER", "tag": "ANY", "op": "SET", "property": "AFTERIMAGE", "value": "RAINBOW", "duration": 1},
	]
	_scene._equipped = Intent.compile(utility)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.13).timeout
	Input.action_press("spellcheck_right")
	await create_timer(0.3).timeout
	_check(Vector2(arena._player.velocity.x, arena._player.velocity.z).length() > 10.0, "speed rule changes physical movement")
	var ghost_colors := {}
	for ghost: Dictionary in arena._afterimages._ghosts:
		var tint: Color = ghost["material"].albedo_color
		ghost_colors[tint.to_html(false)] = true
	_check(ghost_colors.size() >= 2, "motion produces distinct translucent ghost colors")
	Input.action_release("spellcheck_right")
	_check(arena._player.position.y > 0.75, "hover changes physical elevation")
	await create_timer(1.1).timeout
	_check(arena._player.position.y < 0.12 and arena._rules.value(arena._player, "SPEED") == 1.0, "timed self effects restore normal movement and landing")
	_check(arena._rules.value(arena._player, "AFTERIMAGE") == "OFF" and arena._afterimages._ghosts.is_empty(), "afterimages expire")
	_scene._reset_world()
	arena = _scene._arena

	_prepare("Fireball")
	_click_toward(Vector3(0, 0, 16))
	await create_timer(0.21).timeout
	utility["rules"] = [
		{"event": "CAST", "scope": "ARENA", "tag": "WORLD", "op": "SET", "property": "TIME_SCALE", "value": 0, "duration": 1},
		{"event": "CAST", "scope": "CAMERA", "tag": "ANY", "op": "SET", "property": "SCREEN_SATURATION", "value": 0, "duration": 1},
	]
	_scene._equipped = Intent.compile(utility)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.08).timeout
	_check(arena._screen_filter.visible and arena._screen_filter.material.get_shader_parameter("saturation") == 0.0, "camera shader receives grayscale independently")
	_check(not arena._projectiles.is_empty(), "a projectile exists when time stops")
	if not arena._projectiles.is_empty():
		var flying: Node3D = arena._projectiles[0]["node"]
		var frozen_at := flying.position
		var caster_at: Vector3 = arena._player.position
		Input.action_press("spellcheck_right")
		await create_timer(0.26).timeout
		Input.action_release("spellcheck_right")
		_check(flying.position.is_equal_approx(frozen_at), "world time freezes projectile movement")
		_check(not arena._player.position.is_equal_approx(caster_at), "the caster can move during stopped time")
		await create_timer(0.85).timeout
		_check(arena._rules.value(arena, "TIME_SCALE") == 1.0, "the arena clock resumes on real time")
		_check(not arena._screen_filter.visible and arena._rules.value(arena._camera, "SCREEN_SATURATION") == 1.0, "camera filter expires on real time")
		_check(not is_instance_valid(flying) or not flying.position.is_equal_approx(frozen_at), "world movement resumes")
	_scene._reset_world()


func _beam_runtime() -> void:
	var arena = _scene._arena
	var fan := {"lanes": 2, "spread": 8}
	var left := Intent.beam_lane_direction(Vector3.FORWARD, fan, 0)
	var right := Intent.beam_lane_direction(Vector3.FORWARD, fan, 1)
	_check(left.x < 0.0 and right.x > 0.0 and is_equal_approx(rad_to_deg(left.angle_to(right)), 8.0), "positive spread diverges symmetrically")
	var target := _target_near(Vector3(0, 0, -5), "TIMBER")
	var intent := Intent.create("BEAM", "RED", "NONE", "BREAK", 1)
	intent["beam"] = {"anchor": "EYES", "lanes": 2, "spacing": 0.26, "spread": 0.0}
	_scene._equipped = Intent.compile(intent)["spell"]
	_click_toward(Vector3(0, 0, -5))
	await create_timer(0.095).timeout
	_check(arena._beams.size() == 1, "beam remains active briefly")
	if not arena._beams.is_empty():
		var active: Dictionary = arena._beams[0]
		var origins: Array = active["origins"]
		_check(origins.size() == 2 and is_equal_approx(origins[0].distance_to(origins[1]), 0.26), "two distinct eye origins render")
		_check(arena._targets.get(target, {}).get("integrity", 0.0) == 1.0, "beam lanes damage each target once per cast")
		var player_start: Vector3 = arena._player.position
		Input.action_press("spellcheck_right")
		await create_timer(0.19).timeout
		Input.action_release("spellcheck_right")
		var beam_delta: Vector3 = active["origins"][0] - origins[0]
		var caster_delta: Vector3 = arena._player.position - player_start
		_check(caster_delta.length() > 0.3 and beam_delta.is_equal_approx(caster_delta), "beam origin follows a moving caster")
	await create_timer(0.25).timeout
	_check(arena._beams.is_empty(), "beam expires after its cast lifetime")
	_scene._reset_world()


func _runtime_examples() -> void:
	var intent := Intent.create("RITUAL", "VIOLET", "NONE", "NONE", 0)
	intent["charge"] = 3.2
	_check(Intent.compile(intent).has("error"), "charge cap is enforced")
	intent["charge"] = 0.0
	intent["rules"] = [
		{"event": "CAST", "scope": "ARENA", "tag": "TREE", "op": "SET", "property": "TINT", "value": "VIOLET"},
		{"event": "CAST", "scope": "ARENA", "tag": "GRASS", "op": "SET", "property": "SCORCH", "value": 1},
	]
	_scene._equipped = Intent.compile(intent)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.19).timeout
	for target: Node3D in _scene._arena._rules.entities:
		if _scene._arena._targets.get(target, {}).get("kind") == "TREE":
			_check(_scene._arena._rules.value(target, "TINT") == Intent.PALETTES["VIOLET"], "arena rule tints trees")
	_check(_count_scorched() > 100, "scorch is a selectable terrain property")
	intent["rules"] = [{"event": "CAST", "scope": "ARENA", "tag": "GRASS", "op": "SET", "property": "SCORCH", "value": 0}]
	_scene._equipped = Intent.compile(intent)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.19).timeout
	_check(_count_scorched() == 0, "the same rule can clear scorch")

	var arena = _scene._arena
	var member := Node3D.new()
	arena.add_child(member)
	member.position = arena._player.position + Vector3.RIGHT
	arena._rules.register(member, ["PROJECTILE", "MOVING"], {"SPEED": 1.0})
	var domain := Intent.create("DOMAIN", "RED", "NONE", "NONE", 0)
	domain["rules"] = [{"event": "ENTER", "scope": "MEMBER", "tag": "MOVING", "op": "MULTIPLY", "property": "SPEED", "value": 0.3}]
	domain["radius"] = 4.0
	domain["duration"] = 1.3
	_scene._equipped = Intent.compile(domain)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.2).timeout
	_check(is_equal_approx(arena._rules.value(member, "SPEED"), 0.3), "initial domain members slow")
	_check(arena._rules.value(arena._player, "SPEED") == 1.0, "the caster stays outside member effects")
	_click_toward(Vector3.FORWARD)
	await create_timer(0.2).timeout
	_check(is_equal_approx(arena._rules.value(member, "SPEED"), 0.09), "overlapping domains stack by source")
	member.position += Vector3.RIGHT * 8.0
	await create_timer(0.12).timeout
	_check(arena._rules.value(member, "SPEED") == 1.0, "leaving both domains restores speed")
	member.position -= Vector3.RIGHT * 8.0
	await create_timer(1.2).timeout
	_check(arena._rules.value(member, "SPEED") == 1.0, "expired domains restore speed")
	_scene._reset_world()
	arena = _scene._arena

	var wave := Intent.create("WAVE", "CYAN", "NONE", "NONE", 0)
	_scene._equipped = Intent.compile(wave)["spell"]
	_click_toward(Vector3.FORWARD)
	await create_timer(0.43).timeout
	var visual: Dictionary = arena._waves[0]
	var scale_at_max_hits: float = visual["node"].scale.x
	var alpha_before_fade: float = visual["core"].albedo_color.a
	await create_timer(0.14).timeout
	_check(visual["node"].scale.x > scale_at_max_hits and visual["core"].albedo_color.a < alpha_before_fade, "wave continues moving and fading after hit range")
	await create_timer(0.2).timeout
	_check(arena._waves.is_empty(), "wave expires")
	var curve := Intent.create("BOLT", "CYAN", "NONE", "NONE", 0)
	curve["path"] = "HELIX"
	var path: Dictionary = Intent.compile(curve)["spell"]
	_check(Intent.path_offset(path, Vector3.FORWARD, 0.125).length() > 0.1, "bounded math path changes trajectory")
	var effect := Intent.create("BEAM", "BLUE", "NONE", "NONE", 0)
	effect["emitters"] = [{"phase": "HIT", "anchor": "TARGET", "direction": "UP", "shape": "SHARD", "color": "RED"}]
	_scene._equipped = Intent.compile(effect)["spell"]
	_click_toward(Vector3(0, 0, -5))
	await create_timer(0.14).timeout
	var particles := get_nodes_in_group("spellcheck_particle_fields")
	_check(particles.size() == 1, "impact spawns the selected particle phase")
	if not particles.is_empty():
		_check(particles[0].global_position.distance_to(Vector3(0, 0.48, -5)) < 1.0, "impact particles are anchored to the target")
	_scene._reset_world()


func _count_props(kind: String) -> int:
	var count := 0
	for prop: Dictionary in _scene._arena._targets.values():
		if prop["kind"] == kind:
			count += 1
	return count


func _count_flipped() -> int:
	var count := 0
	for node: Node3D in _scene._arena._targets:
		if _scene._arena._targets[node]["kind"] == "TREE" and is_equal_approx(absf(node.rotation.z), PI):
			count += 1
	return count


func _count_scorched() -> int:
	var count := 0
	for patch: Node3D in _scene._arena._fire._grass:
		if float(_scene._arena._rules.value(patch, "SCORCH")) > 0.5:
			count += 1
	return count

func _river_runtime() -> void:
	_scene._reset_world()
	var arena = _scene._arena
	var player: CharacterBody3D = arena._player
	var bank := Vector3(8.9, 0.05, 0)
	var river_midpoint := Vector3(11, 0, 0)
	var cells: Array[Node3D] = arena._rules.matching("WATER", river_midpoint, 1.0)
	_check(cells.size() == 1, "liquid cells can be selected by rules")
	var cell: Node3D = cells[0]
	player.position = bank
	await create_timer(0.07).timeout
	player.move_and_collide(Vector3(4.45, 0, 0))
	_check(player.position.x < 9.5, "unfrozen water stops walking")
	player.position = bank + Vector3(0, 0, 4)
	await create_timer(0.07).timeout
	player.move_and_collide(Vector3(4.45, 0, 0))
	_check(player.position.x > 12.5, "bridge crosses unfrozen water")

	player.position = bank
	_prepare("Levitate")
	_click_toward(river_midpoint)
	await create_timer(0.45).timeout
	player.move_and_collide(Vector3(4.45, 0, 0))
	_check(player.position.x > 12.5, "hover clears the liquid blocker")
	player.position = bank
	await create_timer(0.07).timeout
	player.position = river_midpoint + Vector3.UP
	arena._rules.set_base(player, "HOVER", 0.0)
	arena._rules.advance(6, 0)
	await create_timer(0.08).timeout
	_check(player.position.x < 9.5, "ending hover over water restores safe footing")

	_prepare("Snowgrave")
	var timber := _target_near(Vector3(4.7, 0.85, -3.4), "TIMBER")
	_click_toward(river_midpoint)
	await create_timer(0.1).timeout
	_check(arena._rules.value(cell, "MATERIAL") == "ICE", "Snowgrave freezes water inside its domain")
	_check(arena._rules.matching("ICE", Vector3(11, 0, 13), 1.0).is_empty(), "Snowgrave stays local")
	player.move_and_collide(Vector3(4.45, 0, 0))
	_check(player.position.x > 12.5, "ice supports walking")
	player.position = bank
	await create_timer(1.05).timeout
	_check(arena._rules.value(timber, "INTEGRITY") == 1.0, "Snowgrave pulses damage inside its domain")

	var cold := Intent.create("RITUAL", "CYAN", "NONE", "NONE", 0)
	cold["rules"] = [{"event": "CAST", "scope": "NEARBY", "tag": "WATER", "op": "TRANSFORM", "property": "MATERIAL", "value": "ICE", "radius": 3, "duration": 2}]
	var spell: Dictionary = Intent.compile(cold)["spell"]
	arena._rules.dispatch(spell, "CAST", {"origin": bank, "source": 900})
	arena._end_domain(arena._domains.pop_back())
	_check(arena._rules.value(cell, "MATERIAL") == "ICE", "ending one freeze leaves the overlapping freeze intact")
	player.position = river_midpoint
	arena._rules.advance(2.1, 2.1)
	await create_timer(0.08).timeout
	_check(arena._rules.value(cell, "MATERIAL") == "WATER" and player.position.x < 9.5, "thaw restores water and safe footing")

	_scene._reset_world()
	arena = _scene._arena
	_check(arena._rules.matching("ICE", river_midpoint, 30).is_empty(), "reset restores an unfrozen river")
	var tree := _target_near(Vector3(-2.4, 0.625, -2.6), "TREE")
	var grass: Node3D = arena._rules.matching("GRASS", tree.position, 1.0)[0]
	arena._rules.set_base(tree, "BURNING", 1.0)
	arena._rules.set_base(grass, "BURNING", 1.0)
	_prepare("Aqua")
	_click_toward(tree.global_position + Vector3.UP * 1.7)
	await create_timer(0.5).timeout
	_check(arena._rules.value(tree, "WET") == 1.0 and arena._rules.value(grass, "WET") == 1.0, "Aqua wets impacted wood and nearby grass")
	arena._rules.set_base(tree, "BURNING", 1.0)
	_check(arena._rules.value(tree, "BURNING") == 0.0 and arena._rules.value(grass, "BURNING") == 0.0, "wetness extinguishes and prevents ignition")
	arena._rules.advance(4.1, 4.1)
	_check(arena._rules.value(tree, "WET") == 0.0, "wetness wears off")
	_scene._reset_world()


func _offline_examples(book: Spellbook) -> void:
	var added := book.add_entry("Cinder Pop", "A bright green ball that bursts in a puff of smoke.")
	var id: String = added["entry_id"]
	var entry: Dictionary = book.entries[id]
	_prepare(entry["name"])
	var stale_token: int = _scene._request_token
	_scene._reset_world()
	var generated := Intent.create("ORB", "GREEN", "SMOKE", "BURST", 0)
	_scene._on_resolved(stale_token, {"intent": generated, "source": "Gemma"})
	_check(book.resolution(id).is_empty(), "reset ignores late inference")
	_check(_scene._equipped.is_empty(), "reset clears equipment")
	_prepare("Fireball")
	_prepare(entry["name"])
	await _wait_for_resolution()
	_check(_scene._state_for(id) == "ERROR", "unreachable server reports error")
	_check(_scene._equipped.get("effect") == "IGNITE", "provider failure preserves previous spell")
	_check(book.remember(entry, {"intent": generated}), "valid definition saves in the project")
	var reloaded := Spellbook.new(_save_path)
	_check(reloaded.lookup(entry["name"]) == id and reloaded.entries[id]["description"] == entry["description"], "custom spell reloads with its description")
	_check(reloaded.resolution(id).get("source") == "Cache", "new definition survives reload")
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file != null:
		var snapshot: Dictionary = JSON.parse_string(file.get_as_text())
		file.close()
		snapshot["resolutions"][id]["intent"]["particle"] = "INVALID"
		file = FileAccess.open(_save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshot))
		file.close()
		reloaded = Spellbook.new(_save_path)
		_check(reloaded.resolution(id).is_empty(), "invalid cache is ignored")


func _launch() -> void:
	_scene = Sandbox.instantiate()
	root.add_child(_scene)
	_scene._book = Spellbook.new(_save_path)


func _prepare(spell_name: String) -> void:
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	_scene._input(shift)
	_check(_scene._ui.mode() == "quick", "holding Shift opens name input")
	_scene._ui._quick_field.text = spell_name
	shift.pressed = false
	_scene._input(shift)
	_check(not _scene._ui.has_modal(), "releasing Shift closes name input")


func _click_toward(point: Vector3) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _scene._arena._camera.unproject_position(point)
	_scene._unhandled_input(click)
	_check(_scene._arena._pending_casts.size() == 1, "left click queues a cast")


func _target_near(point: Vector3, kind: String) -> Node3D:
	var closest: Node3D
	var distance := INF
	for target: Node3D in _scene._arena._targets:
		if _scene._arena._targets[target]["kind"] != kind:
			continue
		var candidate := target.global_position.distance_squared_to(point)
		if candidate < distance:
			distance = candidate
			closest = target
	return closest


func _wait_for_resolution() -> void:
	var deadline := Time.get_ticks_msec() + 75000
	while not _scene._pending_entry.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout


func _expect(record: Dictionary, form: String, palette: String, particle: String, effect: String) -> Dictionary:
	var definition: Dictionary = record.get("intent", {})
	print(_scene._ui._detail.text)
	_check(definition.get("form") == form, form + " shape")
	_check(palette.is_empty() or definition.get("palette") == palette, form + " palette")
	_check(particle.is_empty() or definition.get("particle") == particle, form + " particles")
	_check(definition.get("effect") == effect, form + " effect")
	return definition


func _check(passed: bool, description: String) -> void:
	if not passed:
		_failures += 1
		push_error("FAIL: " + description)
