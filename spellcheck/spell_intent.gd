extends RefCounted

const Rules = preload("res://spellcheck/magic_rules.gd")
const SCHEMA_VERSION := 3
const COMPILER_VERSION := 3
const FORMS := ["ORB", "BOLT", "BEAM", "ARC", "WAVE", "WARD", "DOMAIN", "RITUAL"]
const EFFECTS := ["NONE", "BURST", "IGNITE", "BREAK", "ERASE"]
const PALETTES := {
	"DEFAULT": Color("#f5e5be"),
	"ORANGE": Color("#ff8545"),
	"GREEN": Color("#68ff78"),
	"BLUE": Color("#58baff"),
	"CYAN": Color("#60ffeb"),
	"VIOLET": Color("#b28aff"),
	"RED": Color("#ff5271"),
	"WHITE": Color("#f3f5ff"),
	"YELLOW": Color("#ffe55c"),
	"BLACK": Color("#252333"),
	"PINK": Color("#ff87c7"),
}
const PARTICLES := ["NONE", "SMOKE", "SPARKS", "MAGIC"]
const PHASES := ["CHARGE", "CAST", "TRAVEL", "HIT", "ACTIVE", "EXPIRE"]
const ANCHORS := ["CASTER", "SPELL", "TARGET"]
const DIRECTIONS := ["INWARD", "OUTWARD", "UP", "DOWN", "FORWARD", "SWIRL"]
const PARTICLE_SHAPES := ["MOTE", "SHARD", "FLAKE", "RING"]
const PATHS := ["STRAIGHT", "SINE", "COSINE", "HELIX", "ZIGZAG"]
const MAX_EMITTERS := 3
const EXTRA_FIELDS := ["charge", "rules", "emitters", "path", "amplitude", "frequency", "radius", "duration", "beam"]
const BEAM_ANCHORS := ["HAND", "EYES"]


static func create(form: String, palette: String, particle: String, effect: String, power: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION, "form": form, "palette": palette,
		"particle": particle, "effect": effect, "power": power,
	}


static func compile(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"error": "The intent must be an object."}
	var intent: Dictionary = value
	var version: Variant = intent.get("schema_version")
	if version != 2 and version != SCHEMA_VERSION:
		return {"error": "The spell intent schema is unsupported."}
	for key: String in intent:
		if key not in ["schema_version", "form", "palette", "particle", "effect", "power"] and key not in EXTRA_FIELDS:
			return {"error": "Unknown spell field: " + key}
	for key: String in ["form", "palette", "particle", "effect"]:
		if not intent.get(key) is String:
			return {"error": "Missing or invalid " + key + "."}
	if not FORMS.has(intent["form"]) or not EFFECTS.has(intent["effect"]):
		return {"error": "The spell shape or effect is unsupported."}
	if not PALETTES.has(intent["palette"]) or not PARTICLES.has(intent["particle"]):
		return {"error": "The palette or particle style is unsupported."}
	var raw_power: Variant = intent.get("power")
	if not raw_power is int and not raw_power is float:
		return {"error": "The power tier is invalid."}
	if raw_power not in [0, 1, 2, 3, 0.0, 1.0, 2.0, 3.0]:
		return {"error": "The power tier is outside 0–3."}

	var form: String = intent["form"]
	var effect: String = intent["effect"]
	var power: int = int(raw_power)
	if form == "WARD":
		effect = "NONE"
	if effect in ["NONE", "BURST"]:
		power = 0
	elif effect == "ERASE":
		power = 3
	else:
		power = clampi(power, 1, 3)
	var color: Color = PALETTES[intent["palette"]]
	var charge: Variant = intent.get("charge", 0.0)
	var radius: Variant = intent.get("radius", 6.0)
	var duration: Variant = intent.get("duration", 6.0)
	var amplitude: Variant = intent.get("amplitude", 0.35 if form == "ARC" else 0.65)
	var frequency: Variant = intent.get("frequency", 2.0)
	var path: Variant = intent.get("path", "ZIGZAG" if form == "ARC" else "STRAIGHT")
	if (
		path not in PATHS or not Rules.number_in(charge, 0.0, 3.0)
		or not Rules.number_in(radius, 1.0, 12.0) or not Rules.number_in(duration, 0.25, 12.0)
		or not Rules.number_in(amplitude, 0.0, 2.0) or not Rules.number_in(frequency, 0.25, 5.0)
	):
		return {"error": "The charge, area, duration, or path is outside its supported bounds."}
	var raw_rules: Variant = intent.get("rules", [])
	if not raw_rules is Array or raw_rules.size() > Rules.MAX_RULES:
		return {"error": "A spell may contain at most five rules."}
	if raw_rules.is_empty():
		raw_rules = _legacy_rules(effect, power)
	var compiled_rules: Array[Dictionary] = []
	for rule: Variant in raw_rules:
		var compiled := Rules.compile_rule(rule, form, PALETTES, color)
		if compiled.has("error"):
			return compiled
		compiled_rules.append(compiled)

	var emitters := _compile_emitters(intent.get("emitters", []), color)
	if emitters.has("error"):
		return emitters
	var beam := _compile_beam(intent.get("beam", {}))
	if beam.has("error"):
		return beam
	var profiles: Array = emitters["profiles"]
	if charge > 0.0 and not profiles.any(func(profile: Dictionary) -> bool: return profile["phase"] == "CHARGE"):
		profiles.append({
			"phase": "CHARGE", "anchor": "CASTER", "direction": "INWARD", "shape": "MOTE",
			"color": color, "speed": 4.0, "size": 0.085, "count": 32,
		})
	var piercing := effect == "ERASE" or compiled_rules.any(func(rule: Dictionary) -> bool:
		return rule["event"] == "HIT" and rule["op"] == "DESTROY"
	)
	return {"spell": {
		"form": form,
		"color": color,
		"particle": intent["particle"],
		"effect": effect,
		"power": power,
		"speed": 26.0 if form == "BOLT" else 17.0,
		"radius": 0.48 if piercing else 0.26,
		"lifetime": 2.0,
		"penetration": 7 if piercing else (power if form == "BEAM" else 0),
		"charge": float(charge), "rules": compiled_rules, "emitters": profiles,
		"area_radius": float(radius), "duration": float(duration),
		"path": path, "amplitude": float(amplitude), "frequency": float(frequency), "beam": beam,
	}}


static func _compile_beam(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"error": "Beam geometry must be an object."}
	for key: String in raw:
		if key not in ["lanes", "spacing", "spread", "anchor"]:
			return {"error": "Unknown beam geometry field: " + key}
	var anchor: Variant = raw.get("anchor", "HAND")
	var lanes: Variant = raw.get("lanes", 1)
	var spacing: Variant = raw.get("spacing", 0.26 if anchor == "EYES" else 0.55)
	var spread: Variant = raw.get("spread", 0.0)
	if (
		anchor not in BEAM_ANCHORS or not Rules.number_in(lanes, 1, 4) or float(lanes) != floorf(float(lanes))
		or not Rules.number_in(spacing, 0.16, 1.0) or not Rules.number_in(spread, 0.0, 18.0)
	):
		return {"error": "Beam count, spacing, spread, or anchor is outside its supported bounds."}
	return {"anchor": anchor, "lanes": int(lanes), "spacing": float(spacing), "spread": float(spread)}


static func _legacy_rules(effect: String, power: int) -> Array:
	var rules: Array = []
	if effect in ["BURST", "IGNITE", "BREAK"]:
		rules.append({"event": "HIT", "scope": "HIT", "tag": "ANY", "op": "EMIT", "property": "NONE"})
	match effect:
		"IGNITE":
			rules.append({"event": "HIT", "scope": "HIT", "tag": "WOOD", "op": "STATUS", "property": "BURNING", "value": 1})
			rules.append({"event": "HIT", "scope": "HIT", "tag": "WOOD", "op": "DAMAGE", "property": "INTEGRITY", "value": power})
			rules.append({"event": "HIT", "scope": "NEARBY", "tag": "GRASS", "op": "STATUS", "property": "BURNING", "value": 1, "radius": 1.7})
		"BREAK":
			rules.append({"event": "HIT", "scope": "HIT", "tag": "ANY", "op": "DAMAGE", "property": "INTEGRITY", "value": power})
		"ERASE":
			rules.append({"event": "HIT", "scope": "HIT", "tag": "ANY", "op": "DESTROY", "property": "NONE"})
	return rules


static func _compile_emitters(raw: Variant, color: Color) -> Dictionary:
	if not raw is Array or raw.size() > MAX_EMITTERS:
		return {"error": "A spell may specify at most three particle emitters."}
	var profiles: Array[Dictionary] = []
	for profile: Variant in raw:
		if not profile is Dictionary:
			return {"error": "Each particle emitter must be an object."}
		for key: String in profile:
			if key not in ["phase", "anchor", "direction", "shape", "color", "speed", "size", "count"]:
				return {"error": "Unknown particle field: " + key}
		var phase: Variant = profile.get("phase")
		var anchor: Variant = profile.get("anchor")
		var direction: Variant = profile.get("direction")
		var shape: Variant = profile.get("shape")
		var palette: Variant = profile.get("color", "SPELL")
		var speed: Variant = profile.get("speed", 3.0)
		var size: Variant = profile.get("size", 0.1)
		var count: Variant = profile.get("count", 24)
		if (
			phase not in PHASES or anchor not in ANCHORS or direction not in DIRECTIONS or shape not in PARTICLE_SHAPES
			or (palette != "SPELL" and not PALETTES.has(palette))
			or not Rules.number_in(speed, 0.2, 12.0) or not Rules.number_in(size, 0.025, 0.4)
			or not Rules.number_in(count, 4, 48)
		):
			return {"error": "A particle emitter has an unsupported option or value."}
		profiles.append({
			"phase": phase, "anchor": anchor, "direction": direction, "shape": shape,
			"color": PALETTES.get(palette, color), "speed": float(speed), "size": float(size), "count": int(count),
		})
	return {"profiles": profiles}


static func path_offset(spell: Dictionary, direction: Vector3, time: float) -> Vector3:
	var phase: float = TAU * spell["frequency"] * time
	var side := direction.cross(Vector3.UP).normalized() * float(spell["amplitude"])
	match spell["path"]:
		"SINE":
			return side * sin(phase)
		"COSINE":
			return side * (cos(phase) - 1.0) * 0.5
		"HELIX":
			return side * sin(phase) + Vector3.UP * float(spell["amplitude"]) * (1.0 - cos(phase)) * 0.5
		"ZIGZAG":
			return side * asin(sin(phase)) * (2.0 / PI)
	return Vector3.ZERO


static func beam_lane_offset(beam: Dictionary, lane: int) -> float:
	return float(lane) - (beam["lanes"] - 1.0) * 0.5


static func beam_lane_direction(direction: Vector3, beam: Dictionary, lane: int) -> Vector3:
	return direction.rotated(Vector3.UP, -deg_to_rad(float(beam["spread"]) * beam_lane_offset(beam, lane)))
