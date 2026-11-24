extends Control

const MAX_HISTORY := 10

# TODO!!
# Placeholder values until the real name / damage / best modifier are computed
const PLACEHOLDER_NAME := "Cinder"
const PLACEHOLDER_DAMAGE := 75
const PLACEHOLDER_BEST := "Ignis"

## Node that emits `spell_generated` whenever a new spell sequence is created.
@export var spell_source: CastTyperTest
@export var element_images: Array[Texture2D] # the order is the same as in the enum

@onready var spell_promt: Label = $VBoxContainer/SpellPromt
@onready var spell_text_input: LineEdit = $VBoxContainer/SpellTextInput
@onready var counter_label: Label = $SpellHistoryPanel/VBoxContainer/Counter
@onready var scroll_container: ScrollContainer = $SpellHistoryPanel/VBoxContainer/ScrollContainer
@onready var spell_list: VBoxContainer = $SpellHistoryPanel/VBoxContainer/ScrollContainer/SpellList
@onready var entry_template: PanelContainer = $SpellHistoryPanel/VBoxContainer/ScrollContainer/SpellList/SpellEntryTemplate

# Current spell (the one being typed right now, shown on the upper bar)
@onready var components_scroll: ScrollContainer = $SpellComponentsPanel/ComponentsScroll
@onready var components_bar: HBoxContainer = $SpellComponentsPanel/ComponentsScroll/ComponentsBar
@onready var current_component_template: PanelContainer = $SpellComponentsPanel/ComponentsScroll/ComponentsBar/SpellComponentTemplate

# Current component (shown on the center of the screen + its key to press)
@onready var current_component_panel: PanelContainer = $CurrentComponentPanel


const SCROLL_DURATION := 0.25
const COLOR_CURRENT := Color(0.516, 0.396, 0.131, 1.0)  # yellow: component to type now
const COLOR_DONE := Color(0.128, 0.429, 0.16, 1.0)     # green: already typed correctly

var _default_component_color: Color

var _elements: Array[Enums.Spell]
var _component_template: PanelContainer
var _spells_cast := 0
var _scroll_tween: Tween
var _active = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spell_text_input.text_submitted.connect(_on_LineEdit_text_entered)

	# Take the template card (and its single component slot) out of the list;
	# they are only used as blueprints to duplicate from.
	var components := entry_template.get_node("VBoxContainer/Components")
	_component_template = components.get_child(0)
	components.remove_child(_component_template)
	spell_list.remove_child(entry_template)
	components_bar.remove_child(current_component_template)
	
	var template_sb := current_component_template.get_theme_stylebox("panel") as StyleBoxFlat
	if template_sb:
		_default_component_color = template_sb.bg_color

	if spell_source:
		spell_source.spell_generated.connect(show_current_spell) # show on top  bar
		if spell_source.typer :
			spell_source.typer.on_failed_cast.connect(_on_typing_active_false)
			spell_source.typer.on_successful_cast.connect(add_spell_entry) # show on history
			spell_source.typer.update_graphics.connect(_on_typing_progress)
	_update_counter()
	
	current_component_panel.visible = false

func _exit_tree() -> void:
	# The templates are not in the tree, so they must be freed manually
	for template in [entry_template, _component_template, current_component_template]:
		if is_instance_valid(template):
			template.free()

func _on_typing_active_true() -> void:
	_active = true 
	
func _on_typing_active_false() -> void:
	print("changing to false")
	_active = false

# MUST SENT PROMPT TO AI CONNECTION
func _on_LineEdit_text_entered(new_text: String) -> void:
	spell_promt.text = "Cooking..."
	print("connect to AI !! ")
	spell_text_input.clear()

# FOR ADDING SPELL TO HISTORY 
func add_spell_entry() -> void:
	if !_active: 
		return
	
	var entry := entry_template.duplicate() as PanelContainer
	entry.name = "SpellEntry%d" % (_spells_cast + 1)
	entry.visible = true

	# EDIT THESE WITH PROPER VALUES
	entry.get_node("VBoxContainer/SpellName").text = PLACEHOLDER_NAME
	entry.get_node("VBoxContainer/Stats/Damage/Label").text = "%d damage" % PLACEHOLDER_DAMAGE
	entry.get_node("VBoxContainer/Stats/Best/Label").text = "Best: %s" % PLACEHOLDER_BEST

	# One PanelContainer per element of the sequence
	var components := entry.get_node("VBoxContainer/Components")
	for i in _elements.size():
		var slot := _component_template.duplicate() as PanelContainer
		slot.name = "Component%d" % (i + 1)

		set_panel_image(_elements[i], slot.get_node("Panel"))
		components.add_child(slot)

	spell_list.add_child(entry)
	spell_list.move_child(entry, 0)
	scroll_container.scroll_vertical = 0

	# Keep at most MAX_HISTORY entries, dropping the oldest
	while spell_list.get_child_count() > MAX_HISTORY:
		var oldest := spell_list.get_child(spell_list.get_child_count() - 1)
		spell_list.remove_child(oldest)
		oldest.queue_free()

	_spells_cast += 1
	_update_counter()

func _update_counter() -> void:
	counter_label.text = "%d / %d spells cast" % [min(_spells_cast, MAX_HISTORY), MAX_HISTORY]



# FOR ADDING SPELL TO UPPER BAR
# Fills ComponentsBar with one component (image + name) per element of the new spell
func show_current_spell(elements: Array[Enums.Spell]) -> void:
	_on_typing_active_true()
	_elements = elements
	
	for child in components_bar.get_children():
		components_bar.remove_child(child)
		child.queue_free()

	for i in elements.size():
		var component := current_component_template.duplicate() as PanelContainer
		component.name = "Component%d" % (i + 1)
		component.visible = true
		set_panel_image(elements[i], component.get_node("VBoxContainer/Panel"))
		component.get_node("VBoxContainer/Label").text = Enums.spell_to_string(elements[i])
		components_bar.add_child(component)

	_update_component_colors(0) # first component is the one to type
	_scroll_to(0)
	
	current_component_panel.visible = true
	set_current_component(0) 
	

# Scrolls so the next component to type is centered, revealing the hidden ones on the right
func _on_typing_progress(correct_amount: int) -> void:
	if !_active:
		return
	
	var count := components_bar.get_child_count()
	if count == 0:
		return

	_update_component_colors(correct_amount)

	var next := components_bar.get_child(min(correct_amount, count - 1)) as Control
	var target := next.position.x + next.size.x / 2.0 - components_scroll.size.x / 2.0
	_scroll_to(target)

	set_current_component(correct_amount)

func _scroll_to(target: float) -> void:
	# Clamp to the scrollable range so the tween doesn't overshoot
	var max_scroll := maxf(0.0, components_bar.size.x - components_scroll.size.x)
	target = clampf(target, 0.0, max_scroll)
	
	if _scroll_tween:
		_scroll_tween.kill()
		
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(components_scroll, "scroll_horizontal", int(target), SCROLL_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Typed components -> green, current one -> yellow, the rest -> default
func _update_component_colors(correct_amount: int) -> void:
	for i in components_bar.get_child_count():
		var component := components_bar.get_child(i) as PanelContainer
		if i < correct_amount:
			set_panel_color(COLOR_DONE, component)
		elif i == correct_amount:
			set_panel_color(COLOR_CURRENT, component)
		else:
			set_panel_color(_default_component_color, component)

func set_panel_image(spell: Enums.Spell, slot: Panel) -> void:
	if spell >= element_images.size() or element_images[spell] == null :
		slot.remove_theme_stylebox_override("panel")
		return
	var sb := slot.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
	sb.texture = element_images[spell]
	slot.add_theme_stylebox_override("panel", sb)
	
func set_panel_color(new_color: Color, slot: PanelContainer) -> void:
	var sb := slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if sb == null:
		return
	sb.bg_color = new_color
	slot.add_theme_stylebox_override("panel", sb)


# FOR SHOWING THE CURRENT SPELL TO PRESS ITS KEY
func set_current_component(element_id: int) -> void:	
	if element_id >= _elements.size():
		current_component_panel.visible = false
		return 
	
	var slot = current_component_panel.get_node("VBoxContainer/Panel") as Panel
	set_panel_image(_elements[element_id], slot)
	var press_text = current_component_panel.get_node("VBoxContainer/PressKeyLabel")
	press_text.text = Enums.spell_to_key(_elements[element_id])
	
