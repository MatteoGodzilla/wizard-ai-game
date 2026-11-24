extends CanvasLayer

signal submitted(text: String)
signal book_requested
signal reset_requested
signal workshop_requested
signal modal_changed(is_open: bool)

const INK := Color("#f5efd9")
const MUTED := Color("#bdc7af")
const MINT := Color("#d5eea3")
const AMBER := Color("#ffcf91")

var _canvas: Control
var _modal: ColorRect
var _mode := ""
var _status: Label
var _equipped: Label
var _detail: Label
var _inspector: ScrollContainer
var _quick_field: LineEdit
var _quick_note: Label
var _suggestions: HBoxContainer
var _list: ItemList
var _book_description: Label
var _book_use: Button
var _book_entries: Dictionary
var _book_states: Callable
var _book_query := ""
var _book_selection := ""


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.theme = _make_theme()
	add_child(_canvas)

	var title := _corner_card(Control.PRESET_TOP_LEFT, Vector2(20, 18), Vector2(268, 0))
	title.add_child(_label("Spellcheck", 30))
	_equipped = _label("No spell equipped", 15, MINT)
	_equipped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(_equipped)
	_status = _label("", 14, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(_status)

	var tools := _corner_card(Control.PRESET_TOP_RIGHT, Vector2(-20, 18), Vector2(327, 0))
	var buttons := HBoxContainer.new()
	tools.add_child(buttons)
	_button(buttons, "Spellbook", func() -> void: book_requested.emit())
	_button(buttons, "Reset world", func() -> void: reset_requested.emit())
	_button(buttons, "Back to Workshop", func() -> void: workshop_requested.emit())
	var toggle := _button(buttons, "Inspect", func() -> void: _inspector.visible = not _inspector.visible)
	toggle.toggle_mode = true
	_detail = _label("Cast a spell to inspect its definition.", 14, MUTED)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector = ScrollContainer.new()
	_inspector.custom_minimum_size = Vector2(298, 320)
	_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.add_child(_detail)
	_inspector.hide()
	tools.add_child(_inspector)

	var controls := _corner_card(Control.PRESET_BOTTOM_LEFT, Vector2(20, -18), Vector2.ZERO)
	controls.add_child(_label("WASD  Move     Mouse  Aim     Hold Shift  Type spell     Click  Cast     B  Spellbook", 14, MUTED))


func has_modal() -> bool:
	return is_instance_valid(_modal)


func mode() -> String:
	return _mode


func close_modal() -> void:
	if not has_modal():
		return
	_canvas.remove_child(_modal)
	_modal.queue_free()
	_modal = null
	_mode = ""
	modal_changed.emit(false)


func feedback(message: String, is_error: bool = false) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", AMBER if is_error else MUTED)


func set_equipped(spell_name: String = "") -> void:
	_equipped.text = "No spell equipped" if spell_name.is_empty() else "Equipped  ·  " + spell_name


func inspect(entry: Dictionary, result: Dictionary) -> void:
	var details: Array[String] = [
		entry["name"],
		"Source  ·  " + str(result.get("source", "AI")),
		"Time  ·  %d ms" % result.get("elapsed_ms", 0),
	]
	if not str(entry["description"]).is_empty():
		details.insert(1, entry["description"])
	if not str(result.get("reference", "")).is_empty():
		details.append("Reference  ·  " + str(result["reference"]))
	if not str(result.get("meaning", "")).is_empty():
		details.append("Interpretation  ·  " + str(result["meaning"]))
	if result.has("intent"):
		var intent: Dictionary = result["intent"]
		var spell: Dictionary = result["compiled"]
		var origin := "Preset" if result.get("source") == "Preset" else "AI selections"
		details.append("%s  ·  %s / %s / %s" % [origin, intent["form"], intent["palette"], intent["particle"]])
		details.append("Charge  ·  %.2f s   Path  ·  %s" % [spell["charge"], spell["path"]])
		if spell["form"] == "BEAM":
			var beam: Dictionary = spell["beam"]
			details.append("Beam  ·  %d rays / %s / %.1f° spread" % [beam["lanes"], beam["anchor"], beam["spread"]])
		if spell["form"] == "DOMAIN":
			details.append("Domain  ·  %.1f m / %.1f s" % [spell["area_radius"], spell["duration"]])
		for rule: Dictionary in spell["rules"]:
			var amount: Variant = rule["value"]
			if amount is Color:
				amount = "#" + amount.to_html(false)
			var target := "%s %s" % [rule["scope"], rule["tag"]]
			var action := str(rule["op"])
			if rule["op"] == "SPAWN":
				action += " %d × %s" % [rule["count"], amount]
			elif rule["property"] != "NONE":
				action += " %s %s" % [rule["property"], amount]
			if rule["duration"] > 0.0:
				action += "  ·  %.1f s" % rule["duration"]
			details.append("%s  ·  %s  →  %s" % [rule["event"], target, action])
		for profile: Dictionary in spell["emitters"]:
			details.append("%s particles  ·  %s / %s / %s" % [profile["phase"], profile["anchor"], profile["direction"], profile["shape"]])
			details.append("Color  ·  #%s   Speed  ·  %.1f" % [profile["color"].to_html(false), profile["speed"]])
		details.append("Validation  ·  Passed")
	else:
		details.append("Validation  ·  No executable definition")
		details.append(str(result.get("error", "")))
	if not str(result.get("model", "")).is_empty():
		details.append("Model  ·  " + str(result["model"]))
	_detail.text = "\n".join(details)


func clear_inspection() -> void:
	_detail.text = "Cast a spell to inspect its definition."


func open_quick(prefix_lookup: Callable) -> void:
	var panel := _open_modal("quick", "Prepare a spell", 535)
	_quick_field = LineEdit.new()
	_quick_field.placeholder_text = "Type an unlocked spell name"
	_quick_field.max_length = 120
	_quick_field.custom_minimum_size.y = 43
	panel.add_child(_quick_field)
	_quick_note = _label("Release Shift to prepare. Left click to cast.", 14, MUTED)
	_quick_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_quick_note)
	_suggestions = HBoxContainer.new()
	panel.add_child(_suggestions)
	_quick_field.text_changed.connect(func(text: String) -> void:
		_set_quick_hint(prefix_lookup.call(text))
	)
	_quick_field.grab_focus()


func quick_text() -> String:
	return _quick_field.text


func _set_quick_hint(names: Array) -> void:
	for child in _suggestions.get_children():
		_suggestions.remove_child(child)
		child.queue_free()
	for name_text: String in names:
		var choice := _button(_suggestions, name_text, func() -> void:
			_quick_field.text = name_text
			_quick_field.grab_focus()
			_quick_field.caret_column = name_text.length()
			_set_quick_hint([])
		)
		choice.clip_text = true
		choice.custom_minimum_size.x = 104.0


func open_book(entries: Dictionary, state_lookup: Callable, selected: String = "") -> void:
	var panel := _open_modal("book", "Unlocked spells", 610)
	_book_entries = entries
	_book_states = state_lookup
	_book_query = ""
	_book_selection = selected
	var search := LineEdit.new()
	search.placeholder_text = "Search names"
	search.max_length = 120
	panel.add_child(search)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 232
	panel.add_child(_list)
	_book_description = _label("", 15, INK)
	_book_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_book_description.custom_minimum_size.y = 87
	panel.add_child(_book_description)
	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	_book_use = _button(buttons, "Equip spell", func() -> void:
		submitted.emit(_book_entries[_book_selection]["name"])
	)
	_button(buttons, "Close", close_modal)
	_list.item_selected.connect(func(index: int) -> void:
		_book_selection = _list.get_item_metadata(index)
		_show_book_selection()
	)
	search.text_changed.connect(func(query: String) -> void:
		_book_query = query.strip_edges().to_lower()
		refresh_book()
	)
	refresh_book()
	search.grab_focus()


func refresh_book() -> void:
	if _mode != "book":
		return
	_list.clear()
	var ids := _book_entries.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _book_entries[a]["name"].nocasecmp_to(_book_entries[b]["name"]) < 0
	)
	var selected_index := -1
	for id: String in ids:
		var entry: Dictionary = _book_entries[id]
		if not _book_query.is_empty() and not str(entry["name"]).to_lower().contains(_book_query):
			continue
		if _book_states.call(id) != "READY":
			continue
		var index := _list.add_item(entry["name"])
		_list.set_item_metadata(index, id)
		_list.set_item_custom_fg_color(index, MINT)
		if id == _book_selection:
			selected_index = index
	if selected_index == -1 and _list.item_count > 0:
		selected_index = 0
	if selected_index != -1:
		_book_selection = _list.get_item_metadata(selected_index)
		_list.select(selected_index)
		_list.ensure_current_is_visible()
	else:
		_book_selection = ""
	_show_book_selection()


func _show_book_selection() -> void:
	_book_use.disabled = _book_selection.is_empty()
	if _book_selection.is_empty():
		_book_description.text = "No matching spells."
		return
	var entry: Dictionary = _book_entries[_book_selection]
	_book_description.text = "%s\n%s" % [
		str(entry["origin"]).replace("_", " ").capitalize(), entry["description"],
	]


func _open_modal(kind: String, title: String, width: float) -> VBoxContainer:
	if not has_modal():
		_modal = ColorRect.new()
		_modal.color = Color("#071815a5")
		_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_canvas.add_child(_modal)
		modal_changed.emit(true)
	else:
		var old := _modal.get_child(0)
		_modal.remove_child(old)
		old.queue_free()
	_mode = kind
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var content := _card(center, Vector2(width, 0))
	content.add_child(_label(title, 28))
	return content


func _corner_card(preset: Control.LayoutPreset, offset: Vector2, minimum: Vector2) -> VBoxContainer:
	var offset_root := Control.new()
	offset_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(offset_root)
	offset_root.set_anchors_and_offsets_preset(preset)
	var body := PanelContainer.new()
	body.custom_minimum_size = minimum
	offset_root.add_child(body)
	body.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0.0 else Control.GROW_DIRECTION_END
	body.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0.0 else Control.GROW_DIRECTION_END
	body.position = offset
	if offset.x < 0.0 or offset.y < 0.0:
		body.resized.connect(func() -> void:
			body.position = offset - Vector2(body.size.x if offset.x < 0.0 else 0.0, body.size.y if offset.y < 0.0 else 0.0)
		)
	return _card_content(body)


func _card(parent: Control, minimum: Vector2) -> VBoxContainer:
	var body := PanelContainer.new()
	body.custom_minimum_size = minimum
	parent.add_child(body)
	return _card_content(body)


func _card_content(body: PanelContainer) -> VBoxContainer:
	body.add_theme_stylebox_override("panel", _style(Color("#152526f5"), Color("#587165"), 12, 15))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	body.add_child(content)
	return content


func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(value: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_theme() -> Theme:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 15
	for type: String in ["Button", "LineEdit", "TextEdit", "ItemList"]:
		ui_theme.set_color("font_color", type, INK)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var background := Color("#263c37") if state == "normal" else Color("#375345")
		var border := MINT if state == "focus" else Color("#526c5a")
		ui_theme.set_stylebox(state, "Button", _style(background, border, 7, 9))
	ui_theme.set_color("font_hover_color", "Button", MINT)
	ui_theme.set_color("font_disabled_color", "Button", Color("#849186"))
	ui_theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	ui_theme.set_color("font_placeholder_color", "TextEdit", MUTED)
	for type: String in ["LineEdit", "TextEdit", "ItemList"]:
		ui_theme.set_stylebox("normal" if type != "ItemList" else "panel", type, _style(Color("#0d1b1c"), Color("#466056"), 6, 8))
		ui_theme.set_stylebox("focus", type, _style(Color.TRANSPARENT, MINT, 6, 8))
	ui_theme.set_stylebox("selected", "ItemList", _style(Color("#314c41"), Color("#4c705c"), 5, 3))
	ui_theme.set_stylebox("selected_focus", "ItemList", _style(Color("#314c41"), Color("#72906a"), 5, 3))
	ui_theme.set_constant("v_separation", "ItemList", 5)
	return ui_theme


func _style(background: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.7
	style.content_margin_bottom = padding * 0.7
	return style
