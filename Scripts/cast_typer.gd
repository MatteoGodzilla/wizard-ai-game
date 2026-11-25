class_name CastTyper
extends Node
## Tracks a recipe one key press at a time. A wrong element removes one completed step.
## A positive timer enables a deadline for the separate controls test scene.

signal on_successful_cast
signal on_failed_cast
signal setup_graphics(elements: Array[Enums.Element], timer: float)
signal update_graphics(correct_amount: int)

@export var element_input: ElementInput

var elapsed_time := 0.0
var mistakes := 0
var _is_challenge_active := false
var _remaining_time := 0.0
var _has_deadline := false
var _required_elements: Array[Enums.Element] = []
var _next_spell_index := 0


func _ready() -> void:
	set_process(false)
	if element_input != null:
		element_input.element_typed.connect(_on_element_typed)


func start_casting_challenge(elements: Array[Enums.Element], timer: float = 0.0) -> void:
	if elements.is_empty():
		return
	_required_elements = elements.duplicate()
	_remaining_time = timer
	_has_deadline = timer > 0.0
	_next_spell_index = 0
	elapsed_time = 0.0
	mistakes = 0
	_is_challenge_active = true
	set_process(true)
	setup_graphics.emit(elements, timer)
	update_graphics.emit(0)


func is_casting() -> bool:
	return _is_challenge_active


func cancel_cast() -> void:
	_is_challenge_active = false
	set_process(false)


func _process(delta: float) -> void:
	elapsed_time += delta
	if _has_deadline:
		_remaining_time -= delta
		if _remaining_time <= 0.0:
			cancel_cast()
			on_failed_cast.emit()


func _on_element_typed(typed_spell: Enums.Element) -> void:
	if not _is_challenge_active:
		return
	var should_pluck = false
	if typed_spell == _required_elements[_next_spell_index]:
		_next_spell_index += 1
		should_pluck = true
	else:
		mistakes += 1
		_next_spell_index = maxi(0, _next_spell_index - 1)
	update_graphics.emit(_next_spell_index)
	if _next_spell_index == _required_elements.size():
		cancel_cast()
		on_successful_cast.emit()
		Audio.trigger_sfx("correct")
	elif should_pluck:
		Audio.trigger_sfx("pluck",_next_spell_index)
