extends CanvasLayer
## The advisor's panel. It only shows: its buttons change what is displayed, never the game.
## The recommendation comes first; the tables behind it fold away.

const LAYER := 90
const TITLE_SIZE := 26
const SUMMARY_SIZE := 20
const CELL_SIZE := 19
const NOTE_SIZE := 16
const WIDTH := 1240.0
const BACKGROUND := Color(0.07, 0.09, 0.13)
const BORDER := Color(0.3, 0.38, 0.5)
const TEXT := Color(0.93, 0.95, 0.98)
const GOOD := Color(0.45, 0.9, 0.55)
const CURRENT := Color(0.5, 0.78, 1.0)
const MUTED := Color(0.62, 0.68, 0.75)
const BAD := Color(1.0, 0.7, 0.45)
const CARD := Color(0.1, 0.13, 0.19)
const I18n := preload("../../core/i18n.gd")

var _title: Label
var _close: Button
var _objectives: HBoxContainer
var _summary: Label
var _card: VBoxContainer
var _toggle: Button
var _details: VBoxContainer
var _grid: GridContainer
var _upgrade_grid: GridContainer
var _note: Label
## Kept while the game runs: a player who wants the figures should not have to unfold them each time.
var _details_open := false


func _init() -> void:
	layer = LAYER
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _label("", TITLE_SIZE, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close = _button("")
	_close.pressed.connect(func() -> void: visible = false)
	header.add_child(_close)

	_objectives = HBoxContainer.new()
	_objectives.add_theme_constant_override("separation", 8)
	column.add_child(_objectives)
	_summary = _label("", SUMMARY_SIZE, TEXT)
	_wrap(_summary)
	column.add_child(_summary)
	var card_panel := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = CARD
	card_style.set_corner_radius_all(6)
	card_style.set_content_margin_all(14)
	card_panel.add_theme_stylebox_override("panel", card_style)
	column.add_child(card_panel)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 6)
	card_panel.add_child(_card)
	_toggle = _button("")
	_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_toggle.pressed.connect(_on_toggle)
	column.add_child(_toggle)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 14)
	column.add_child(_details)
	_grid = _new_grid()
	_details.add_child(_grid)
	_upgrade_grid = _new_grid()
	_details.add_child(_upgrade_grid)
	_note = _label("", NOTE_SIZE, MUTED)
	_wrap(_note)
	_details.add_child(_note)
	_show_details()


func show_message(text: String) -> void:
	visible = true
	_relabel()
	_summary.text = text
	_summary.visible = true
	_note.text = ""
	_clear(_objectives)
	_clear(_card)
	_card.get_parent().visible = false
	_toggle.visible = false
	_fill(_grid, {"rows": [], "kinds": []})
	_fill(_upgrade_grid, {"rows": [], "kinds": []})


## card holds lines {text, kind}, kind being "title", "good", "bad", "muted" or "". tables hold rows, lists
## of cells, and kinds, each row's color: "header", "current", "best", "muted" or "".
func show_advice(options: Array[Dictionary], selected: String, on_select: Callable, card: Array[Dictionary], connections: Dictionary, purchases: Dictionary, note: String) -> void:
	visible = true
	_relabel()
	_summary.visible = false
	_card.get_parent().visible = true
	_toggle.visible = true
	_clear(_card)
	for line: Dictionary in card:
		var label := _label(line.text, SUMMARY_SIZE if line.kind == "title" else CELL_SIZE, _color(line.kind))
		_wrap(label)
		_card.add_child(label)
	_note.text = note
	_clear(_objectives)
	_objectives.add_child(_label(I18n.t("panel.objective"), CELL_SIZE, MUTED))
	for option: Dictionary in options:
		var button := _button(option.label)
		if option.key == selected:
			button.add_theme_color_override("font_color", GOOD)
			button.add_theme_color_override("font_hover_color", GOOD)
		button.pressed.connect(on_select.bind(option.key))
		_objectives.add_child(button)
	_fill(_grid, connections)
	_fill(_upgrade_grid, purchases)


func _on_toggle() -> void:
	_details_open = not _details_open
	_show_details()


func _show_details() -> void:
	_details.visible = _details_open
	_toggle.text = I18n.t("panel.hide_details" if _details_open else "panel.show_details")


## The fixed words follow the game's language each time the panel shows, without rebuilding anything.
func _relabel() -> void:
	_title.text = I18n.t("panel.title")
	_close.text = I18n.t("panel.close")
	_show_details()


func _fill(grid: GridContainer, table: Dictionary) -> void:
	_clear(grid)
	grid.visible = table.rows.size() > 1
	if table.rows.is_empty():
		return
	grid.columns = table.rows[0].size()
	for index: int in table.rows.size():
		for cell: String in table.rows[index]:
			grid.add_child(_label(cell, CELL_SIZE, _color(table.kinds[index])))


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _color(kind: String) -> Color:
	match kind:
		"header", "muted":
			return MUTED
		"current":
			return CURRENT
		"best", "good":
			return GOOD
		"bad":
			return BAD
	return TEXT


func _new_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _wrap(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", CELL_SIZE)
	return button


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
