extends Node

signal property_changed(entity: Node3D, property: String, value: Variant)
signal destroyed(entity: Node3D)
signal burst(position: Vector3, color: Color)
signal spawn_requested(archetype: String, position: Vector3, count: int)

const EVENTS := ["CAST", "HIT", "ENTER", "LEAVE", "INTERVAL", "EXPIRE"]
const SCOPES := ["CASTER", "HIT", "MEMBER", "NEARBY", "AREA", "ARENA", "AIM", "CAMERA"]
const TAGS := ["ANY", "TREE", "ROCK", "TIMBER", "WOOD", "STONE", "GRASS", "PROJECTILE", "FIRE_PROJECTILE", "MOVING", "SCORCHED", "BURNING", "WORLD", "WATER", "ICE"]
const OPERATIONS := ["SET", "ADD", "MULTIPLY", "TRANSFORM", "DAMAGE", "DESTROY", "STATUS", "EMIT", "SPAWN"]
const PROPERTIES := ["NONE", "TINT", "ROTATION", "SCALE", "SPEED", "TEMPERATURE", "SCORCH", "BURNING", "MATERIAL", "INTEGRITY", "HOVER", "TIME_SCALE", "SCREEN_SATURATION", "AFTERIMAGE", "WET"]
const LIMITS := {
	"ROTATION": Vector2(-360, 360), "SCALE": Vector2(0.2, 3),
	"SPEED": Vector2(0, 3), "TEMPERATURE": Vector2(0, 100),
	"SCORCH": Vector2(0, 1), "BURNING": Vector2(0, 1), "INTEGRITY": Vector2(0, 10),
	"HOVER": Vector2(0, 2.8), "TIME_SCALE": Vector2(0, 2),
	"SCREEN_SATURATION": Vector2(0, 2), "WET": Vector2(0, 1),
}
const MATERIALS := ["WOOD", "STONE", "GRASS", "CHARRED", "WATER", "ICE"]
const WATER_MATERIALS := ["WATER", "ICE"]
const SPAWN_TYPES := ["TREE"]
const TRAIL_STYLES := ["OFF", "RAINBOW", "SPELL"]
const MAX_RULES := 5
const MAX_TEMPORARY_VALUES := 16
const PROPERTY_GUIDE := [
	"TINT SET a palette or SPELL on props, grass, projectiles or water. ROTATION degrees (180 flips props); SCALE body size; SPEED movement multiplier (0 still, 1 normal).",
	"HOVER on CASTER lifts feet in meters and crosses water. TIME_SCALE requires CAST/ARENA/WORLD/SET for 1–12s; 0 stops simulation, 1 normal, changes neither caster movement nor camera.",
	"SCREEN_SATURATION on CAMERA/ANY: 0 grayscale, 1 normal, 2 vivid. AFTERIMAGE uses CASTER/ANY/SET: RAINBOW multicolor, SPELL spell color, named palette, or OFF.",
	"STATUS BURNING 1 ignites wood/grass, 0 extinguishes. STATUS WET 1 extinguishes and prevents fire while wet. SCORCH 1 scorches grass, 0 clears. TEMPERATURE >=60 ignites fuel.",
	"TRANSFORM MATERIAL on terrain WATER/ICE: WATER selects river cells including frozen ones, ICE selects only frozen cells. Select NEARBY, AREA, ARENA or MEMBER. TRANSFORM prop or grass materials only among dry materials.",
	"DAMAGE INTEGRITY (0–10) on destructible props. DESTROY NONE removes destructible targets and emits a burst. EMIT NONE is cosmetic. SPAWN NONE value TREE/count 1–5 uses CAST/AIM (cursor) or CASTER, or HIT/HIT.",
]

var entities: Dictionary = {}
var caster: Node3D
var camera: Camera3D
var _temporary: Dictionary = {}
var _clock := 0.0
var _world_clock := 0.0


static func compile_rule(raw: Variant, form: String, palettes: Dictionary, spell_color: Color) -> Dictionary:
	if not raw is Dictionary:
		return {"error": "A magic rule must be an object."}
	for field: String in raw:
		if field not in ["event", "scope", "tag", "op", "property", "value", "duration", "radius", "interval", "count"]:
			return {"error": "Unknown magic rule field: " + field}
	var event: Variant = raw.get("event")
	var scope: Variant = raw.get("scope")
	var tag: Variant = raw.get("tag")
	var op: Variant = raw.get("op")
	var property: Variant = raw.get("property")
	if event not in EVENTS or scope not in SCOPES or tag not in TAGS or op not in OPERATIONS or property not in PROPERTIES:
		return {"error": "Unknown magic rule event, target, operation, or property."}
	if (scope == "HIT" and event != "HIT") or (scope == "MEMBER" and event not in ["ENTER", "LEAVE"]):
		return {"error": "That event does not provide the selected target."}
	if event in ["ENTER", "LEAVE"] and scope != "MEMBER":
		return {"error": "Entry and exit rules need the member that crossed the boundary."}
	if event in ["ENTER", "LEAVE", "INTERVAL"] and form != "DOMAIN":
		return {"error": "Membership and interval rules require a domain."}
	if scope == "AREA" and form != "DOMAIN":
		return {"error": "AREA selects targets inside a DOMAIN. Use NEARBY for a radius around the cast or impact."}
	if event == "HIT" and form in ["RITUAL", "WARD", "DOMAIN"]:
		return {"error": "That form does not hit. Use CAST for direct effects, or use a traveling form for impacts."}
	if scope == "AIM" and (op != "SPAWN" or event != "CAST"):
		return {"error": "Aim-point placement needs a cast-time spawn rule."}
	if property == "TIME_SCALE" and (event != "CAST" or scope != "ARENA" or tag != "WORLD" or op != "SET"):
		return {"error": "World time needs a cast-time rule targeting the whole arena clock."}
	if property in ["HOVER", "AFTERIMAGE"] and (scope != "CASTER" or tag != "ANY"):
		return {"error": "Hover and afterimages must target the caster with tag ANY."}
	if (property == "SCREEN_SATURATION" or scope == "CAMERA") and (scope != "CAMERA" or property != "SCREEN_SATURATION" or op not in ["SET", "ADD", "MULTIPLY"]):
		return {"error": "Screen saturation belongs to the camera."}
	if scope == "CAMERA" and tag != "ANY":
		return {"error": "Camera rules must select tag ANY."}
	if property in ["WET", "BURNING", "SCORCH", "MATERIAL", "INTEGRITY", "TEMPERATURE", "ROTATION"] and scope == "CASTER":
		return {"error": "%s is a terrain or prop property. Use CASTER only with a caster property." % property}
	if tag in WATER_MATERIALS and property not in ["TINT", "MATERIAL", "NONE"]:
		return {"error": "River cells expose MATERIAL and TINT. To freeze water, TRANSFORM MATERIAL into ICE."}
	if property == "SCORCH" and tag not in ["GRASS", "SCORCHED", "ANY"]:
		return {"error": "SCORCH affects grass. To explode destructible props use DESTROY with property NONE."}
	if op not in ["DESTROY", "EMIT"] and not raw.has("value"):
		return {"error": "%s requires a value." % op}
	var value: Variant = raw.get("value", 0)
	match op:
		"DESTROY", "EMIT":
			# These actions operate on the selected entity itself.
			property = "NONE"
		"SPAWN":
			if value not in SPAWN_TYPES or scope not in ["AIM", "CASTER", "HIT"]:
				return {"error": "Spawn needs a supported prop and a placement target."}
			property = "NONE"
		"TRANSFORM":
			if property != "MATERIAL" or value not in MATERIALS:
				return {"error": "Transform needs a supported material."}
			if value in WATER_MATERIALS and (tag not in WATER_MATERIALS or scope not in ["NEARBY", "AREA", "ARENA", "MEMBER"]):
				return {"error": "Water and ice transformations need a river-cell selector."}
			if tag in WATER_MATERIALS and value not in WATER_MATERIALS:
				return {"error": "River cells can transform between water and ice."}
		"STATUS":
			if property not in ["BURNING", "WET"] or not number_in(value, 0.0, 1.0):
				return {"error": "Burning and wetness need a value between zero and one."}
		"DAMAGE":
			if property != "INTEGRITY" or not number_in(value, 0.0, 10.0):
				return {"error": "Damage needs a bounded integrity amount."}
		"SET", "ADD", "MULTIPLY":
			if property == "TINT":
				if op != "SET" or (value != "SPELL" and not palettes.has(value)):
					return {"error": "Tint needs a palette color."}
				value = palettes.get(value, spell_color)
			elif property == "AFTERIMAGE":
				if scope != "CASTER" or op != "SET" or (value not in TRAIL_STYLES and not palettes.has(value)):
					return {"error": "Afterimages need a caster trail style."}
				if value == "SPELL" or palettes.has(value):
					var tint: Color = palettes.get(value, spell_color)
					value = "#" + tint.to_html(false)
			elif not LIMITS.has(property) or not number_in(value, -360.0, 360.0):
				return {"error": "That operation needs a supported numeric property."}
	var duration: Variant = raw.get("duration", 0.0)
	var radius: Variant = raw.get("radius", 0.0)
	var interval: Variant = raw.get("interval", 1.0)
	var count: Variant = raw.get("count", 1.0)
	if not number_in(duration, 0, 12) or not number_in(radius, 0, 12) or not number_in(interval, 0.25, 4):
		return {"error": "Rule duration, radius, or interval is outside the supported bounds."}
	if property == "TIME_SCALE" and duration < 1.0:
		return {"error": "World time spells need a duration of at least one second."}
	if property == "TIME_SCALE" and not number_in(value, LIMITS["TIME_SCALE"].x, LIMITS["TIME_SCALE"].y):
		return {"error": "TIME_SCALE must be in 0–2. Use 0 to stop time, a fraction below 1 to slow it, or a number above 1 to speed it up."}
	if not number_in(count, 1, 5) or float(count) != floorf(float(count)):
		return {"error": "Spawn count must be a whole number between one and five."}
	return {
		"event": event, "scope": scope, "tag": tag, "op": op, "property": property,
		"value": value, "duration": float(duration), "radius": float(radius), "interval": float(interval),
		"count": int(count),
	}


static func number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= minimum and value <= maximum


func register(node: Node3D, tags: Array, properties: Dictionary, destructible: bool = false) -> void:
	entities[node] = {
		"tags": tags, "base": properties.duplicate(), "effective": properties.duplicate(),
		"destructible": destructible,
	}
	node.tree_exiting.connect(forget.bind(node), CONNECT_ONE_SHOT)


func forget(node: Node3D) -> void:
	_temporary.erase(node)
	entities.erase(node)


func value(node: Node3D, property: String, default: Variant = 0.0) -> Variant:
	if not entities.has(node):
		return default
	return entities[node]["effective"].get(property, default)


func set_base(node: Node3D, property: String, next: Variant) -> void:
	if not entities.has(node) or not entities[node]["base"].has(property):
		return
	if property == "BURNING" and float(next) > 0.0 and float(value(node, "WET")) >= 0.5:
		return
	if LIMITS.has(property):
		var bounds: Vector2 = LIMITS[property]
		next = clampf(float(next), bounds.x, bounds.y)
	entities[node]["base"][property] = next
	_recompute(node, property)


func matching(tag: String, origin: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node3D in entities:
		if _matches(node, tag) and node.global_position.distance_squared_to(origin) <= radius * radius:
			found.append(node)
	return found


func dispatch(spell: Dictionary, event: String, context: Dictionary, only_rule: int = -1) -> void:
	var rules: Array = spell["rules"]
	for index in range(rules.size()):
		var rule: Dictionary = rules[index]
		if rule["event"] != event or (only_rule >= 0 and index != only_rule):
			continue
		if rule["op"] == "SPAWN":
			var point: Vector3 = context.get("aim", context["origin"]) if rule["scope"] == "AIM" else context["origin"]
			if rule["scope"] == "CASTER":
				point = caster.global_position
			spawn_requested.emit(rule["value"], point, rule["count"])
			continue
		for target: Node3D in _select(rule, context):
			if entities.has(target) and _matches(target, rule["tag"]):
				_apply(target, rule, context, index, spell["color"])
		if rule["op"] == "EMIT" and rule["scope"] == "HIT" and context.get("hit") == null:
			burst.emit(context["origin"], spell["color"])


func remove_membership(node: Node3D, source: int) -> void:
	_remove_matching(node, "%d/member/" % source)


func advance(delta: float, world_delta: float) -> void:
	_clock += delta
	_world_clock += world_delta
	for node: Node3D in _temporary.keys():
		_remove_matching(node, "")


func _select(rule: Dictionary, context: Dictionary) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var target: Node3D
	match rule["scope"]:
		"CASTER":
			target = caster
		"CAMERA":
			target = camera
		"HIT":
			target = context.get("hit")
		"MEMBER":
			target = context.get("member")
		"ARENA":
			result.assign(entities.keys())
		"NEARBY", "AREA":
			var radius: float = rule["radius"]
			if radius == 0.0:
				radius = context.get("radius", 6.0)
			if rule["scope"] == "AREA":
				radius = minf(radius, context.get("radius", radius))
			return matching(rule["tag"], context["origin"], radius)
	if is_instance_valid(target):
		result.append(target)
	return result


func _matches(node: Node3D, tag: String) -> bool:
	if tag == "ANY":
		return true
	if tag == "SCORCHED":
		return float(value(node, "SCORCH")) > 0.05
	if tag == "BURNING":
		return float(value(node, "BURNING")) >= 0.5
	if tag == "ICE":
		return value(node, "MATERIAL", "") == "ICE"
	if tag in ["WOOD", "STONE"]:
		return value(node, "MATERIAL", "") == tag
	return tag in entities[node]["tags"]


func _apply(node: Node3D, rule: Dictionary, context: Dictionary, index: int, color: Color) -> void:
	var op: String = rule["op"]
	var property: String = rule["property"]
	var change: Variant = rule["value"]
	if op == "DESTROY":
		if entities[node]["destructible"]:
			burst.emit(node.global_position, color)
			destroyed.emit(node)
		return
	if op == "EMIT":
		burst.emit(node.global_position, color)
		return
	if not entities[node]["base"].has(property):
		return
	if property in ["BURNING", "WET"] and value(node, "MATERIAL") not in ["WOOD", "GRASS", "CHARRED"]:
		return
	if property == "BURNING" and float(value(node, "WET")) >= 0.5:
		return
	if property == "MATERIAL" and ((_matches(node, "WATER")) != (change in WATER_MATERIALS)):
		return
	if op == "DAMAGE":
		set_base(node, property, float(value(node, property)) - float(change))
		if float(value(node, property)) <= 0.0 and entities[node]["destructible"]:
			destroyed.emit(node)
		return
	if op in ["TRANSFORM", "STATUS"]:
		op = "SET"
	var duration: float = rule["duration"]
	var membership: bool = rule["event"] == "ENTER"
	if duration <= 0.0 and not membership:
		set_base(node, property, _combine(entities[node]["base"][property], op, change))
		return
	if not _temporary.has(node):
		_temporary[node] = {}
	if not _temporary[node].has(property):
		_temporary[node][property] = {}
	var modifiers: Dictionary = _temporary[node][property]
	var channel := "member" if membership else "timed"
	var key := "%d/%s/%d" % [context["source"], channel, index]
	if not modifiers.has(key) and modifiers.size() >= MAX_TEMPORARY_VALUES:
		modifiers.erase(modifiers.keys()[0])
	var unscaled := node == caster or node == camera or property == "TIME_SCALE"
	var clock := _clock if unscaled else _world_clock
	modifiers[key] = {
		"op": op, "value": change, "unscaled": unscaled, "until": clock + duration if duration > 0.0 else INF,
	}
	_recompute(node, property)


func _remove_matching(node: Node3D, prefix: String) -> void:
	if not _temporary.has(node):
		return
	var properties: Dictionary = _temporary[node]
	for property: String in properties.keys():
		var modifiers: Dictionary = properties.get(property, {})
		var changed := false
		for key: String in modifiers.keys():
			var modifier: Dictionary = modifiers[key]
			var clock := _clock if modifier["unscaled"] else _world_clock
			if (not prefix.is_empty() and key.begins_with(prefix)) or clock >= modifier["until"]:
				modifiers.erase(key)
				changed = true
		if changed:
			_recompute(node, property)
		if modifiers.is_empty():
			properties.erase(property)
	if properties.is_empty():
		_temporary.erase(node)


func _recompute(node: Node3D, property: String) -> void:
	var record: Dictionary = entities[node]
	var effective: Variant = record["base"][property]
	var modifiers: Dictionary = _temporary.get(node, {}).get(property, {})
	for modifier: Dictionary in modifiers.values():
		effective = _combine(effective, modifier["op"], modifier["value"])
	if LIMITS.has(property):
		var bounds: Vector2 = LIMITS[property]
		effective = clampf(float(effective), bounds.x, bounds.y)
	if record["effective"][property] != effective:
		record["effective"][property] = effective
		if property == "WET" and float(effective) >= 0.5:
			if _temporary.has(node):
				_temporary[node].erase("BURNING")
			set_base(node, "BURNING", 0.0)
			set_base(node, "TEMPERATURE", 0.0)
		property_changed.emit(node, property, effective)


static func _combine(previous: Variant, op: String, proposed: Variant) -> Variant:
	match op:
		"ADD":
			return float(previous) + float(proposed)
		"MULTIPLY":
			return float(previous) * float(proposed)
	return proposed
