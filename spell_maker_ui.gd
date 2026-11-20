extends Control

@onready var spell_promt: Label = $VBoxContainer/SpellPromt
@onready var spell_text_input: LineEdit = $VBoxContainer/SpellTextInput

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spell_text_input.text_submitted.connect(_on_LineEdit_text_entered)

func _on_LineEdit_text_entered(new_text: String) -> void: 
	spell_promt.text = "Cooking..."
	print("connect to AI")
	spell_text_input.clear()
