extends Node3D

signal tree_consumed(tree: Node3D)

const Rules = preload("res://spellcheck/magic_rules.gd")
const GRASS_SHADER = preload("res://spellcheck/grass.gdshader")
const FLAME_SHADER = preload("res://spellcheck/fire.gdshader")
const ParticleField = preload("res://spellcheck/particle_field.gd")
const GRASS := Color("#456951")
const CELL := 2.35
const MAX_FIRES := 32

var _rules: Rules
var _grass: Array[MeshInstance3D] = []
var _fires: Dictionary = {}
var _grass_plane: PlaneMesh
var _spread_depth := 0


func setup(rules: Rules, is_river: Callable) -> void:
	_rules = rules
	_rules.property_changed.connect(_property_changed)
	var grass_material := ShaderMaterial.new()
	grass_material.shader = GRASS_SHADER
	_grass_plane = PlaneMesh.new()
	_grass_plane.size = Vector2.ONE * CELL * 1.045
	_grass_plane.material = grass_material
	for x in range(-7, 8):
		for z in range(-7, 8):
			var position_in_arena := Vector3(x * CELL, 0.026, z * CELL)
			if position_in_arena.distance_to(Vector3(0, 0, 1)) >= 7.3 and not is_river.call(position_in_arena, CELL * 0.55):
				_add_grass(position_in_arena)
	# These patches let fire spread near the demonstration tree on the clearing.
	_add_grass(Vector3(-2.4, 0.026, -2.6))
	_add_grass(Vector3(-4.75, 0.026, -2.6))
	_add_grass(Vector3(-4.75, 0.026, -4.95))


func advance(delta: float) -> void:
	for target: Node3D in _fires.keys():
		var fire: Dictionary = _fires.get(target, {})
		if fire.is_empty():
			continue
		if not is_instance_valid(target) or not _rules.entities.has(target):
			_fires.erase(target)
			continue
		fire["age"] += delta
		if not fire["spread"] and fire["age"] >= 0.6:
			fire["spread"] = true
			_spread(target, fire["depth"])
		if fire["age"] >= fire["duration"]:
			_rules.set_base(target, "BURNING", 0.0)
			_rules.set_base(target, "TEMPERATURE", 0.0)
			if "TREE" in _rules.entities.get(target, {}).get("tags", []):
				tree_consumed.emit(target)


func _add_grass(point: Vector3) -> void:
	var patch := MeshInstance3D.new()
	patch.mesh = _grass_plane
	patch.position = point
	patch.hide()
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)
	_grass.append(patch)
	_rules.register(patch, ["GRASS"], {
		"TINT": GRASS, "SCORCH": 0.0, "TEMPERATURE": 0.0, "BURNING": 0.0, "WET": 0.0, "MATERIAL": "GRASS",
	})
	patch.set_instance_shader_parameter("ground_tint", GRASS)


func _property_changed(target: Node3D, property: String, next: Variant) -> void:
	var grass := target is MeshInstance3D and _grass.has(target)
	if grass and property == "TEMPERATURE" and float(next) >= 60.0:
		_rules.set_base(target, "BURNING", 1.0)
	if grass and property in ["TINT", "SCORCH", "MATERIAL", "WET"]:
		var tint: Color = _rules.value(target, "TINT", GRASS)
		var scorch: float = _rules.value(target, "SCORCH")
		match _rules.value(target, "MATERIAL"):
			"CHARRED":
				scorch = maxf(scorch, 0.85)
			"WOOD":
				tint = tint.lerp(Color("#926743"), 0.65)
			"STONE":
				tint = tint.lerp(Color("#a1a69f"), 0.8)
		if float(_rules.value(target, "WET")) >= 0.5:
			tint = tint.lerp(Color("#285c63"), 0.5)
		target.visible = scorch > 0.001 or tint != GRASS
		target.set_instance_shader_parameter("ground_tint", tint)
		target.set_instance_shader_parameter("scorch", scorch)
	if property == "BURNING":
		if float(next) >= 0.5:
			_ignite(target, grass)
		elif _fires.has(target):
			var visual: Node3D = _fires[target]["visual"]
			if is_instance_valid(visual):
				visual.queue_free()
			_fires.erase(target)


func _ignite(target: Node3D, grass: bool) -> void:
	if _fires.has(target):
		return
	if _fires.size() >= MAX_FIRES:
		if grass:
			_rules.set_base(target, "SCORCH", 1.0)
		_rules.set_base(target, "BURNING", 0.0)
		return
	var flames := Node3D.new()
	target.add_child(flames)
	var offsets := [
		Vector3(-0.48, 0.47, 0.2), Vector3(0.4, 0.52, -0.24), Vector3(0.04, 0.74, 0.26),
	]
	for index in range(offsets.size()):
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.88, 1.36) if grass else Vector2(1.1, 1.85)
		var material := ShaderMaterial.new()
		material.shader = FLAME_SHADER
		material.set_shader_parameter("shift", float(index) * 1.14 + float(target.get_instance_id() % 17))
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.material_override = material
		view.rotation.y = index * TAU / 3.0
		view.position = offsets[index]
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.add_child(view)
	var duration := 2.3 if grass else 3.6
	_fire_particles(flames, Color("#ff9b42"), 3.2, 0.075, 12, duration)
	_fire_particles(flames, Color(0.39, 0.33, 0.27, 0.22), 5.0, 0.32, 8, duration)
	_fires[target] = {"visual": flames, "age": 0.0, "depth": _spread_depth, "spread": false, "duration": duration}
	var on_exit := _forget_fire.bind(target)
	if not target.tree_exiting.is_connected(on_exit):
		target.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	if grass:
		_rules.set_base(target, "SCORCH", 1.0)
	_rules.set_base(target, "TEMPERATURE", 92.0)


func _fire_particles(parent: Node3D, color: Color, speed: float, size: float, count: int, duration: float) -> void:
	var field := ParticleField.new()
	field.setup({"phase": "ACTIVE", "direction": "UP", "shape": "MOTE", "color": color, "speed": speed, "size": size, "count": count}, Vector3.UP, duration)
	field.position.y = 0.45
	parent.add_child(field)


func _forget_fire(target: Node3D) -> void:
	_fires.erase(target)


func _spread(source: Node3D, depth: int) -> void:
	if depth >= 2:
		return
	var neighbors := _rules.matching("GRASS", source.global_position, CELL * 1.35)
	neighbors.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(source.global_position) < b.global_position.distance_squared_to(source.global_position)
	)
	var ignited := 0
	for patch: Node3D in neighbors:
		if float(_rules.value(patch, "SCORCH")) > 0.5 or float(_rules.value(patch, "WET")) >= 0.5:
			continue
		_spread_depth = depth + 1
		_rules.set_base(patch, "BURNING", 1.0)
		_spread_depth = 0
		ignited += 1
		if ignited >= 2:
			break
