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
