extends Node

@export var typer: CastTyper

func _ready() -> void:
	print(Enums.spell_to_string(Enums.Element.AQUA))
	assert(Enums.string_to_spell(Enums.spell_to_string(Enums.Element.AQUA)) == Enums.Element.AQUA)
	Audio.next_bgm()
	pass

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("StartCasting"):
		randomize()
		var amount = randi_range(6, 10)
		var spell_list : Array[Enums.Element] = []
		for i in amount:
			var spell = Enums.valid_elements.pick_random()
			spell_list.append(spell)
		typer.start_casting_challenge(spell_list, 10)
