extends CanvasLayer
## The advisor's panel. It only shows: no button here can change the game.

const LAYER := 90
const FONT_SIZE := 15
const GOOD := Color(0.45, 0.9, 0.55)
const CURRENT := Color(0.5, 0.75, 1.0)
const MUTED := Color(0.7, 0.75, 0.8)

var _summary: Label
var _grid: GridContainer
var _note: Label


func _init() -> void:
	layer = LAYER
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Conseil hacking", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)

	_summary = _label("", FONT_SIZE)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size.x = 860
	column.add_child(_summary)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(_grid)
	_note = _label("", 13)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 860
	_note.add_theme_color_override("font_color", MUTED)
	column.add_child(_note)


func show_message(text: String) -> void:
	visible = true
	_summary.text = text
	_note.text = ""
	_clear_grid()


## rows are lists of cells; kinds gives each row's color: "header", "current", "best" or "".
func show_table(summary: String, rows: Array, kinds: Array, note: String) -> void:
	visible = true
	_summary.text = summary
	_note.text = note
	_clear_grid()
	_grid.columns = rows[0].size()
	for index: int in rows.size():
		for cell: String in rows[index]:
			var label := _label(cell, FONT_SIZE)
			match kinds[index]:
				"header":
					label.add_theme_color_override("font_color", MUTED)
				"current":
					label.add_theme_color_override("font_color", CURRENT)
				"best":
					label.add_theme_color_override("font_color", GOOD)
			_grid.add_child(label)


func _clear_grid() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
