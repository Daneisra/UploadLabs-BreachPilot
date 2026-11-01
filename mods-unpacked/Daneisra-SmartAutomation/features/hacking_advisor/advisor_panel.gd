extends CanvasLayer
## The advisor's panel. It only shows: no button here can change the game.

const LAYER := 90
const TITLE_SIZE := 26
const SUMMARY_SIZE := 21
const CELL_SIZE := 19
const NOTE_SIZE := 16
const WIDTH := 1180.0
const BACKGROUND := Color(0.07, 0.09, 0.13)
const BORDER := Color(0.3, 0.38, 0.5)
const TEXT := Color(0.93, 0.95, 0.98)
const GOOD := Color(0.45, 0.9, 0.55)
const CURRENT := Color(0.5, 0.78, 1.0)
const MUTED := Color(0.62, 0.68, 0.75)

var _summary: Label
var _grid: GridContainer
var _upgrade_grid: GridContainer
var _note: Label


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
	var title := _label("Conseil hacking", TITLE_SIZE, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", CELL_SIZE)
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)

	_summary = _label("", SUMMARY_SIZE, TEXT)
	_wrap(_summary)
	column.add_child(_summary)
	_grid = _new_grid()
	column.add_child(_grid)
	_upgrade_grid = _new_grid()
	column.add_child(_upgrade_grid)
	_note = _label("", NOTE_SIZE, MUTED)
	_wrap(_note)
	column.add_child(_note)


func show_message(text: String) -> void:
	visible = true
	_summary.text = text
	_note.text = ""
	_fill(_grid, [], [])
	_fill(_upgrade_grid, [], [])


## rows are lists of cells; kinds gives each row's color: "header", "current", "best", "muted" or "".
func show_tables(summary: String, rows: Array, kinds: Array, upgrade_rows: Array, upgrade_kinds: Array, note: String) -> void:
	visible = true
	_summary.text = summary
	_note.text = note
	_fill(_grid, rows, kinds)
	_fill(_upgrade_grid, upgrade_rows, upgrade_kinds)


func _fill(grid: GridContainer, rows: Array, kinds: Array) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.visible = rows.size() > 1
	if rows.is_empty():
		return
	grid.columns = rows[0].size()
	for index: int in rows.size():
		for cell: String in rows[index]:
			grid.add_child(_label(cell, CELL_SIZE, _color(kinds[index])))


func _color(kind: String) -> Color:
	match kind:
		"header", "muted":
			return MUTED
		"current":
			return CURRENT
		"best":
			return GOOD
	return TEXT


func _new_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _wrap(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
