class_name CastTyper
extends Node

# Public API
signal on_successful_cast
signal on_failed_cast
signal setup_graphics(elements: Array[Enums.Spell], timer: float)
signal update_graphics(correct_amount: int)

func start_casting_challenge(elements: Array[Enums.Spell], timer: float):
	_is_challenge_active = true
	_remaining_time = timer
	_current_spell_list = elements
	_idx_to_type = 0
	setup_graphics.emit(elements, timer)

# "Private" Implementation
var _is_challenge_active = false
var _remaining_time: float
var _current_spell_list : Array[Enums.Spell]
var _idx_to_type = 0

func _check_typed_spell(typed: Enums.Spell):
	var to_type : Enums.Spell = _current_spell_list[_idx_to_type]
	if to_type == typed:
		_idx_to_type += 1
		if _idx_to_type == _current_spell_list.size():
			_is_challenge_active = false
			on_successful_cast.emit()
			print("Success")
	else:
		_idx_to_type = max(0, _idx_to_type - 1)
	update_graphics.emit(_idx_to_type)

func _input(event: InputEvent) -> void:
	var typed_by_player : Enums.Spell
	# There has to be a better way for this
	if Input.is_action_just_pressed("Acqua"):
		_check_typed_spell(Enums.Spell.ACQUA)
	elif Input.is_action_just_pressed("Aer"):
		_check_typed_spell(Enums.Spell.AER)
	elif Input.is_action_just_pressed("Ignis"):
		_check_typed_spell(Enums.Spell.IGNIS)
	elif Input.is_action_just_pressed("Terra"):
		_check_typed_spell(Enums.Spell.TERRA)
	elif Input.is_action_just_pressed("Lux"):
		_check_typed_spell(Enums.Spell.LUX)
	elif Input.is_action_just_pressed("Tenebrae"):
		_check_typed_spell(Enums.Spell.TENEBRAE)
	elif Input.is_action_just_pressed("Corpus"):
		_check_typed_spell(Enums.Spell.CORPUS)
	elif Input.is_action_just_pressed("Arcanum"):
		_check_typed_spell(Enums.Spell.ARCANUM)

func _process(delta: float) -> void:
	_remaining_time -= delta
	if _remaining_time < 0 && _is_challenge_active:
		_is_challenge_active = false
		on_failed_cast.emit()
		print("Failiure")
