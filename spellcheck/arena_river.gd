extends Node3D

const Rules = preload("res://spellcheck/magic_rules.gd")
const SURFACE = preload("res://spellcheck/river.gdshader")
const BLOCKER_LAYER_NUMBER := 4
const BLOCKER_LAYER := 1 << (BLOCKER_LAYER_NUMBER - 1)
const CENTER_X := 11.0
const WIDTH := 3.0
const CELL_LENGTH := 2.0
const HALF_LENGTH := 19.0
const BRIDGE_Z := 4.0
const CLEARANCE := 0.4

var _cells: Array[StaticBody3D] = []
var _last_safe := Vector3.ZERO
var _rules: Rules
var _surface: ShaderMaterial
var _animation_time := 0.0


func setup(rules: Rules, start: Vector3) -> void:
	_rules = rules
	_last_safe = start
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(WIDTH, CELL_LENGTH)
	_surface = ShaderMaterial.new()
	_surface.shader = SURFACE
	water_mesh.material = _surface
	var blocker := BoxShape3D.new()
	blocker.size = Vector3(WIDTH, CLEARANCE, CELL_LENGTH)

	for index in range(int(HALF_LENGTH * 2.0 / CELL_LENGTH)):
		var cell := StaticBody3D.new()
		cell.position = Vector3(CENTER_X, 0, (index + 0.5) * CELL_LENGTH - HALF_LENGTH)
		cell.collision_mask = 0
		cell.collision_layer = 0 if _bridge_cell(cell.position.z) else BLOCKER_LAYER
		add_child(cell)
		var collision := CollisionShape3D.new()
		collision.position.y = CLEARANCE * 0.5
		collision.shape = blocker
		cell.add_child(collision)
		var mesh := MeshInstance3D.new()
		mesh.mesh = water_mesh
		mesh.position.y = 0.035
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cell.add_child(mesh)
		_cells.append(cell)
		_rules.register(cell, ["WATER"], {"MATERIAL": "WATER", "TINT": Color.TRANSPARENT})

	var plank := BoxMesh.new()
	plank.size = Vector3(WIDTH + 1.3, 0.08, 0.21)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#79563c")
	plank.material = wood
	for index in 9:
		var deck := MeshInstance3D.new()
		deck.mesh = plank
		deck.position = Vector3(CENTER_X, 0.082, BRIDGE_Z + (index - 4) * 0.22)
		add_child(deck)
	_rules.property_changed.connect(_on_property)


func contains(point: Vector3, margin: float = 0.0) -> bool:
	return absf(point.x - CENTER_X) < WIDTH * 0.5 + margin and absf(point.z) < HALF_LENGTH + margin


func advance(world_delta: float) -> void:
	_animation_time += world_delta
	_surface.set_shader_parameter("animation_time", _animation_time)


func prepare_player(player: CharacterBody3D, hover: float) -> void:
	var feet := player.position
	var clears_water := hover >= CLEARANCE and feet.y >= CLEARANCE
	player.set_collision_mask_value(BLOCKER_LAYER_NUMBER, not clears_water)
	if contains(feet) and not _bridge_cell(feet.z) and not clears_water:
		var index := clampi(floori((feet.z + HALF_LENGTH) / CELL_LENGTH), 0, _cells.size() - 1)
		if _rules.value(_cells[index], "MATERIAL") == "WATER":
			player.position = _last_safe
			player.velocity.y = 0.0


func remember_safe_feet(feet: Vector3) -> void:
	if not contains(feet, 0.36) or absf(feet.z - BRIDGE_Z) < 0.6:
		_last_safe = Vector3(feet.x, 0.05, feet.z)


func _bridge_cell(z: float) -> bool:
	return absf(z - BRIDGE_Z) < CELL_LENGTH * 0.5


func _on_property(entity: Node3D, property: String, value: Variant) -> void:
	if property not in ["MATERIAL", "TINT"] or not entity is StaticBody3D or entity not in _cells:
		return
	var mesh: MeshInstance3D = entity.get_child(1)
	match property:
		"MATERIAL":
			var frozen: bool = value == "ICE"
			entity.set_deferred("collision_layer", 0 if frozen or _bridge_cell(entity.position.z) else BLOCKER_LAYER)
			mesh.set_instance_shader_parameter("frozen", float(frozen))
		"TINT":
			mesh.set_instance_shader_parameter("dye", value)
