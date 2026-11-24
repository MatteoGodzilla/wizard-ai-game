extends MultiMeshInstance3D

var _profile: Dictionary
var _direction: Vector3
var _lifetime: float
var _clock := 0.0
var _vectors: Array[Vector3] = []
var _phases: Array[float] = []


func setup(profile: Dictionary, direction: Vector3, lifetime: float) -> void:
	_profile = profile
	_direction = direction
	_lifetime = lifetime
	var view: PrimitiveMesh
	match profile["shape"]:
		"SHARD":
			var shard := BoxMesh.new()
			shard.size = Vector3(0.27, 1.6, 0.27)
			view = shard
		"FLAKE":
			var flake := QuadMesh.new()
			view = flake
		"RING":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.32
			ring.outer_radius = 0.49
			ring.rings = 8
			ring.ring_segments = 6
			view = ring
		_:
			var mote := SphereMesh.new()
			mote.radial_segments = 6
			mote.rings = 4
			view = mote
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = view
	multimesh.instance_count = profile["count"]
	multimesh.custom_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var random := RandomNumberGenerator.new()
	random.seed = get_instance_id()
	for index in range(multimesh.instance_count):
		var v := Vector3(random.randfn(), random.randfn(), random.randfn()).normalized()
		_vectors.append(v * random.randf_range(0.42, 1.0))
		_phases.append(random.randf())
	_process(0.0)


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= _lifetime:
		queue_free()
		return
	var color: Color = _profile["color"]
	var speed: float = _profile["speed"]
	var kind: String = _profile["direction"]
	var one_shot: bool = _profile["phase"] in ["HIT", "CAST", "EXPIRE"]
	for index in range(multimesh.instance_count):
		var age := clampf((_clock - _phases[index] * 0.14) * 1.25, 0.0, 1.0) if one_shot else fposmod(_phases[index] + _clock * (0.38 + speed * 0.16), 1.0)
		var seed := _vectors[index]
		var spread := clampf(speed * 0.42, 0.28, 4.4)
		var point := seed * spread * age
		match kind:
			"INWARD":
				point = seed * spread * (1.0 - age) + Vector3.UP * (1.0 - age) * 0.75
			"UP":
				point = seed * 0.55 + Vector3.UP * spread * age
			"DOWN":
				point = seed * 0.55 - Vector3.UP * spread * age
			"FORWARD":
				point = seed * age * 0.65 + _direction * spread * age
			"SWIRL":
				point = seed.rotated(Vector3.UP, (age + _clock * 0.25) * TAU) * spread * 0.6
				point.y += age * 0.65
		var fade := sin(age * PI) * (1.0 - smoothstep(_lifetime * 0.85, _lifetime, _clock))
		var thickness: float = _profile["size"] * (0.55 + fade)
		var basis := Basis.from_euler(Vector3(age * 3.0, _clock + index * 0.4, age * 4.0)).scaled(Vector3.ONE * thickness)
		multimesh.set_instance_transform(index, Transform3D(basis, point))
		multimesh.set_instance_color(index, Color(color.r, color.g, color.b, color.a * fade))
