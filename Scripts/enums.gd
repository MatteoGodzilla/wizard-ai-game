extends Node # NEVER FUCKING REMOVE THIS, I SWEAR TO GOD

enum Element{
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

var valid_elements: Array[Element] = [
	Element.AQUA,
	Element.AER,
	Element.IGNIS,
	Element.TERRA,
	Element.LUX,
	Element.TENEBRAE,
	Element.CORPUS,
	Element.ARCANUM
]


func string_to_spell(s: String):
	match s:
		"Aqua": return Element.AQUA
		"Aer": return Element.AER
		"Ignis": return Element.IGNIS
		"Terra": return Element.TERRA
		"Lux": return Element.LUX
		"Tenebrae": return Element.TENEBRAE
		"Corpus": return Element.CORPUS
		"Arcanum": return Element.ARCANUM
		_: return Element.INVALID

func spell_to_string(spell: Element):
	match spell:
		Element.AQUA: return "Aqua"
		Element.AER: return "Aer"
		Element.IGNIS: return "Ignis"
		Element.TERRA: return "Terra"
		Element.LUX: return "Lux"
		Element.TENEBRAE: return "Tenebrae"
		Element.CORPUS: return "Corpus"
		Element.ARCANUM: return "Arcanum"
		_: return ""
