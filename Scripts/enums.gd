extends Node # NEVER FUCKING REMOVE THIS, I SWEAR TO GOD

enum Spell{
	AQUA,
	AER,
	IGNIS,
	TERRA,
	LUX,
	TENEBRAE,
	CORPUS,
	ARCANUM,
	INVALID # REMEMBER TO FILTER THIS WHEN RANDOMIZING VALUES
}

func string_to_spell(s: String):
	match s:
		"Aqua": return Spell.AQUA
		"Aer": return Spell.AER
		"Ignis": return Spell.IGNIS
		"Terra": return Spell.TERRA
		"Lux": return Spell.LUX
		"Tenebrae": return Spell.TENEBRAE
		"Corpus": return Spell.CORPUS
		"Arcanum": return Spell.ARCANUM
		_: return Spell.INVALID

func spell_to_string(spell: Spell):
	match spell:
		Spell.AQUA: return "Aqua"
		Spell.AER: return "Aer"
		Spell.IGNIS: return "Ignis"
		Spell.TERRA: return "Terra"
		Spell.LUX: return "Lux"
		Spell.TENEBRAE: return "Tenebrae"
		Spell.CORPUS: return "Corpus"
		Spell.ARCANUM: return "Arcanum"
		_: return ""
		
func spell_to_key(spell: Spell):
	var press_str = "Press "
	match spell: 
		Spell.AQUA: press_str+= "Q"
		Spell.AER: press_str+= "W"
		Spell.IGNIS: press_str+= "E"
		Spell.TERRA: press_str+= "R"
		Spell.LUX: press_str+= "A"
		Spell.TENEBRAE: press_str+= "S"
		Spell.CORPUS: press_str+= "D"
		Spell.ARCANUM: press_str+= "F"
		_: press_str+= "invalid"
	return press_str
