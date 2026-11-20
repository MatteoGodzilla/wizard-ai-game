extends RefCounted

const Intent = preload("res://spellcheck/spell_intent.gd")
const Rules = preload("res://spellcheck/magic_rules.gd")
const CASTER_TRAIL_WORDS := "(?:after[ -]?images?|ghost[ -]trails?|motion echoes|(?:cop(?:y|ies)|echo(?:es)?|silhouettes?) of (?:me|myself|(?:the )?(?:caster|wizard)))"

const IMPACT_REPAIR_BRIEF := """
Compile one traveling spell from the original request. Use the previous interpretation as a hint about what flies and what it does on impact. The spell's motion is determined by its form and path. Rules change gameplay, so leave out unrelated buffs, time changes, and world edits.
Use BOLT for a narrow, fast thrown shape such as a dart or cutting projectile, ORB for a round shot, WAVE for a spreading front, BEAM for a ray, and ARC for lightning.
Use BUILT_IN when the spell only needs ordinary impact behavior. BREAK damages destructible targets. IGNITE burns flammable targets. ERASE pierces and removes targets when erasure is requested. BURST is a visual impact. Use power 1 for ordinary damage, 2 for a strong impact, and 3 for overwhelming damage. Use charge 0 and a STRAIGHT path unless the request calls for different timing or motion. Use beam {} for nonbeams and emitters [] when extra particles are unnecessary.
Example for a silver cutting projectile: {"status":"BUILT_IN","reference":"","meaning":"Throws a white blade that damages targets on impact.","form":"BOLT","palette":"WHITE","particle":"SPARKS","effect":"BREAK","power":2,"charge":0,"path":"STRAIGHT","beam":{},"emitters":[]}
Use COMPOSED only when the request needs custom gameplay rules. A rule that changes the impact target uses event HIT and scope HIT. Emitters at the impact use phase HIT and anchor TARGET. Return one JSON object matching the schema.
"""

const BRIEF := """
Design ONE playable spell from the player data. Interpret a description as the requested behavior, even if it describes a fictional device or a technique from another genre. For a reference, infer the signature mechanics and visuals, then map each to available options. Approximate recognizable unsupported ideas and describe what will actually happen. Return UNINTELLIGIBLE only for gibberish, unrelated input, or a bare name with no inferable meaning. Put the source franchise in reference if recognized, otherwise "". Keep meaning short.

Choose status BUILT_IN when form, appearance and the standard impacts suffice. This includes purely visual spells and ordinary projectiles. Choose COMPOSED only when custom state changes, targeting or timing rules are needed. Choose UNINTELLIGIBLE for gibberish. In meaning list the intended behaviors and targets before selecting rules. Only output rules that serve those behaviors. Examples show syntax; their effects are specific to their own requests.

FORM: ORB round projectile; BOLT narrow dart; BEAM sustained ray; ARC branching lightning; WAVE traveling shockwave; WARD visual guardian or protective aura (no damage); DOMAIN sphere that follows caster and tracks members; RITUAL direct changes (no shot or field). Keep the shape the player explicitly names. Approximate summoned protective creatures with a BUILT_IN WARD. Use RITUAL for direct rules and DOMAIN for an ongoing zone around the caster. Domain radius 1–12 m, duration 0.25–12 s.
IMPACT: NONE no implicit hit effect; BURST visual impact; IGNITE burns wood/grass; BREAK structural damage; ERASE pierces and removes destructible props. Nonempty rules replace ALL implicit hit effects, so include required impacts as HIT rules. Use NONE and power 0 for utility, harmless, or purely cosmetic magic. Prefer ordinary strength unless the input calls for more.
RULES: up to five. Choose the operation first, then property, event, scope, tag, value (0 for DESTROY or EMIT), and duration. CAST is release, HIT is impact, EXPIRE is end; DOMAIN also supports ENTER and LEAVE (scope MEMBER) and INTERVAL (0.25–4 s). HIT scope selects the thing hit. NEARBY selects around the event (set rule radius for an explicit distance), AREA inside the field, ARENA anywhere. "All trees" targets ARENA/TREE; "nearby rocks" targets NEARBY/ROCK. CASTER is the wizard, CAMERA the local view, AIM the pointed location for tree placement. duration 0 is permanent, or until exit for ENTER. Use a duration for temporary effects (default 6 s). Caster and camera timers keep running during world time changes.
Represent each distinct behavior once. For superhuman acceleration depicted as bullet time, use a RITUAL that speeds up the caster (SPEED above 1), slows the arena (TIME_SCALE below 1), and conveys the motion with AFTERIMAGE (RAINBOW for a flashy multicolor trail, or the specified color). Plain self speed changes use only caster SPEED. Full arena time stop uses TIME_SCALE 0. A slow zone uses DOMAIN and ENTER/MEMBER/MOVING MULTIPLY SPEED, because an arena time rule would affect everything outside the zone too.
Example verbs: "make every rock explode" uses CAST/ARENA/ROCK DESTROY NONE; "grow a tree where I point" uses CAST/AIM/ANY SPAWN NONE value TREE. "Flip all trees" uses CAST/ARENA/TREE SET ROTATION 180. "Clear all burned grass" uses CAST/ARENA/GRASS SET SCORCH 0. Edits like these are permanent (duration 0) unless asked to wear off.
For freezing nearby water, use RITUAL and one rule such as {"op":"TRANSFORM","property":"MATERIAL","event":"CAST","scope":"NEARBY","tag":"WATER","value":"ICE","duration":4,"radius":5}. Literal water freezing does not affect the caster or alter the arena clock.
Example for "a cinematic sprint while the room goes into slow motion": {"status":"COMPOSED","reference":"","meaning":"Run fast, slow the arena, and leave colorful motion echoes.","form":"RITUAL","rules":[{"op":"MULTIPLY","property":"SPEED","event":"CAST","scope":"CASTER","tag":"ANY","value":2,"duration":4},{"op":"SET","property":"TIME_SCALE","event":"CAST","scope":"ARENA","tag":"WORLD","value":0.4,"duration":4},{"op":"SET","property":"AFTERIMAGE","event":"CAST","scope":"CASTER","tag":"ANY","value":"RAINBOW","duration":4}],"palette":"CYAN","particle":"NONE","effect":"NONE","power":0,"charge":0,"path":"STRAIGHT","beam":{},"emitters":[]}
Example for "dye every rock green": {"status":"COMPOSED","reference":"","meaning":"All rocks become green on cast.","form":"RITUAL","rules":[{"op":"SET","property":"TINT","event":"CAST","scope":"ARENA","tag":"ROCK","value":"GREEN","duration":0}],"palette":"GREEN","particle":"NONE","effect":"NONE","power":0,"charge":0,"path":"STRAIGHT","beam":{},"emitters":[]}
Example for "a blue bubble around me where moving objects slow down": {"status":"COMPOSED","reference":"","meaning":"A bubble slows objects inside it while the caster moves normally.","form":"DOMAIN","rules":[{"op":"MULTIPLY","property":"SPEED","event":"ENTER","scope":"MEMBER","tag":"MOVING","value":0.4,"duration":0}],"palette":"BLUE","particle":"NONE","effect":"NONE","power":0,"charge":0,"path":"STRAIGHT","beam":{},"emitters":[],"radius":6,"duration":6}
VISUALS: honor explicit colors and shapes. Use charge 0 unless the request or the reference describes a distinct charge-up before release (0–3 s). path defaults to STRAIGHT (ARC defaults to ZIGZAG), amplitude in meters (0–2), frequency in Hz (0.25–5). Set beam to {} for nonbeams. For BEAM use anchor HAND or EYES, lanes 1–4, spacing 0.16–1 m, spread 0–18 degrees between adjacent rays. Ordinary eye rays use BUILT_IN, EYES, lanes 2, spread 0, and IGNITE if they burn targets. For one ray use lanes 1.
EMITTERS: use [] unless special particles are called for, then list up to three. phase controls when, anchor controls where (TARGET is aim at release or impact on hit), direction controls movement, shape controls geometry. Use color SPELL or palette, speed 0.2–12, size 0.025–0.4, count 4–48.
AFTERIMAGE defaults to absent. It draws ghost copies of the moving wizard. Use it for explicit caster trails or as a signature visual of a direct caster speed buff. For the color, flare, or trail of a beam, projectile, or blast, use its palette or emitters. Explosive power and bright colors alone do not imply caster ghosts.
Example for "a blue dart with a sine path and purple flakes floating up on impact": {"status":"BUILT_IN","reference":"","meaning":"A blue sine bolt scatters violet flakes on impact.","form":"BOLT","palette":"BLUE","particle":"NONE","effect":"NONE","power":0,"charge":0,"path":"SINE","beam":{},"emitters":[{"phase":"HIT","anchor":"TARGET","direction":"UP","shape":"FLAKE","color":"VIOLET"}]}
Example for "two green rays from my eyes": {"status":"BUILT_IN","reference":"","meaning":"Two parallel green beams fire from the eyes.","form":"BEAM","palette":"GREEN","particle":"NONE","effect":"NONE","power":0,"charge":0,"path":"STRAIGHT","beam":{"anchor":"EYES","lanes":2,"spread":0},"emitters":[]}
"""


static func prompt(anchors: String) -> String:
	var vocabulary: Array[String] = [
		"Tags: " + ", ".join(Rules.TAGS),
		"Operations: " + ", ".join(Rules.OPERATIONS),
		"Effective numeric bounds: " + _property_bounds(),
		"Materials: " + ", ".join(Rules.MATERIALS),
		"Palettes: " + ", ".join(Intent.PALETTES.keys()),
		"Built-in particles: " + ", ".join(Intent.PARTICLES),
		"Paths: " + ", ".join(Intent.PATHS),
		"Emitter phase: " + ", ".join(Intent.PHASES),
		"Emitter anchor: " + ", ".join(Intent.ANCHORS),
		"Emitter direction: " + ", ".join(Intent.DIRECTIONS),
		"Emitter shape: " + ", ".join(Intent.PARTICLE_SHAPES),
	]
	return BRIEF + "\n".join(Rules.PROPERTY_GUIDE + vocabulary) + "\nPower examples: " + anchors + (
		"\nBefore writing rules, choose the described or inferred form. A direct state change uses RITUAL, "
		+ "a region with effects inside it uses DOMAIN, and a summoned guardian can use a visual WARD. "
		+ "Each chosen rule must implement a distinct requested or inferred mechanic. Ignore example effects that do not apply. "
		+ "The world clock never slows the wizard. For an accelerated caster use their SPEED > 1; a SPEED < 1 makes them slower."
	)


static func _property_bounds() -> String:
	var bounds: Array[String] = []
	for property: String in Rules.LIMITS:
		var span: Vector2 = Rules.LIMITS[property]
		bounds.append("%s %s–%s" % [property, str(span.x), str(span.y)])
	return ", ".join(bounds)


static func grounded_rules(intent: Dictionary, request: String) -> Array:
	var rules: Array = intent.get("rules", [])
	if not rules.any(_is_afterimage):
		return rules
	var requested := RegEx.create_from_string("(?i)\\b" + CASTER_TRAIL_WORDS + "\\b").search(request) != null
	var declined := RegEx.create_from_string(
		"(?i)\\b(?:no|without)\\s+(?:[\\w-]+\\s+){0,2}" + CASTER_TRAIL_WORDS + "\\b"
	).search(request) != null
	if requested and not declined:
		return rules
	if not declined and _is_mobility_ritual(intent, rules):
		return rules.filter(func(rule: Variant) -> bool: return not _is_afterimage(rule) or rule.get("event") == "CAST")
	return rules.filter(func(rule: Variant) -> bool: return not _is_afterimage(rule) or (declined and rule.get("value") == "OFF"))


static func _is_afterimage(rule: Variant) -> bool:
	return rule is Dictionary and rule.get("property") == "AFTERIMAGE"


static func _is_mobility_ritual(intent: Dictionary, rules: Array) -> bool:
	if intent.get("form") != "RITUAL" or intent.get("effect") != "NONE":
		return false
	if not rules.all(func(rule: Variant) -> bool:
		return rule is Dictionary and rule.get("op") not in ["DAMAGE", "DESTROY", "EMIT"] and (
			rule.get("scope") in ["CASTER", "CAMERA"] or rule.get("property") == "TIME_SCALE"
		)
	):
		return false
	return rules.any(func(rule: Dictionary) -> bool:
		if rule.get("property") != "SPEED" or rule.get("scope") != "CASTER" or rule.get("event") != "CAST":
			return false
		var value: Variant = rule.get("value")
		return (value is int or value is float) and (
			(rule.get("op") in ["SET", "MULTIPLY"] and value > 1.0) or (rule.get("op") == "ADD" and value > 0.0)
		)
	)


static func schema(impact_only: bool = false, built_in_only: bool = false) -> Dictionary:
	var palettes := Intent.PALETTES.keys()
	var forms := Rules.HIT_FORMS if impact_only else Intent.FORMS
	var summary := {
		"status": _choice(["BUILT_IN"]),
		"reference": {"type": "string", "maxLength": 60},
		"meaning": {"type": "string", "maxLength": 150},
		"form": _choice(forms),
	}
	var body := {
		"palette": _choice(palettes),
		"particle": _choice(Intent.PARTICLES),
		"effect": _choice(Intent.EFFECTS),
		"power": _number(0, 3, "integer"),
		"charge": _number(0, 3),
		"radius": _number(1, 12),
		"duration": _number(0.25, 12),
		"path": _choice(Intent.PATHS),
		"amplitude": _number(0, 2),
		"frequency": _number(0.25, 5),
		"beam": {"anyOf": [_object({
			"anchor": _choice(Intent.BEAM_ANCHORS),
			"lanes": _number(1, 4, "integer"),
			"spacing": _number(0.16, 1),
			"spread": _number(0, 18),
		}, ["anchor", "lanes"]), _object({}, [])]},
		"emitters": {
			"type": "array", "maxItems": Intent.MAX_EMITTERS,
			"items": _object({
				"phase": _choice(Intent.PHASES), "anchor": _choice(Intent.ANCHORS),
				"direction": _choice(Intent.DIRECTIONS), "shape": _choice(Intent.PARTICLE_SHAPES),
				"color": _choice(palettes + ["SPELL"]), "speed": _number(0.2, 12),
				"size": _number(0.025, 0.4), "count": _number(4, 48, "integer"),
			}, ["phase", "anchor", "direction", "shape", "color"]),
		},
	}
	var core := ["palette", "particle", "effect", "power", "charge", "path", "beam", "emitters"]
	var choices := [
		_object(summary.merged(body).merged({
			"form": _choice(forms.filter(func(form: String) -> bool: return form != "RITUAL")),
		}, true), summary.keys() + core),
	]
	if not built_in_only:
		var composed := summary.merged({
			"status": _choice(["COMPOSED"]),
			"rules": {
				"type": "array", "minItems": 1, "maxItems": Rules.MAX_RULES,
				"items": _rule_schema(palettes, impact_only),
			},
		}, true)
		choices.append(_object(composed.merged(body), composed.keys() + core))
	choices.append(_object({"status": _choice(["UNINTELLIGIBLE"])}, ["status"]))
	return {"anyOf": choices}


static func _rule_schema(palettes: Array, impact_only: bool) -> Dictionary:
	var arithmetic := _choice(["SET", "ADD", "MULTIPLY"])
	var common := {
		"op": arithmetic,
		"property": _choice(["ROTATION", "SCALE", "SPEED", "SCORCH", "TEMPERATURE", "BURNING", "WET", "INTEGRITY"]),
		"event": _choice(Rules.EVENTS),
		"scope": _choice(Rules.SCOPES.filter(func(scope: String) -> bool: return scope != "CAMERA")),
		"tag": _choice(Rules.TAGS.filter(func(tag: String) -> bool: return tag not in Rules.WATER_MATERIALS and tag != "WORLD")),
		"value": _number(-360, 360),
		"duration": _number(0, 12),
	}
	var spatial := {"radius": _number(0, 12), "interval": _number(0.25, 4)}
	var variants := [
		spatial,
		spatial.merged({"op": _choice(["DESTROY", "EMIT"]), "property": _choice(["NONE"]), "value": _number(0, 0)}),
		{
			"op": _choice(["SPAWN"]), "property": _choice(["NONE"]),
			"event": _choice(["CAST", "HIT"]), "scope": _choice(["AIM", "CASTER", "HIT"]),
			"tag": _choice(["ANY"]), "value": _choice(Rules.SPAWN_TYPES), "count": _number(1, 5, "integer"),
		},
		spatial.merged({
			"op": _choice(["TRANSFORM"]), "property": _choice(["MATERIAL"]), "tag": _choice(Rules.TAGS),
			"scope": _choice(["HIT", "MEMBER", "NEARBY", "AREA", "ARENA"]), "value": _choice(Rules.MATERIALS),
		}),
		spatial.merged({"op": _choice(["STATUS"]), "property": _choice(["BURNING", "WET"]), "value": _number(0, 1)}),
		spatial.merged({
			"op": _choice(["DAMAGE"]), "property": _choice(["INTEGRITY"]),
			"scope": _choice(["HIT", "MEMBER", "NEARBY", "AREA", "ARENA"]), "value": _bounds("INTEGRITY"),
		}),
		spatial.merged({
			"op": _choice(["SET"]), "property": _choice(["TINT"]),
			"tag": _choice(Rules.TAGS), "value": _choice(palettes + ["SPELL"]),
		}),
		{
			"op": _choice(["SET"]), "property": _choice(["TIME_SCALE"]), "event": _choice(["CAST"]),
			"scope": _choice(["ARENA"]), "tag": _choice(["WORLD"]),
			"value": _bounds("TIME_SCALE"), "duration": _number(1, 12),
		},
		{
			"property": _choice(["HOVER"]), "scope": _choice(["CASTER"]), "tag": _choice(["ANY"]),
			"value": _number(-2.8, 2.8),
		},
		{
			"op": _choice(["SET"]), "property": _choice(["AFTERIMAGE"]), "scope": _choice(["CASTER"]),
			"tag": _choice(["ANY"]), "value": _choice(palettes + Rules.TRAIL_STYLES),
		},
		{
			"property": _choice(["SCREEN_SATURATION"]), "scope": _choice(["CAMERA"]),
			"tag": _choice(["ANY"]), "value": _number(-2, 2),
		},
	]
	var choices: Array[Dictionary] = []
	for variant: Dictionary in variants:
		var properties := common.merged(variant, true)
		if impact_only:
			properties["event"] = _choice(properties["event"]["enum"].filter(func(event: String) -> bool: return event not in Rules.DOMAIN_EVENTS))
			properties["scope"] = _choice(properties["scope"]["enum"].filter(func(scope: String) -> bool: return scope not in ["AREA", "MEMBER"]))
		choices.append(_object(properties, common.keys()))
	return {"anyOf": choices}


static func _bounds(property: String) -> Dictionary:
	var span: Vector2 = Rules.LIMITS[property]
	return _number(span.x, span.y)


static func _object(properties: Dictionary, required: Array) -> Dictionary:
	return {"type": "object", "properties": properties, "required": required, "additionalProperties": false}


static func _choice(options: Array) -> Dictionary:
	return {"type": "string", "enum": options}


static func _number(low: float, high: float, type: String = "number") -> Dictionary:
	return {"type": type, "minimum": low, "maximum": high}
