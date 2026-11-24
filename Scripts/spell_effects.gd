extends Node3D
## Plays a short elemental effect when a spell is crafted. The dummy is only decoration.

const COLORS: Array[Color] = [
	Color(0.2, 0.65, 1.0), Color(0.7, 0.9, 1.0), Color(1.0, 0.3, 0.05),
	Color(0.4, 0.65, 0.2), Color(1.0, 0.9, 0.4), Color(0.4, 0.15, 0.7),
	Color(0.95, 0.45, 0.5), Color(0.65, 0.35, 1.0),
]

@onready var _dummy: Node3D = $"../Background/Dummy2"
var _start_transform: Transform3D
var _original_materials: Dictionary = {}
var _hit_tween: Tween
var _projectiles: Array[MeshInstance3D] = []


func _ready() -> void:
	_start_transform = _dummy.transform
	for mesh in _dummy.find_children("*", "MeshInstance3D", true, false):
		_original_materials[mesh] = mesh.material_overlay


func reset_dummy() -> void:
	if _hit_tween != null:
		_hit_tween.kill()
	_dummy.transform = _start_transform
	_restore_materials()
	for projectile in _projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_projectiles.clear()


func play_craft(elements: Array[Enums.Element]) -> void:
	if _hit_tween != null:
		_hit_tween.kill()
	var color := COLORS[elements[0]]
	var overlay := StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.albedo_color = Color(color, 0.5)
	for mesh: MeshInstance3D in _original_materials:
		mesh.material_overlay = overlay
	for index in elements.size():
		_spawn_projectile(COLORS[elements[index]], index)
	_hit_tween = create_tween()
	_hit_tween.tween_interval(0.3)
	_hit_tween.tween_property(_dummy, "rotation:z", _start_transform.basis.get_euler().z + 0.12, 0.1)
	_hit_tween.tween_property(_dummy, "rotation:z", _start_transform.basis.get_euler().z, 0.15)
	_hit_tween.tween_callback(_restore_materials)


func _restore_materials() -> void:
	for mesh: MeshInstance3D in _original_materials:
		if is_instance_valid(mesh):
			mesh.material_overlay = _original_materials[mesh]


func _spawn_projectile(color: Color, index: int) -> void:
	var projectile := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.065
	sphere.height = 0.13
	projectile.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	projectile.material_override = material
	add_child(projectile)
	projectile.global_position = _dummy.global_position + Vector3(2.5, 0.7 + index * 0.08, 2.8)
	_projectiles.append(projectile)
	var tween := projectile.create_tween()
	tween.tween_interval(index * 0.035)
	tween.tween_property(projectile, "global_position", _dummy.global_position + Vector3(0, 1, 0), 0.35)
	tween.tween_callback(projectile.queue_free)
