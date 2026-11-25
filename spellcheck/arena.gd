extends Node3D

signal charging(seconds: float)
signal released
signal cast_performed
signal notice(text: String)

const Intent = preload("res://spellcheck/spell_intent.gd")
const Rules = preload("res://spellcheck/magic_rules.gd")
const Fire = preload("res://spellcheck/arena_fire.gd")
const River = preload("res://spellcheck/arena_river.gd")
const ParticleField = preload("res://spellcheck/particle_field.gd")
const BeamVisual = preload("res://spellcheck/beam_visual.gd")
const AfterimageTrail = preload("res://spellcheck/afterimage_trail.gd")
const DOMAIN_SHADER = preload("res://spellcheck/domain.gdshader")
const SCREEN_FILTER_SHADER = preload("res://spellcheck/screen_filter.gdshader")
const ORIGINAL_TINT := Color(-1, -1, -1)
const MATERIAL_TINTS := {
	"WOOD": Color("#926743"), "STONE": Color("#88988e"), "GRASS": Color("#54795a"), "CHARRED": Color("#513429"),
}
const START := Vector3(0, 0.05, 5)
const CAMERA_OFFSET := Vector3(9, 17, 17)
const CAST_HEIGHT := 0.48
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const AIM_LAYER := 4
const MAX_PROJECTILES := 12
const MAX_SPAWNED_TREES := 24
const MAX_BEAMS := 4
const BEAM_LIFETIME := 0.47

var input_enabled := true
var aim_direction := Vector3.FORWARD

var _camera: Camera3D
var _screen_filter: ColorRect
var _player: CharacterBody3D
var _wizard: Node3D
var _afterimages: AfterimageTrail
var _marker: Node3D
var _targets: Dictionary = {}
var _spawned_trees: Dictionary = {}
var _projectiles: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _pending_casts: Array[Dictionary] = []
var _materials: Dictionary = {}
var _last_cast := -1000
var _ward: Node3D
var _rules: Rules
var _fire: Fire
var _river: River
var _charge: Dictionary = {}
var _domains: Array[Dictionary] = []
var _waves: Array[Dictionary] = []
var _source := 0


func _ready() -> void:
	_rules = Rules.new()
	add_child(_rules)
	_rules.property_changed.connect(_apply_world_property)
	_rules.destroyed.connect(_destroy)
	_rules.burst.connect(_burst)
	_rules.spawn_requested.connect(_spawn_prop)
	_rules.register(self, ["WORLD"], {"TIME_SCALE": 1.0})
	_river = River.new()
	add_child(_river)
	_river.setup(_rules, START)
	_build_lighting()
	_build_clearing()
	_build_player()
	_afterimages = AfterimageTrail.new()
	add_child(_afterimages)
	_fire = Fire.new()
	add_child(_fire)
	_fire.setup(_rules, _river.contains)
	_fire.tree_consumed.connect(_destroy)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 20.0
	_camera.current = true
	add_child(_camera)
	_rules.camera = _camera
	_rules.register(_camera, [], {"SCREEN_SATURATION": 1.0})
	_build_screen_filter()
	_update_camera()
	_marker = Node3D.new()
	_marker.position = START + Vector3(0, 0, -3)
	add_child(_marker)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.19
	ring.outer_radius = 0.235
	_mesh(_marker, ring, Vector3.ZERO, _glow(Color("#e5ffce")))
	_box(_marker, Vector3(0.04, 0.012, 0.04), Vector3.ZERO, _glow(Color("#f8ffde")))


func _physics_process(delta: float) -> void:
	var movement := Vector2.ZERO
	if input_enabled:
		movement = Input.get_vector(
			"spellcheck_left", "spellcheck_right", "spellcheck_forward", "spellcheck_back"
		)
	var right := _camera.global_basis.x
	var back := _camera.global_basis.z
	back.y = 0.0
	var motion := (right * movement.x + back.normalized() * movement.y) * 5.6 * float(_rules.value(_player, "SPEED", 1.0))
	_player.velocity.x = motion.x
	_player.velocity.z = motion.z
	var hover: float = _rules.value(_player, "HOVER")
	if hover > 0.0:
		_player.velocity.y = clampf((hover - _player.position.y) * 6.0, -7.0, 7.0)
	else:
		_player.velocity.y -= 18.0 * delta
	_river.prepare_player(_player, hover)
	_player.move_and_slide()
	if absf(_player.position.x) > 18.9 or absf(_player.position.z) > 18.9:
		_player.position.x = clampf(_player.position.x, -18.9, 18.9)
		_player.position.z = clampf(_player.position.z, -18.9, 18.9)
	_river.remember_safe_feet(_player.position)
	_update_camera()
	if input_enabled and get_viewport().gui_get_hovered_control() == null:
		_sample_aim(get_viewport().get_mouse_position())
	_afterimages.advance(delta, _wizard, _rules.value(_player, "AFTERIMAGE", "OFF"))
	var world_step := delta * float(_rules.value(self, "TIME_SCALE", 1.0))
	_rules.advance(delta, world_step)
	if world_step > 0.0:
		_river.advance(world_step)
		_fire.advance(world_step)
		_advance_domains(world_step)
		_advance_projectiles(world_step)
		_advance_waves(world_step)
	_advance_beams(world_step)
	_advance_charge(delta)
	for request: Dictionary in _pending_casts:
		_sample_aim(request["cursor"])
		_start_cast(request["spell"], aim_direction)
	_pending_casts.clear()


func _sample_aim(cursor: Vector2) -> void:
	var origin := _camera.project_ray_origin(cursor)
	var ray := _camera.project_ray_normal(cursor)
	var point: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, ray)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 100.0, WORLD_LAYER | AIM_LAYER)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hovered: Object = hit.get("collider")
	if hovered is Area3D:
		hovered = hovered.get_parent()
	if hovered is Node3D and _targets.has(hovered):
		point = hovered.global_position
		point.y = 0.0
	if point is Vector3:
		var direction: Vector3 = point - _player.position
		direction.y = 0.0
		if direction.length_squared() > 0.025:
			aim_direction = direction.normalized()
			_wizard.rotation.y = atan2(-aim_direction.x, -aim_direction.z)
		_marker.position = point + Vector3.UP * 0.045


func cast(spell: Dictionary, cursor: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_cast < 160 or not _charge.is_empty() or _projectiles.size() >= MAX_PROJECTILES:
		return false
	if spell["form"] == "BEAM" and _beams.size() >= MAX_BEAMS:
		return false
	_last_cast = now
	_pending_casts.append({"spell": spell, "cursor": cursor})
	return true


func _start_cast(spell: Dictionary, direction: Vector3) -> void:
	_source += 1
	var target_point := _marker.global_position
	if spell["charge"] <= 0.0:
		_perform_cast(spell, direction, _source, target_point)
		return
	var focus := Node3D.new()
	_player.add_child(focus)
	focus.position = Vector3.UP * 0.94 + direction * 0.55
	var light := _ball(focus, 0.18, Vector3.ZERO, _glow(spell["color"]))
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	focus.scale = Vector3.ONE * 0.16
	focus.create_tween().tween_property(focus, "scale", Vector3.ONE, spell["charge"])
	_emit_phase(spell, "CHARGE", direction, focus.global_position, focus, spell["charge"], target_point)
	_charge = {
		"spell": spell, "direction": direction, "source": _source, "left": spell["charge"], "visual": focus,
		"target": target_point,
	}
	charging.emit(spell["charge"])


func _advance_charge(delta: float) -> void:
	if _charge.is_empty():
		return
	_charge["left"] -= delta
	if _charge["left"] > 0.0:
		return
	var finished := _charge
	_charge = {}
	finished["visual"].queue_free()
	_perform_cast(finished["spell"], finished["direction"], finished["source"], finished["target"])
	released.emit()


func _perform_cast(spell: Dictionary, direction: Vector3, source: int, target_point: Vector3) -> void:
	var origin := _player.global_position + Vector3.UP * CAST_HEIGHT
	var context := _context(spell, origin, source)
	context["aim"] = target_point
	_rules.dispatch(spell, "CAST", context)
	_emit_phase(spell, "CAST", direction, origin, null, 0.86, target_point)
	match spell["form"]:
		"BEAM":
			_start_beam(spell, direction, target_point, source)
		"ARC":
			_cast_arc(spell, origin, direction, source)
		"WAVE":
			_cast_wave(spell, origin, direction, source)
		"WARD":
			_cast_ward(spell, source, direction)
		"DOMAIN":
			_cast_domain(spell, source, direction)
		"RITUAL":
			_burst(origin, spell["color"])
			_finish_spell(spell, source, origin, direction)
		_:
			_launch_projectile(spell, origin, direction, source)
	cast_performed.emit()


func _launch_projectile(spell: Dictionary, origin: Vector3, direction: Vector3, source: int) -> void:
	var projectile := Node3D.new()
	add_child(projectile)
	projectile.global_position = origin
	var color: Color = spell["color"]
	if spell["form"] == "BOLT":
		_streak(projectile, -direction * 0.65, direction * 0.42, 0.085, _glow(color))
		_streak(projectile, -direction * 0.88, direction * 0.5, 0.16, _glow(color, 0.25))
	else:
		var radius: float = spell["radius"]
		_ball(projectile, radius, Vector3.ZERO, _glow(color))
		var halo := _ball(projectile, radius * 1.45, Vector3.ZERO, _glow(color, 0.24))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail: GPUParticles3D
	if spell["particle"] != "NONE" and not _has_phase(spell, "TRAVEL"):
		trail = _particles(projectile, color, spell["particle"], false)
	var tags := ["PROJECTILE", "MOVING"]
	if spell["effect"] == "IGNITE" or spell["rules"].any(func(rule: Dictionary) -> bool:
		return rule["property"] == "BURNING" and float(rule["value"]) > 0.0
	):
		tags.append("FIRE_PROJECTILE")
	_rules.register(projectile, tags, {"SPEED": 1.0, "TINT": color, "SCALE": 1.0}, true)
	_emit_phase(spell, "TRAVEL", direction, origin, projectile, spell["lifetime"])
	_projectiles.append({
		"node": projectile, "direction": direction, "spell": spell,
		"origin": origin, "travel": 0.0, "source": source,
		"remaining": spell["lifetime"], "trail": trail, "pierced": [] as Array[RID],
	})


func _advance_projectiles(delta: float) -> void:
	for index in range(_projectiles.size() - 1, -1, -1):
		var active := _projectiles[index]
		if not is_instance_valid(active["node"]) or active["node"].is_queued_for_deletion():
			_projectiles.remove_at(index)
			continue
		var projectile: Node3D = active["node"]
		var spell: Dictionary = active["spell"]
		var remaining: float = active["remaining"]
		active["travel"] += minf(delta, remaining) * float(_rules.value(projectile, "SPEED", 1.0))
		var direction: Vector3 = active["direction"]
		var end: Vector3 = (
			active["origin"] + direction * spell["speed"] * active["travel"]
			+ Intent.path_offset(spell, direction, active["travel"])
		)
		end.y = maxf(0.12, end.y)
		var spread: float = spell["radius"] * 0.75 if spell["form"] == "ORB" else 0.07
		var traced := _trace(spell, projectile.global_position, end, active["pierced"], {}, active["source"], spread)
		projectile.global_position = traced["end"]
		if traced["stopped"] or remaining <= delta:
			var trail: GPUParticles3D = active["trail"]
			if is_instance_valid(trail):
				trail.reparent(self, true)
				trail.emitting = false
				var fade := trail.create_tween()
				fade.tween_interval(trail.lifetime)
				fade.tween_callback(trail.queue_free)
			_finish_spell(spell, active["source"], projectile.global_position, direction)
			_destroy(projectile)
			_projectiles.remove_at(index)
		else:
			active["remaining"] = remaining - delta


func _trace(
	spell: Dictionary, from: Vector3, to: Vector3, pierced: Array[RID],
	touched: Dictionary, source: int, spread: float = 0.0, apply_hits: bool = true
) -> Dictionary:
	if from.is_equal_approx(to):
		return {"end": to, "stopped": false}
	var side := (to - from).normalized().cross(Vector3.UP) * spread
	var offsets := [Vector3.ZERO]
	if spread > 0.0:
		offsets.append_array([-side, side])
	while true:
		var nearest: Dictionary = {}
		var distance := INF
		for offset: Vector3 in offsets:
			var query := PhysicsRayQueryParameters3D.create(from + offset, to + offset, WORLD_LAYER, pierced)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and from.distance_squared_to(hit["position"]) < distance:
				nearest = hit
				distance = from.distance_squared_to(hit["position"])
		if nearest.is_empty():
			return {"end": to, "stopped": false}
		var collider: Object = nearest["collider"]
		var pierce := pierced.size() < int(spell["penetration"]) and _targets.has(collider)
		if apply_hits and not touched.has(nearest["rid"]):
			touched[nearest["rid"]] = true
			_impact(spell, nearest["position"], collider, source, (to - from).normalized())
		if not pierce:
			return {"end": nearest["position"], "stopped": true}
		pierced.append(nearest["rid"])
	return {"end": to, "stopped": false}


func _start_beam(spell: Dictionary, direction: Vector3, target: Vector3, source: int) -> void:
	var geometry: Dictionary = spell["beam"]
	var samples := 1 if spell["path"] == "STRAIGHT" else 18
	var view := BeamVisual.new()
	add_child(view)
	view.setup(geometry["lanes"], samples, spell["color"])
	var heading := direction
	if geometry["anchor"] == "EYES":
		var distance := maxf(2.2, direction.dot(target - _player.global_position))
		heading = (direction * distance + Vector3.DOWN * 0.56).normalized()
	var active := {
		"node": view, "spell": spell, "direction": direction, "heading": heading, "source": source,
		"samples": samples, "left": BEAM_LIFETIME, "touched": {}, "origins": [],
	}
	_draw_beam(active, true)
	_beams.append(active)
	if spell["particle"] != "NONE" and not _has_phase(spell, "HIT"):
		var emitter := _particles(view, spell["color"], spell["particle"], true)
		emitter.position = active["end"]
	var midpoint := view.emitter_anchor.global_position
	_emit_phase(spell, "ACTIVE", direction, midpoint, view.emitter_anchor, BEAM_LIFETIME)
	_emit_phase(spell, "TRAVEL", direction, midpoint, view.emitter_anchor, BEAM_LIFETIME)


func _advance_beams(world_step: float) -> void:
	for index in range(_beams.size() - 1, -1, -1):
		var active := _beams[index]
		active["left"] -= world_step
		if active["left"] <= 0.0:
			_finish_spell(active["spell"], active["source"], active["end"], active["direction"])
			active["node"].queue_free()
			_beams.remove_at(index)
			continue
		_draw_beam(active, world_step > 0.0)


func _draw_beam(active: Dictionary, apply_hits: bool) -> void:
	var spell: Dictionary = active["spell"]
	var beam: Dictionary = spell["beam"]
	var view: BeamVisual = active["node"]
	var direction: Vector3 = active["direction"]
	var side := direction.cross(Vector3.UP)
	var muzzle := _player.global_position + Vector3.UP * CAST_HEIGHT
	if beam["anchor"] == "EYES":
		muzzle = _player.global_position + Vector3.UP * 1.05 + direction * 0.2
	var origins: Array[Vector3] = []
	var average := Vector3.ZERO
	var lanes: int = beam["lanes"]
	for lane in range(lanes):
		var offset := Intent.beam_lane_offset(beam, lane) * float(beam["spacing"])
		var origin := muzzle + side * offset
		var heading := Intent.beam_lane_direction(active["heading"], beam, lane)
		var points: Array[Vector3] = [origin]
		var pierced: Array[RID] = []
		var end := origin
		var samples: int = active["samples"]
		for index in range(1, samples + 1):
			var progress := float(index) / samples
			var next := origin + heading * 21.0 * progress + Intent.path_offset(spell, heading, progress * 1.5)
			var width := 0.07 if lanes > 1 else 0.19
			var traced := _trace(spell, end, next, pierced, active["touched"], active["source"], width, apply_hits)
			end = traced["end"]
			points.append(end)
			if traced["stopped"]:
				break
		view.draw_lane(lane, points)
		origins.append(origin)
		average += end
	active["origins"] = origins
	active["end"] = average / lanes
	view.emitter_anchor.global_position = (muzzle + active["end"]) * 0.5


func _cast_arc(spell: Dictionary, origin: Vector3, direction: Vector3, source: int) -> void:
	var pierced: Array[RID] = []
	var touched := {}
	var beam := Node3D.new()
	add_child(beam)
	var color: Color = spell["color"]
	var samples := 18
	var core := _glow(color.lerp(Color.WHITE, 0.62))
	var halo := _glow(color, 0.34)
	var end := origin
	var side := direction.cross(Vector3.UP)
	for index in range(1, samples + 1):
		var progress := float(index) / samples
		var next := origin + direction * 18.0 * progress
		next += Intent.path_offset(spell, direction, progress * 1.5)
		if index < samples:
			next += side * sin(index * 12.19 + source) * 0.35
			next.y += sin(index * 7.19) * 0.22
		var traced := _trace(spell, end, next, pierced, touched, source, 0.13)
		var tip: Vector3 = traced["end"]
		_streak(beam, end, tip, 0.065, core)
		_streak(beam, end, tip, 0.17, halo)
		if index in [3, 6, 9] and not traced["stopped"]:
			var elbow := tip + direction * 0.72 + side * (1.1 if index % 2 == 0 else -1.1) + Vector3.UP * 0.64
			_streak(beam, tip, elbow, 0.038, core)
			_streak(beam, elbow, elbow + direction * 1.24 + side * (0.68 if index % 2 == 0 else -0.68), 0.025, halo)
		end = tip
		if traced["stopped"]:
			break
	if spell["particle"] != "NONE" and not _has_phase(spell, "HIT"):
		var emitter := _particles(beam, color, spell["particle"], true)
		emitter.position = end
	var midpoint := (origin + end) * 0.5
	_emit_phase(spell, "ACTIVE", direction, midpoint, null, 0.47)
	_emit_phase(spell, "TRAVEL", direction, midpoint, null, 0.47)
	_expire(beam, 0.47, _finish_spell.bind(spell, source, end, direction))


func _cast_wave(spell: Dictionary, origin: Vector3, direction: Vector3, source: int) -> void:
	var wave := Node3D.new()
	wave.position = origin
	add_child(wave)
	var color: Color = spell["color"]
	var prior := Vector3.ZERO
	var arms: Array[Dictionary] = []
	var core := _glow(color, 0.94)
	var halo := _glow(color, 0.37)
	for index in range(9):
		var angle := lerpf(-0.62, 0.62, float(index) / 8.0)
		var edge := direction.rotated(Vector3.UP, angle)
		var ripple := Intent.path_offset(spell, edge.cross(Vector3.UP), float(index) / 8.0)
		var point := edge * 7.5 + ripple
		arms.append({"direction": point / 7.5, "stopped": false, "pierced": [] as Array[RID]})
		if index > 0:
			_streak(wave, prior, point, 0.12, core)
			_streak(wave, prior, point, 0.24, halo)
		prior = point
	if spell["particle"] != "NONE":
		var emitter := _particles(wave, color, spell["particle"], true)
		emitter.position = direction * 5.0
	wave.scale = Vector3.ONE * 0.04
	_waves.append({
		"node": wave, "arms": arms, "touched": {}, "spell": spell, "origin": origin,
		"source": source, "direction": direction, "time": 0.0, "core": core, "halo": halo,
	})
	var front := Node3D.new()
	front.position = direction * 7.5
	wave.add_child(front)
	_emit_phase(spell, "ACTIVE", direction, origin, front, 0.74)
	_emit_phase(spell, "TRAVEL", direction, origin, front, 0.74)


func _advance_waves(delta: float) -> void:
	for index in range(_waves.size() - 1, -1, -1):
		var wave := _waves[index]
		var before := minf(7.5, wave["time"] * 19.0)
		wave["time"] += delta
		var distance: float = wave["time"] * 19.0
		var reach := minf(7.5, distance)
		if reach > before:
			for arm: Dictionary in wave["arms"]:
				if arm["stopped"]:
					continue
				var start: Vector3 = wave["origin"] + arm["direction"] * before
				var end: Vector3 = wave["origin"] + arm["direction"] * reach
				arm["stopped"] = _trace(wave["spell"], start, end, arm["pierced"], wave["touched"], wave["source"], 0.15)["stopped"]
		var opacity := 1.0 - smoothstep(4.0, 13.6, distance)
		wave["node"].scale = Vector3.ONE * maxf(0.04, distance / 7.5)
		_set_alpha(wave["core"], opacity * 0.95)
		_set_alpha(wave["halo"], opacity * 0.37)
		if distance >= 13.6:
			_finish_spell(wave["spell"], wave["source"], wave["origin"] + wave["direction"] * reach, wave["direction"])
			wave["node"].queue_free()
			_waves.remove_at(index)


func _cast_ward(spell: Dictionary, source: int, direction: Vector3) -> void:
	if is_instance_valid(_ward):
		_ward.queue_free()
	var ward := Node3D.new()
	_ward = ward
	_player.add_child(ward)
	var color: Color = spell["color"]
	var shell := _ball(ward, 2.35, Vector3.UP * 0.45, _glow(color, 0.16), 32)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := TorusMesh.new()
	ring.inner_radius = 2.23
	ring.outer_radius = 2.34
	_mesh(ward, ring, Vector3.UP * 0.055, _glow(color))
	if spell["particle"] != "NONE":
		_particles(ward, color, spell["particle"], false)
	_emit_phase(spell, "ACTIVE", direction, ward.global_position, ward, 2.6)
	ward.scale = Vector3.ONE * 0.1
	var pulse := ward.create_tween()
	pulse.tween_property(ward, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pulse.tween_interval(2.1)
	pulse.tween_property(ward, "scale", Vector3.ONE * 0.02, 0.22)
	pulse.tween_callback(func() -> void:
		_finish_spell(spell, source, ward.global_position, direction)
		ward.queue_free()
	)


func _cast_domain(spell: Dictionary, source: int, direction: Vector3) -> void:
	var domain := Node3D.new()
	_player.add_child(domain)
	var radius: float = spell["area_radius"]
	var color: Color = spell["color"]
	var field := ShaderMaterial.new()
	field.shader = DOMAIN_SHADER
	field.set_shader_parameter("field_color", color)
	var shell := _ball(domain, radius, Vector3.ZERO, field, 48)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim := TorusMesh.new()
	rim.inner_radius = radius - 0.075
	rim.outer_radius = radius + 0.03
	_mesh(domain, rim, Vector3.UP * 0.065, _glow(color, 0.75)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_view := _cylinder(domain, radius, radius, 0.015, Vector3.UP * 0.024, color, 56)
	floor_view.material_override = _glow(color, 0.16)
	floor_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	domain.scale = Vector3.ONE * 0.08
	domain.create_tween().tween_property(domain, "scale", Vector3.ONE, 0.26).set_ease(Tween.EASE_OUT)
	_emit_phase(spell, "ACTIVE", direction, domain.global_position, domain, spell["duration"])
	if _domains.size() >= 4:
		_end_domain(_domains.pop_front())
	var active := {
		"node": domain, "spell": spell, "source": source, "time": 0.0,
		"members": {}, "schedule": {}, "direction": direction,
	}
	_domains.append(active)
	_update_members(active)


func _advance_domains(delta: float) -> void:
	for index in range(_domains.size() - 1, -1, -1):
		var active := _domains[index]
		var spell: Dictionary = active["spell"]
		active["time"] += delta
		if active["time"] >= spell["duration"]:
			_end_domain(active)
			_domains.remove_at(index)
			continue
		_update_members(active)
		var rules: Array = spell["rules"]
		for slot in range(rules.size()):
			var rule: Dictionary = rules[slot]
			if rule["event"] != "INTERVAL":
				continue
			var next: float = active["schedule"].get(slot, rule["interval"])
			if active["time"] >= next:
				_rules.dispatch(spell, "INTERVAL", _context(spell, active["node"].global_position, active["source"]), slot)
				active["schedule"][slot] = next + rule["interval"]


func _update_members(active: Dictionary) -> void:
	var spell: Dictionary = active["spell"]
	var center: Vector3 = active["node"].global_position
	var context := _context(spell, center, active["source"])
	var previous: Dictionary = active["members"]
	var next := {}
	for entity: Node3D in _rules.matching("ANY", center, spell["area_radius"]):
		if entity == _player:
			continue
		next[entity] = true
		if not previous.has(entity):
			context["member"] = entity
			_rules.dispatch(spell, "ENTER", context)
	for entity in previous:
		if not is_instance_valid(entity) or next.has(entity):
			continue
		context["member"] = entity
		_rules.remove_membership(entity, active["source"])
		_rules.dispatch(spell, "LEAVE", context)
	active["members"] = next


func _end_domain(active: Dictionary) -> void:
	var spell: Dictionary = active["spell"]
	var center: Vector3 = active["node"].global_position
	var context := _context(spell, center, active["source"])
	for entity in active["members"]:
		if is_instance_valid(entity):
			context["member"] = entity
			_rules.remove_membership(entity, active["source"])
			_rules.dispatch(spell, "LEAVE", context)
	_finish_spell(spell, active["source"], center, active["direction"])
	active["node"].queue_free()


func _context(spell: Dictionary, origin: Vector3, source: int) -> Dictionary:
	return {"origin": origin, "radius": spell["area_radius"], "source": source}


func _finish_spell(spell: Dictionary, source: int, point: Vector3, direction: Vector3) -> void:
	_rules.dispatch(spell, "EXPIRE", _context(spell, point, source))
	_emit_phase(spell, "EXPIRE", direction, point)


func _has_phase(spell: Dictionary, phase: String) -> bool:
	return spell["emitters"].any(func(profile: Dictionary) -> bool: return profile["phase"] == phase)


func _emit_phase(
	spell: Dictionary, phase: String, direction: Vector3, point: Vector3,
	carrier: Node3D = null, lifetime: float = 0.86, target_point: Variant = null
) -> void:
	for profile: Dictionary in spell["emitters"]:
		if profile["phase"] != phase or get_tree().get_node_count_in_group("spellcheck_particle_fields") >= 48:
			continue
		var effect := ParticleField.new()
		effect.setup(profile, direction, lifetime)
		effect.add_to_group("spellcheck_particle_fields")
		match profile["anchor"]:
			"CASTER":
				_player.add_child(effect)
				effect.global_position = _player.global_position + Vector3.UP * 0.94 + direction * 0.55
			"SPELL":
				if is_instance_valid(carrier):
					carrier.add_child(effect)
					effect.position = Vector3.ZERO
				else:
					add_child(effect)
					effect.global_position = point
			"TARGET":
				add_child(effect)
				effect.global_position = target_point if target_point is Vector3 else point


func _set_alpha(material: StandardMaterial3D, alpha: float) -> void:
	var color := material.albedo_color
	color.a = alpha
	material.albedo_color = color


func _expire(node: Node3D, delay: float, before_free: Callable = Callable()) -> void:
	var lifetime := node.create_tween()
	lifetime.tween_interval(delay)
	if before_free.is_valid():
		lifetime.tween_callback(before_free)
	lifetime.tween_callback(node.queue_free)


func _impact(spell: Dictionary, point: Vector3, collider: Object, source: int, direction: Vector3) -> void:
	var context := _context(spell, point, source)
	if _rules.entities.has(collider):
		context["hit"] = collider
	_rules.dispatch(spell, "HIT", context)
	_emit_phase(spell, "HIT", direction, point)


func _destroy(prop: Node3D) -> void:
	if _rules.entities.has(prop):
		_rules.forget(prop)
		_targets.erase(prop)
		_spawned_trees.erase(prop)
		prop.queue_free()


func _spawn_prop(archetype: String, point: Vector3, count: int) -> void:
	if archetype != "TREE":
		return
	var offsets := [Vector2.ZERO, Vector2(1.6, 0), Vector2(-1.6, 0), Vector2(0, 1.6), Vector2(0, -1.6),
		Vector2(1.6, 1.6), Vector2(-1.6, 1.6), Vector2(1.6, -1.6), Vector2(-1.6, -1.6)]
	var center := Vector2(clampf(point.x, -17.3, 17.3), clampf(point.z, -17.3, 17.3))
	var planted := 0
	for offset: Vector2 in offsets:
		if planted == count or _spawned_trees.size() >= MAX_SPAWNED_TREES:
			break
		var candidate := center + offset
		if absf(candidate.x) > 18.0 or absf(candidate.y) > 18.0:
			continue
		if _river.contains(Vector3(candidate.x, 0, candidate.y), 1.0):
			continue
		var player_point := Vector2(_player.position.x, _player.position.z)
		if candidate.distance_squared_to(player_point) < 1.3:
			continue
		var occupied := false
		for target: Node3D in _targets:
			var location := Vector2(target.position.x, target.position.z)
			if candidate.distance_squared_to(location) < 1.8:
				occupied = true
				break
		if occupied:
			continue
		var ground := Vector3(candidate.x, 0.0, candidate.y)
		var tree := _add_tree(ground, 2.2, Color("#497b56"), Color("#6b9c53"))
		_spawned_trees[tree] = true
		_burst(ground + Vector3.UP * 0.5, Color("#a9ed73"))
		planted += 1
	if planted == 0:
		notice.emit("No room to plant a tree here.")


func _register_prop(prop: Node3D, kind: String, material: String, integrity: float) -> void:
	var meshes := {}
	var bounds := AABB()
	for child in prop.get_children():
		if child is MeshInstance3D:
			meshes[child] = child.material_override
			var extent: AABB = child.transform * child.get_aabb()
			bounds = extent if meshes.size() == 1 else bounds.merge(extent)
	_targets[prop] = {
		"kind": kind, "burning": false, "integrity": integrity, "material": material, "meshes": meshes, "bounds": bounds,
	}
	_rules.register(prop, [kind], {
		"TINT": ORIGINAL_TINT, "ROTATION": 0.0, "SCALE": 1.0, "INTEGRITY": integrity,
		"BURNING": 0.0, "TEMPERATURE": 0.0, "WET": 0.0, "MATERIAL": material,
	}, true)


func _apply_world_property(node: Node3D, property: String, value: Variant) -> void:
	if node == self and property == "TIME_SCALE":
		var rate := float(value)
		if is_equal_approx(rate, 0.0):
			notice.emit("Arena time stopped.")
		elif is_equal_approx(rate, 1.0):
			notice.emit("Arena time resumed.")
		else:
			notice.emit("Arena time ×%.2f." % rate)
		return
	if node == _camera and property == "SCREEN_SATURATION":
		_screen_filter.material.set_shader_parameter("saturation", value)
		_screen_filter.visible = not is_equal_approx(float(value), 1.0)
		return
	if _targets.has(node):
		var prop: Dictionary = _targets[node]
		match property:
			"ROTATION", "SCALE":
				node.rotation.z = deg_to_rad(_rules.value(node, "ROTATION"))
				node.scale = Vector3.ONE * float(_rules.value(node, "SCALE", 1.0))
				var visual_bounds: AABB = Transform3D(node.basis, Vector3.ZERO) * prop["bounds"]
				node.position.y = -visual_bounds.position.y
			"INTEGRITY":
				prop["integrity"] = value
			"BURNING", "TINT", "MATERIAL", "WET":
				if property == "BURNING":
					prop["burning"] = float(value) >= 0.5
					if prop["burning"]:
						prop["charred"] = true
				var tint: Color = _rules.value(node, "TINT", ORIGINAL_TINT)
				if tint == ORIGINAL_TINT:
					var material: String = _rules.value(node, "MATERIAL")
					if prop.get("charred", false):
						tint = MATERIAL_TINTS["CHARRED"]
					elif material != prop["material"]:
						tint = MATERIAL_TINTS[material]
				for mesh: MeshInstance3D in prop["meshes"]:
					var wet_tint := tint
					var original: StandardMaterial3D = prop["meshes"][mesh]
					if float(_rules.value(node, "WET")) >= 0.5:
						wet_tint = (original.albedo_color if tint == ORIGINAL_TINT else tint).lerp(Color("#254f5a"), 0.45)
					mesh.material_override = original if wet_tint == ORIGINAL_TINT else _material(wet_tint)
			"TEMPERATURE":
				if float(value) >= 60.0 and _rules.value(node, "MATERIAL") == "WOOD":
					_rules.set_base(node, "BURNING", 1.0)
		return
	if node == _player and property == "SCALE":
		_wizard.scale = Vector3.ONE * float(value)
	elif "PROJECTILE" in _rules.entities[node]["tags"]:
		if property == "SCALE":
			node.scale = Vector3.ONE * float(value)
		elif property == "TINT":
			for child in node.get_children():
				if child is MeshInstance3D and child.material_override is StandardMaterial3D:
					var material: StandardMaterial3D = child.material_override
					var color: Color = value
					color.a = material.albedo_color.a
					material.albedo_color = color


func _update_camera() -> void:
	var focus := _player.position
	_camera.position = focus + CAMERA_OFFSET
	_camera.look_at(focus + Vector3.UP * 0.4, Vector3.UP)


func _build_screen_filter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_screen_filter = ColorRect.new()
	_screen_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filter := ShaderMaterial.new()
	filter.shader = SCREEN_FILTER_SHADER
	_screen_filter.material = filter
	_screen_filter.hide()
	layer.add_child(_screen_filter)
	_screen_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	var scene_environment := Environment.new()
	scene_environment.background_mode = Environment.BG_COLOR
	scene_environment.background_color = Color("#344f53")
	scene_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene_environment.ambient_light_color = Color("#b4c3be")
	scene_environment.ambient_light_energy = 0.68
	world.environment = scene_environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53, -42, 0)
	sun.light_color = Color("#fff1cd")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45
	add_child(sun)


func _build_clearing() -> void:
	_solid_box(Vector3(42, 0.8, 42), Vector3(0, -0.4, 0), Color("#456951"))
	_cylinder(self, 7.4, 8.5, 0.055, Vector3(0, -0.019, 1), Color("#8a855b"), 44)
	_cylinder(self, 5.9, 7.0, 0.052, Vector3(0, -0.013, 1), Color("#a29466"), 44)
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(42, 1.35, 0.7), Vector3(0, 0.65, 19.5 * side), Color("#65756b"))
		_solid_box(Vector3(0.7, 1.35, 42), Vector3(19.5 * side, 0.65, 0), Color("#65756b"))

	_add_target(Vector3(0, 0, -5), 0.0, true)
	_add_target(Vector3(4.7, 0, -3.4), -0.27, false)
	_add_target(Vector3(-4.2, 0, -2.1), 0.21, false)
	_add_rock(Vector3(2.2, 0, -1.6), 0.88, 0.4)
	_add_rock(Vector3(2.95, 0, -3.8), 0.76, -0.5)
	var tree_colors := [Color("#365c50"), Color("#497b56"), Color("#588655")]
	_add_tree(Vector3(-2.4, 0, -2.6), 2.2, tree_colors[0], tree_colors[2])
	var random := RandomNumberGenerator.new()
	random.seed = 51273
	for index in range(27):
		var theta := TAU * index / 27.0 + random.randf_range(-0.09, 0.09)
		var radius := random.randf_range(11.0, 17.8)
		var point := Vector3(cos(theta), 0, sin(theta)) * radius
		var height := random.randf_range(1.8, 3.15)
		if not _river.contains(point, 1.6):
			_add_tree(point, height, tree_colors[index % 3], tree_colors[(index + 1) % 3])
	for index in range(38):
		var theta := random.randf_range(0.0, TAU)
		var radius := random.randf_range(8.1, 18.8)
		var point := Vector3(cos(theta), 0, sin(theta)) * radius
		var size := random.randf_range(0.48, 0.86)
		if not _river.contains(point, 1.2):
			_add_rock(point, size, theta)
	for index in range(70):
		var theta := random.randf_range(0.0, TAU)
		var radius := random.randf_range(8.1, 19.0)
		var height := random.randf_range(0.17, 0.42)
		var point := Vector3(cos(theta) * radius, height * 0.5, sin(theta) * radius)
		if not _river.contains(point, 0.25):
			var tuft := _cylinder(self, 0.03, 0.19, height, point, tree_colors[index % 3], 3)
			tuft.rotation.z = 0.2


func _add_tree(point: Vector3, height: float, shade: Color, tip: Color) -> StaticBody3D:
	var tree := _solid_box(Vector3(0.56, 1.25, 0.56), point + Vector3.UP * 0.625, Color("#67533d"))
	_cylinder(tree, 0.0, height * 0.44, height, Vector3.UP * height * 0.63, shade, 6)
	_cylinder(tree, 0.0, height * 0.34, height * 0.82, Vector3.UP * height, tip, 6)
	_register_prop(tree, "TREE", "WOOD", 2)
	var canopy := Area3D.new()
	canopy.collision_layer = AIM_LAYER
	canopy.collision_mask = 0
	canopy.monitorable = false
	canopy.monitoring = false
	canopy.position.y = height * 0.77
	tree.add_child(canopy)
	var proxy := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = height * 1.2
	shape.radius = height * 0.44
	proxy.shape = shape
	canopy.add_child(proxy)
	return tree


func _add_rock(point: Vector3, size: float, yaw: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size * 1.66, maxf(0.64, size * 1.1), size * 1.25)
	var body := _static_body(point + Vector3.UP * size * 0.38, shape)
	body.rotation.y = yaw
	var rock := _ball(body, size, Vector3.ZERO, _material(Color("#768174")), 6)
	rock.scale = Vector3(1.05, 0.66, 0.82)
	_register_prop(body, "ROCK", "STONE", 3)


func _add_target(point: Vector3, yaw: float, primary: bool) -> void:
	var prop := _solid_box(Vector3(1.65, 1.7, 0.38), point + Vector3.UP * 0.85, Color("#926743"))
	prop.rotation.y = yaw
	var trim := _material(Color("#5e4935"))
	for x: float in [-0.66, -0.34, 0.0, 0.34, 0.66]:
		_box(prop, Vector3(0.025, 1.64, 0.025), Vector3(x, 0, 0.2), trim)
	for y: float in [-0.6, 0.55]:
		_box(prop, Vector3(1.76, 0.16, 0.48), Vector3(0, y, 0), trim)
	_cylinder(prop, 0.32, 0.32, 0.045, Vector3(0, 0.06, 0.22), Color("#e9c58d"), 20).rotation.x = PI / 2.0
	_cylinder(prop, 0.15, 0.15, 0.055, Vector3(0, 0.06, 0.24), Color("#a95743"), 20).rotation.x = PI / 2.0
	if primary:
		var label := Label3D.new()
		label.text = "Timber target"
		label.font_size = 34
		label.pixel_size = 0.0095
		label.outline_size = 8
		label.position.y = 1.2
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		prop.add_child(label)
	_register_prop(prop, "TIMBER", "WOOD", 2)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.position = START
	_player.collision_layer = PLAYER_LAYER
	_player.collision_mask = WORLD_LAYER
	add_child(_player)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.38
	shape.shape = capsule
	shape.position.y = 0.7
	_player.add_child(shape)
	_wizard = Node3D.new()
	_player.add_child(_wizard)
	_cylinder(_wizard, 0.24, 0.43, 0.82, Vector3.UP * 0.51, Color("#563a7f"), 8)
	_cylinder(_wizard, 0.33, 0.38, 0.09, Vector3.UP * 0.49, Color("#ceab65"), 8)
	_ball(_wizard, 0.225, Vector3.UP * 1.04, _material(Color("#edc398")), 12)
	_cylinder(_wizard, 0.51, 0.51, 0.08, Vector3.UP * 1.23, Color("#362658"), 12)
	_cylinder(_wizard, 0.025, 0.32, 0.58, Vector3.UP * 1.53, Color("#563a7f"), 10)
	var staff := Vector3(0.44, 0.63, -0.12)
	_cylinder(_wizard, 0.04, 0.05, 1.02, staff, Color("#674732"), 8)
	_ball(_wizard, 0.11, staff + Vector3.UP * 0.57, _glow(Color("#beffb5")), 12)
	_rules.caster = _player
	_rules.register(_player, ["MOVING"], {"SPEED": 1.0, "SCALE": 1.0, "HOVER": 0.0, "AFTERIMAGE": "OFF"})


func _burst(point: Vector3, color: Color) -> void:
	var flash := Node3D.new()
	flash.position = to_local(point)
	add_child(flash)
	_particles(flash, color, "SPARKS", true)
	var glow := _ball(flash, 0.34, Vector3.ZERO, _glow(color, 0.68))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var expansion := flash.create_tween()
	expansion.tween_property(glow, "scale", Vector3.ONE * 3.0, 0.15)
	expansion.tween_callback(glow.hide)
	expansion.tween_interval(0.5)
	expansion.tween_callback(flash.queue_free)


func _particles(parent: Node3D, color: Color, style: String, burst: bool) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.emitting = false
	emitter.amount = 26 if burst else 19
	emitter.lifetime = 0.56 if burst else 0.68
	emitter.one_shot = burst
	emitter.explosiveness = 1.0 if burst else 0.0
	emitter.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0 if burst else 50.0
	process.gravity = Vector3(0, 0.7, 0) if style == "SMOKE" else Vector3(0, -2.5, 0)
	process.initial_velocity_min = 1.2 if burst else 0.18
	process.initial_velocity_max = 4.4 if burst else 0.62
	process.scale_min = 0.65
	process.scale_max = 1.35
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	emitter.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.18 if style == "SMOKE" else 0.058
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	if style == "SMOKE":
		var scale_curve := Curve.new()
		scale_curve.add_point(Vector2(0, 0.45))
		scale_curve.add_point(Vector2(1, 1.0))
		var scale_texture := CurveTexture.new()
		scale_texture.curve = scale_curve
		process.scale_curve = scale_texture
		mesh.material = _glow(color.lerp(Color("#738877"), 0.68), 0.45)
	elif style == "MAGIC":
		mesh.material = _glow(color.lerp(Color.WHITE, 0.2), 0.85)
	else:
		mesh.material = _glow(color, 0.96)
	emitter.draw_pass_1 = mesh
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(emitter)
	emitter.emitting = true
	return emitter


func _solid_box(size: Vector3, point: Vector3, color: Color) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = size
	var body := _static_body(point, box)
	_box(body, size, Vector3.ZERO, _material(color))
	return body


func _static_body(point: Vector3, collision: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = WORLD_LAYER
	add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = collision
	body.add_child(shape)
	return body


func _streak(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var axis := to - from
	if axis.length_squared() < 0.0001:
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = axis.length()
	cylinder.radial_segments = 10
	var view := _mesh(parent, cylinder, (from + to) * 0.5, material)
	view.quaternion = Quaternion(Vector3.UP, axis.normalized())
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(parent: Node3D, size: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, point, material)


func _ball(parent: Node3D, radius: float, point: Vector3, material: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	return _mesh(parent, mesh, point, material)


func _cylinder(
	parent: Node3D, top: float, bottom: float, height: float, point: Vector3, color: Color, sides: int
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(parent, mesh, point, _material(color))


func _mesh(parent: Node3D, mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.position = point
	view.mesh = mesh
	view.material_override = material
	parent.add_child(view)
	return view


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		_materials[color] = material
	return _materials[color]


func _glow(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
	return material
