extends Node

@export var typer: CastTyper

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("StartCasting"):
		randomize()
		var amount = randi_range(6, 10)
		var spell_list : Array[Enums.Spell] = []
		for i in amount:
			var spell = Enums.Spell.values().pick_random()
			spell_list.append(spell)
		typer.start_casting_challenge(spell_list, 10)
