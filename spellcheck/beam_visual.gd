extends Node3D

var emitter_anchor: Node3D
var _lanes: Array[Array] = []


func setup(lane_count: int, segment_count: int, tint: Color) -> void:
	var narrow := lane_count > 1
	var core_mesh := _mesh(0.047 if narrow else 0.115)
	var halo_mesh := _mesh(0.112 if narrow else 0.28)
	var core := _material(tint.lerp(Color.WHITE, 0.45), 1.0)
	var halo := _material(tint, 0.38)
	for lane in range(lane_count):
		var segments: Array[Dictionary] = []
		for index in range(segment_count):
			segments.append({"core": _instance(core_mesh, core), "halo": _instance(halo_mesh, halo)})
		_lanes.append(segments)
	emitter_anchor = Node3D.new()
	add_child(emitter_anchor)


func draw_lane(lane: int, points: Array[Vector3]) -> void:
	var segments := _lanes[lane]
	for index in range(segments.size()):
		var pair: Dictionary = segments[index]
		if index + 1 >= points.size():
			pair["core"].hide()
			pair["halo"].hide()
			continue
		var start := points[index]
		var finish := points[index + 1]
		var axis := finish - start
		if axis.length_squared() < 0.000001:
			pair["core"].hide()
			pair["halo"].hide()
			continue
		var orientation := Basis(Quaternion(Vector3.UP, axis.normalized()))
		var transform_in_world := Transform3D(
			orientation * Basis.from_scale(Vector3(1.0, axis.length(), 1.0)), (start + finish) * 0.5
		)
		for segment: MeshInstance3D in pair.values():
			segment.global_transform = transform_in_world
			segment.show()


func _instance(mesh: CylinderMesh, material: StandardMaterial3D) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.mesh = mesh
	segment.material_override = material
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	segment.hide()
	add_child(segment)
	return segment


static func _mesh(radius: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 10
	return mesh


static func _material(tint: Color, opacity: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(tint, opacity)
	if opacity < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
