extends Control
## Shows the recipe being crafted and the collection of successfully completed spells.

signal spell_submitted(spell_name: String)
signal craft_submitted(spell_name: String, description: String)
signal cancel_requested
signal retry_requested(id: String, description: String)
signal finish_requested
signal continue_requested
signal sandbox_requested
signal menu_requested

const Spellbook = preload("res://spellcheck/spellbook.gd")
const SCROLL_DURATION := 0.2
const COLOR_CURRENT := Color(0.516, 0.396, 0.131)
const COLOR_DONE := Color(0.128, 0.429, 0.16)

@export var spell_source: Node
@export var element_images: Array[Texture2D]

@onready var spell_promt: Label = $VBoxContainer/SpellPromt
@onready var spell_text_input: LineEdit = $VBoxContainer/SpellTextInput
@onready var spell_description_input: LineEdit = $VBoxContainer/SpellDescriptionInput
@onready var counter_label: Label = $SpellBookPanel/VBoxContainer/Counter
@onready var scroll_container: ScrollContainer = $SpellBookPanel/VBoxContainer/ScrollContainer
@onready var spell_list: VBoxContainer = $SpellBookPanel/VBoxContainer/ScrollContainer/SpellList
@onready var empty_label: Label = $SpellBookPanel/VBoxContainer/ScrollContainer/SpellList/EmptyLabel
@onready var entry_template: PanelContainer = $SpellBookPanel/VBoxContainer/ScrollContainer/SpellList/SpellEntryTemplate
@onready var finish_button: Button = $SpellBookPanel/VBoxContainer/FinishButton
@onready var sandbox_shortcut: Button = $SandboxShortcut
@onready var components_scroll: ScrollContainer = $SpellComponentsPanel/ComponentsScroll
@onready var components_bar: HBoxContainer = $SpellComponentsPanel/ComponentsScroll/ComponentsBar
@onready var current_component_template: PanelContainer = $SpellComponentsPanel/ComponentsScroll/ComponentsBar/SpellComponentTemplate
@onready var current_component_panel: PanelContainer = $CurrentComponentPanel

var _component_template: PanelContainer
var _default_component_color := Color(0.28, 0.22, 0.32)
var _elements: Array[Enums.Element] = []
var _crafted_count := 0
var _scroll_tween: Tween
var _active := false
var _can_cancel := false
var _practice_typer: CastTyper


func _ready() -> void:
	spell_text_input.max_length = 120
	spell_text_input.text_submitted.connect(_on_LineEdit_text_entered)
	spell_description_input.text_submitted.connect(func(_description: String) -> void:
		_on_LineEdit_text_entered(spell_text_input.text)
	)
	$VBoxContainer/GenerateButton.pressed.connect(func() -> void:
		if _can_cancel:
			cancel_requested.emit()
		else:
			_on_LineEdit_text_entered(spell_text_input.text)
	)
	finish_button.pressed.connect(func() -> void: finish_requested.emit())
	sandbox_shortcut.pressed.connect(func() -> void: sandbox_requested.emit())
	$ResultPanel/VBoxContainer/ContinueButton.pressed.connect(func() -> void: continue_requested.emit())
	$ResultPanel/VBoxContainer/SandboxButton.pressed.connect(func() -> void: sandbox_requested.emit())
	$ResultPanel/VBoxContainer/MenuButton.pressed.connect(func() -> void: menu_requested.emit())
	var components := entry_template.get_node("VBoxContainer/Components")
	_component_template = components.get_child(0)
	components.remove_child(_component_template)
	spell_list.remove_child(entry_template)
	components_bar.remove_child(current_component_template)
	var style := current_component_template.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		_default_component_color = style.bg_color
	if element_images.is_empty():
		for name: String in ["Aqua", "Aer", "ignis", "Terra", "Lux", "Tenebrae", "Corpus", "Arcanum"]:
			element_images.append(load("res://Fantasy_Assets/Element_Images/%s.png" % name))
	# The separate controls scene uses the same recipe display without saving a collection.
	if spell_source != null and spell_source.has_signal("spell_generated"):
		spell_source.connect("spell_generated", show_current_spell)
		_practice_typer = spell_source.get("typer") as CastTyper
		if _practice_typer != null:
			_practice_typer.on_failed_cast.connect(_on_typing_active_false)
			_practice_typer.on_successful_cast.connect(_on_practice_completed)
			_practice_typer.update_graphics.connect(_on_typing_progress)
		finish_button.hide()
		spell_description_input.hide()
	sandbox_shortcut.visible = spell_source == null
	if sandbox_shortcut.visible:
		$SpellNameLabel.offset_right = sandbox_shortcut.offset_left - 12.0
	$Panel.visible = spell_source != null
	_update_counter()
	current_component_panel.hide()
	_update_key_guide()


func _exit_tree() -> void:
	for template in [entry_template, _component_template, current_component_template]:
		if is_instance_valid(template):
			template.free()


func _on_LineEdit_text_entered(new_text: String) -> void:
	if spell_text_input.editable:
		if spell_source == null:
			craft_submitted.emit(new_text, spell_description_input.text)
		else:
			spell_submitted.emit(new_text)


func set_entry_enabled(enabled: bool, clear_input: bool = false) -> void:
	spell_text_input.editable = enabled
	spell_description_input.editable = enabled
	$VBoxContainer/GenerateButton.disabled = not enabled
	set_finish_enabled(enabled and _crafted_count > 0)
	if enabled:
		if clear_input:
			spell_text_input.clear()
			spell_description_input.clear()
		spell_text_input.grab_focus()
	else:
		spell_text_input.release_focus()
		spell_description_input.release_focus()
		$VBoxContainer/GenerateButton.release_focus()


func set_finish_enabled(enabled: bool) -> void:
	finish_button.disabled = not enabled


func set_cancel_enabled(enabled: bool) -> void:
	_can_cancel = enabled
	var button: Button = $VBoxContainer/GenerateButton
	button.text = "Cancel crafting" if enabled else "Create recipe"
	button.disabled = not enabled and not spell_text_input.editable


func show_status(message: String) -> void:
	spell_promt.text = message


func show_recipe(recipe: Dictionary, elements: Array[Enums.Element], built_in: bool = false) -> void:
	$SpellNameLabel.text = recipe["name"]
	$SpellNameLabel.tooltip_text = recipe["name"]
	var prefix := "Built-in recipe. " if built_in else ""
	$DescriptionLabel.text = prefix + recipe["description"]
	$DescriptionLabel.tooltip_text = prefix + recipe["description"]
	show_current_spell(elements)


func show_current_spell(elements: Array[Enums.Element]) -> void:
	$SpellComponentsPanel.show()
	_active = true
	_elements = elements.duplicate()
	for child in components_bar.get_children():
		components_bar.remove_child(child)
		child.queue_free()
	for index in elements.size():
		var component := current_component_template.duplicate() as PanelContainer
		component.name = "Component%d" % (index + 1)
		component.show()
		set_panel_image(elements[index], component.get_node("VBoxContainer/Panel"))
		component.get_node("VBoxContainer/Label").text = Enums.spell_to_string(elements[index])
		components_bar.add_child(component)
	_update_component_colors(0)
	_scroll_to(0)
	current_component_panel.show()
	set_current_component(0)


func show_countdown(seconds: int, built_in: bool) -> void:
	var prefix := "Built-in recipe. " if built_in else ""
	show_status("%sRead the recipe. Crafting starts in %d..." % [prefix, seconds])
	current_component_panel.get_node("VBoxContainer/PressKeyLabel").text = str(seconds)


func show_cast_status(elapsed: float, mistakes: int) -> void:
	show_status("Cast the elements in order. %.2f s  |  %d mistakes" % [elapsed, mistakes])


func _on_typing_progress(correct_amount: int) -> void:
	if not _active or components_bar.get_child_count() == 0:
		return
	_update_component_colors(correct_amount)
	var index := mini(correct_amount, components_bar.get_child_count() - 1)
	var next := components_bar.get_child(index) as Control
	_scroll_to(next.position.x + next.size.x / 2.0 - components_scroll.size.x / 2.0)
	set_current_component(correct_amount)


func _on_typing_active_false() -> void:
	_active = false
	current_component_panel.hide()


func hide_current_recipe() -> void:
	_on_typing_active_false()
	$SpellComponentsPanel.hide()
	$SpellNameLabel.text = "Craft a spell"
	$DescriptionLabel.text = "Invent a name, complete its recipe and add it to your spellbook."


func add_spell_entry(record: Dictionary) -> PanelContainer:
	_crafted_count += 1
	var entry := entry_template.duplicate() as PanelContainer
	entry.name = "SpellEntry%d" % _crafted_count
	entry.show()
	entry.get_node("VBoxContainer/SpellName").text = record["name"]
	entry.get_node("VBoxContainer/SpellName").tooltip_text = record["name"]
	entry.get_node("VBoxContainer/Stats/Time/Label").text = "%.2f s" % record["craft_time"]
	entry.get_node("VBoxContainer/Stats/Mistakes/Label").text = "%d mistakes" % record["mistakes"]
	var source_label := "Built-in recipe. " if record.get("source", "") == "fallback" else ""
	entry.tooltip_text = source_label + record["description"]
	for name: String in record["elements"]:
		var slot := _component_template.duplicate() as PanelContainer
		slot.tooltip_text = name
		set_panel_image(Enums.string_to_spell(name), slot.get_node("Panel"))
		entry.get_node("VBoxContainer/Components").add_child(slot)
	spell_list.add_child(entry)
	spell_list.move_child(entry, 1)
	scroll_container.scroll_vertical = 0
	_update_counter()
	return entry


func _on_practice_completed() -> void:
	_on_typing_active_false()
	var names: Array[String] = []
	for element in _elements:
		names.append(Enums.spell_to_string(element))
	add_spell_entry({
		"name": "Practice spell", "description": "Controls practice",
		"elements": names, "craft_time": _practice_typer.elapsed_time,
		"mistakes": _practice_typer.mistakes,
	})


func reset_crafting() -> void:
	$SpellComponentsPanel.hide()
	_crafted_count = 0
	_active = false
	$ResultPanel.hide()
	current_component_panel.hide()
	$SpellNameLabel.text = "Craft a spell"
	$DescriptionLabel.text = "Invent a name, complete its recipe and add it to your spellbook."
	for container in [spell_list, components_bar]:
		for child in container.get_children():
			if child == empty_label:
				continue
			container.remove_child(child)
			child.queue_free()
	_update_counter()
	show_status("Enter a spell name and press Enter or Create recipe.")
	set_entry_enabled(true, true)


func show_workshop_records(records: Array[Dictionary], can_retry: bool) -> void:
	for child in spell_list.get_children():
		if child != empty_label:
			spell_list.remove_child(child)
			child.queue_free()
	_crafted_count = 0
	var unlocked := 0
	for record: Dictionary in records:
		var recipe: Dictionary = record["recipe"]
		var entry := add_spell_entry({
			"name": record["name"], "description": recipe.get("description", record.get("description", "")),
			"elements": recipe.get("elements", []), "craft_time": record["craft_time"],
			"mistakes": record["mistakes"],
		})
		if record["state"] == "unlocked":
			unlocked += 1
			continue
		var content := entry.get_node("VBoxContainer")
		var error := String(record.get("error", ""))
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = "Preparing sandbox effect…" if error.is_empty() else error
		content.add_child(detail)
		if can_retry and not error.is_empty():
			var clarification := LineEdit.new()
			clarification.placeholder_text = "Clarify the sandbox effect (optional)"
			clarification.max_length = 400
			content.add_child(clarification)
			var retry_button := Button.new()
			retry_button.text = "Retry sandbox effect"
			retry_button.pressed.connect(_request_retry.bind(record["id"], clarification))
			content.add_child(retry_button)
	_update_counter()
	$ResultPanel/VBoxContainer/Summary.text = "%d crafted spells ready for the sandbox.\n%d still preparing or need a retry.\nFireball is available from the start." % [
		unlocked, records.size() - unlocked,
	]


func _request_retry(id: String, clarification: LineEdit) -> void:
	retry_requested.emit(id, clarification.text)


func show_crafting_result() -> void:
	_on_typing_active_false()
	$ResultPanel.show()
	$ResultPanel/VBoxContainer/SandboxButton.grab_focus()


func hide_crafting_result() -> void:
	$ResultPanel.hide()


func _update_counter() -> void:
	counter_label.text = "%d / %d spells crafted" % [_crafted_count, Spellbook.MAX_CRAFTS]
	empty_label.visible = _crafted_count == 0


func _update_key_guide() -> void:
	var labels := PackedStringArray()
	for element: Enums.Element in Enums.valid_elements:
		labels.append("%s: %s" % [Enums.spell_to_string(element), InputBindingLabels.get_key_labels(SpellInputActions.get_action_name(element))])
	$KeyGuide.text = "    ".join(labels)


func _scroll_to(target: float) -> void:
	if _scroll_tween != null:
		_scroll_tween.kill()
	var limit := maxf(0.0, components_bar.size.x - components_scroll.size.x)
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(components_scroll, "scroll_horizontal", int(clampf(target, 0.0, limit)), SCROLL_DURATION)


func _update_component_colors(correct_amount: int) -> void:
	for index in components_bar.get_child_count():
		var component := components_bar.get_child(index) as PanelContainer
		var color := _default_component_color
		if index < correct_amount:
			color = COLOR_DONE
		elif index == correct_amount:
			color = COLOR_CURRENT
		set_panel_color(color, component)


func set_panel_image(element: Enums.Element, slot: Panel) -> void:
	if element < 0 or element >= element_images.size() or element_images[element] == null:
		return
	var style := StyleBoxTexture.new()
	style.texture = element_images[element]
	slot.add_theme_stylebox_override("panel", style)


func set_panel_color(color: Color, slot: PanelContainer) -> void:
	var style := slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style != null:
		style.bg_color = color
		slot.add_theme_stylebox_override("panel", style)


func set_current_component(index: int) -> void:
	if index >= _elements.size():
		current_component_panel.hide()
		return
	current_component_panel.show()
	set_panel_image(_elements[index], current_component_panel.get_node("VBoxContainer/Panel"))
	var keys := InputBindingLabels.get_key_labels(SpellInputActions.get_action_name(_elements[index]))
	var label := current_component_panel.get_node("VBoxContainer/PressKeyLabel") as Label
	label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.75))
	label.text = "Press " + keys
