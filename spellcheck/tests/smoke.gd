extends SceneTree

const SANDBOX_PATH := "res://spellcheck/sandbox.tscn"
const Spellbook = preload("res://spellcheck/spellbook.gd")
const Resolver = preload("res://spellcheck/spell_resolver.gd")
const Intent = preload("res://spellcheck/spell_intent.gd")
const Catalog = preload("res://spellcheck/spell_catalog.gd")
const Rules = preload("res://spellcheck/magic_rules.gd")

var _scene
var _crafting: Node
var _save_path := "res://spellcheck/local/smoke-%d/spellbook.json" % OS.get_process_id()
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_crafting = root.get_node("Crafting")
	var previous_book: Spellbook = _crafting.book
	_launch()
	var book: Spellbook = _scene._book
	_check(book.entries.size() == 1, "only Fireball starts unlocked")
	_check(book.lookup(" FIRE    BALL ") == "classic.fireball", "normalized alias")
	_check(book.suggestions("Firball") == ["classic.fireball"], "Fireball typo")
	_check(_crafting.begin("fire ball", "").has("error"), "duplicate unlocked alias")
	_prepare("Snowgrave")
	_check(_scene._equipped.is_empty(), "locked preset cannot equip")
	_check(Resolver.decode({"message": {"content": "{}"}}).has("error"), "malformed decision rejected")
	_check(Intent.compile(Intent.create("ORB", "ORANGE", "SMOKE", "IGNITE", 9)).has("error"), "unsafe power rejected")
	var old_intent := Intent.create("ORB", "ORANGE", "SMOKE", "IGNITE", 1)
	old_intent["schema_version"] = 2
	_check(Intent.compile(old_intent).has("error"), "compiler accepts only the current spell schema")
	_delivery_schema()
	_afterimage_policy()
	_scene._open_book()
	_check(_scene._ui._list.item_count == 1, "unfiltered book shows only unlocked entries")
	_scene._ui.close_modal()
	for name in ["Levitate", "Snowgrave", "Aqua"]:
		_check(_earn_fixture(_crafting.begin(name, ""), name).is_empty(), "unlock %s fixture" % name)

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
	await _utility_runtime()
	await _beam_runtime()
	await _river_runtime()

	var args := OS.get_cmdline_user_args()
	if "--planner" in args or "--live" in args:
		await _collision_reference_live()
		await _planner_live()
		await _attack_trails_live()
	else:
		_offline_examples(book)
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
		DirAccess.remove_absolute(_save_path.get_base_dir())
	_crafting.book = previous_book
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


func _collision_reference_live() -> void:
	var name := "DESTRUCTO DISC"
	_scene._reset_world()
	await _craft_and_equip(name)
	print(_scene._ui._detail.text)
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


func _afterimage_policy() -> void:
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



func _rule_properties(result: Dictionary) -> Array:
	return result.get("intent", {}).get("rules", []).map(func(rule: Dictionary) -> String: return rule["property"])


func _decode_rules(intent: Dictionary, request: String) -> Dictionary:
	var draft := intent.duplicate()
	draft.erase("schema_version")
	draft.merge({"status": "COMPOSED", "meaning": "Test cast", "reference": ""})
	return Resolver.decode({"message": {"content": JSON.stringify(draft)}}, request)


func _attack_trails_live() -> void:
	for name in ["Heat Vision", "Nuclear Bomb"]:
		_scene._reset_world()
		await _craft_and_equip(name)
		_check(not _scene._equipped.get("rules", []).any(func(rule: Dictionary) -> bool:
			return rule["property"] == "AFTERIMAGE"
		), "%s has no unrelated caster trail" % name)


func _planner_live() -> void:
	for sample in [
		["Quick Accent", "It works like David's Sandevistan from Cyberpunk: Edgerunners."],
		["Mauve Hour", "For two seconds double my movement speed, make the world move at half speed, and leave rainbow copies of me behind as I move."],
	]:
		_scene._reset_world()
		await _craft_and_equip(sample[0], sample[1])
		if _scene._equipped.is_empty():
			continue
		var arena = _scene._arena
		_click_toward(Vector3.FORWARD)
		await create_timer(float(_scene._equipped["charge"]) + 0.09).timeout
		_check(arena._rules.value(arena._player, "SPEED") > 1.0, "combo speeds up the caster")
		_check(arena._rules.value(arena, "TIME_SCALE") < 1.0, "combo slows down the arena")
		_check(arena._rules.value(arena._player, "AFTERIMAGE") == "RAINBOW", "combo selects multicolored afterimages")

	_scene._reset_world()
	var arena = _scene._arena
	arena._player.position = Vector3(8.7, 0.05, 0)
	await _craft_and_equip("Winter Footing", "Freeze river water within six meters of me into walkable ice for four seconds.")
	if not _scene._equipped.is_empty():
		_click_toward(Vector3(11, 0, 0))
		await create_timer(float(_scene._equipped["charge"]) + 0.1).timeout
		_check(not arena._rules.matching("ICE", Vector3(11, 0, 0), 1.0).is_empty(), "generated spell physically freezes river cells")


func _utility_runtime() -> void:
	_scene._reset_world()
	_prepare("DD")
	_check(_scene._equipped.is_empty(), "unlocked-only input rejects unknown names")
	_prepare("zxqvplmtrn")
	_check(_scene._equipped.is_empty(), "unlocked-only input rejects unknown text")

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
		_check(is_instance_valid(flying) and flying.position.is_equal_approx(frozen_at), "world time freezes projectile movement")
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
	var reloaded := Spellbook.new(_save_path)
	for name in ["Levitate", "Snowgrave", "Aqua"]:
		var id := book.lookup(name)
		_check(not id.is_empty() and reloaded.lookup(name) == id, "fixture unlock survives reload")
		_check(not reloaded.resolution(id).is_empty(), "unlocked fixture retains its behavior")
	_scene._reset_world()
	_prepare("Cinder Pop")
	_check(_scene._equipped.is_empty(), "unknown spells do not equip in the sandbox")


func _launch() -> void:
	_crafting.book = Spellbook.new(_save_path)
	_scene = load(SANDBOX_PATH).instantiate()
	root.add_child(_scene)


func _earn_fixture(draft: Dictionary, name: String) -> String:
	if draft.has("error"):
		return draft["error"]
	var recipe := {"name": name, "description": "Smoke test recipe", "elements": [
		"Aqua", "Aer", "Ignis", "Terra", "Lux", "Tenebrae",
	]}
	return _crafting.earn(draft["id"], recipe, 1.0, 0, {"source": "Test"})


func _craft_and_equip(name: String, description: String = "") -> void:
	var draft: Dictionary = _crafting.begin(name, description)
	var error := _earn_fixture(draft, name)
	_check(error.is_empty(), "%s can be earned: %s" % [name, error])
	if not error.is_empty():
		return
	var deadline := Time.get_ticks_msec() + 75000
	while _crafting.book.lookup(name).is_empty() and Time.get_ticks_msec() < deadline:
		var record: Dictionary = _crafting.book.record(draft["id"])
		if not str(record.get("error", "")).is_empty():
			break
		await create_timer(0.05).timeout
	var id: String = _crafting.book.lookup(name)
	var record: Dictionary = _crafting.book.record(draft["id"])
	_check(not id.is_empty(), "%s unlocks: %s" % [name, record.get("error", "")])
	if id.is_empty():
		return
	_prepare(name)


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
	# These cases test spell effects. Clear the wall-clock click cooldown so a
	# headless simulation timer can advance independently of that clock.
	_scene._arena._last_cast = Time.get_ticks_msec() - 1000
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


func _check(passed: bool, description: String) -> void:
	if not passed:
		_failures += 1
		push_error("FAIL: " + description)
