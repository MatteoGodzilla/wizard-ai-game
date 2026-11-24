class_name CastTyperTest
extends Node

# For testing the history of spells
signal spell_generated(spell_list: Array[Enums.Element])

@export var typer: CastTyper

func _ready() -> void:
	print(Enums.spell_to_string(Enums.Element.AQUA))
	assert(Enums.string_to_spell(Enums.spell_to_string(Enums.Element.AQUA)) == Enums.Element.AQUA)
	Audio.next_bgm()
	pass

func _input(event: InputEvent) -> void:
	# Only react to the actual key press, not to every input event while it is held (otherwise a lot of spells generated)
	if event.is_action_pressed("StartCasting") and not event.is_echo():
		randomize()
		var amount = randi_range(6, 10)
		var spell_list : Array[Enums.Element] = []
		for i in amount:
			var spell = Enums.valid_elements.pick_random()
			spell_list.append(spell)
		typer.start_casting_challenge(spell_list, 10)
		
		# history testing
		spell_generated.emit(spell_list)
