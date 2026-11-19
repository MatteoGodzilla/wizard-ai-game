extends Node3D

const SAMPLE_TIME := 0.055
const GHOST_LIFE := 0.46
const MAX_GHOSTS := 8
const RAINBOW := [
	Color("#62ffdc"), Color("#64afff"), Color("#9e83ff"),
	Color("#ff60bc"), Color("#ffc867"), Color("#b7ff75"),
]

var _ghosts: Array[Dictionary] = []
var _time_to_sample := 0.0
var _last_position := Vector3.INF
var _next_color := 0


func advance(delta: float, model: Node3D, style: String) -> void:
	for index in range(_ghosts.size() - 1, -1, -1):
		var ghost := _ghosts[index]
		ghost["age"] += delta
		if ghost["age"] >= GHOST_LIFE:
			ghost["node"].queue_free()
			_ghosts.remove_at(index)
		else:
			var material: StandardMaterial3D = ghost["material"]
			var tint := material.albedo_color
			tint.a = 0.56 * pow(1.0 - ghost["age"] / GHOST_LIFE, 1.3)
			material.albedo_color = tint

	if style == "OFF":
		_time_to_sample = 0.0
		_last_position = Vector3.INF
		return
	var position_now := model.global_position
	if _last_position == Vector3.INF:
		_last_position = position_now
	_time_to_sample -= delta
	if _time_to_sample > 0.0 or position_now.distance_squared_to(_last_position) < 0.055:
		return
	var tint: Color = RAINBOW[_next_color] if style == "RAINBOW" else Color(style)
	_next_color = (_next_color + 1) % RAINBOW.size()
	_snapshot(model, tint)
	_last_position = position_now
	_time_to_sample = SAMPLE_TIME


func _snapshot(model: Node3D, tint: Color) -> void:
	if _ghosts.size() >= MAX_GHOSTS:
		_ghosts.pop_front()["node"].queue_free()
	var ghost := Node3D.new()
	add_child(ghost)
	ghost.global_transform = model.global_transform
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(tint, 0.56)
	for child in model.get_children():
		if child is MeshInstance3D:
			var copy := MeshInstance3D.new()
			copy.mesh = child.mesh
			copy.transform = child.transform
			copy.material_override = material
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.add_child(copy)
	_ghosts.append({"node": ghost, "material": material, "age": 0.0})
