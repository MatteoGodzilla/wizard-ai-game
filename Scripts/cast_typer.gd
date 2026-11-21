class_name CastTyper
extends Node

# Public API
signal on_successful_cast
signal on_failed_cast
signal setup_graphics(elements: Array[Enums.Element], timer: float)
signal update_graphics(correct_amount: int)

@export var element_input : ElementInput

# "Private" Implementation
var _is_challenge_active := false:
	set(value):
		_is_challenge_active = value
		set_process(value)
var _remaining_time : float
var _required_elements : Array[Enums.Element]
var _next_spell_index := 0

func _ready() -> void:
	set_process(false)
	element_input.element_typed.connect(_on_element_typed)

func start_casting_challenge(elements: Array[Enums.Element], timer: float) -> void:
	assert(not elements.is_empty(), "A casting challenge needs at least one spell")
	_required_elements = elements
	_remaining_time = timer
	_next_spell_index = 0
	_is_challenge_active = true
	setup_graphics.emit(elements, timer)

func _process(delta: float) -> void:
	_remaining_time -= delta
	if _remaining_time < 0.0:
		_is_challenge_active = false
		on_failed_cast.emit()

func _on_element_typed(typed_spell: Enums.Element) -> void:
	if not _is_challenge_active:
		return
	if typed_spell == _required_elements[_next_spell_index]:
		_next_spell_index += 1
	else:
		_next_spell_index = maxi(0, _next_spell_index - 1)
	update_graphics.emit(_next_spell_index)
	if _next_spell_index == _required_elements.size():
		_is_challenge_active = false
		on_successful_cast.emit()
