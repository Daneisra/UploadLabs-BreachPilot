extends HFlowContainer
## The small row shown under a Breach node's level buttons. It only displays what it is given and
## reports its button: it knows nothing about the regulation. It is not part of the game's save data.

const NODE_NAME := "SmartAutomationControl"
const FONT_SIZE := 16
const BUTTON_HEIGHT := 36
const COLORS := {
	"active": Color(0.35, 0.85, 0.55),
	"pause": Color(0.95, 0.65, 0.25),
	"blocked": Color(0.95, 0.4, 0.4),
	"disabled": Color(0.6, 0.65, 0.72),
}

var _label := Label.new()
var _button := Button.new()
var _advice_button := Button.new()
var _shown: Dictionary = {}


## source gives the look of the game's own buttons. on_pressed is called once per click.
## on_advice, when given, adds a button opening the advice.
func setup(source: Button, on_pressed: Callable, on_advice: Callable = Callable()) -> void:
	name = NODE_NAME
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_button.theme_type_variation = source.theme_type_variation
	_button.custom_minimum_size.y = BUTTON_HEIGHT
	_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(on_pressed)
	add_child(_label)
	add_child(_button)
	if on_advice.is_valid():
		_advice_button.text = "Conseil"
		_advice_button.theme_type_variation = source.theme_type_variation
		_advice_button.custom_minimum_size.y = BUTTON_HEIGHT
		_advice_button.add_theme_font_size_override("font_size", FONT_SIZE)
		_advice_button.focus_mode = Control.FOCUS_NONE
		_advice_button.pressed.connect(on_advice)
		add_child(_advice_button)


## view: kind, text, button (empty for none), tooltip. Nothing is touched if it did not change.
func show_state(view: Dictionary) -> void:
	if view == _shown:
		return
	_shown = view
	_label.text = view.text
	_label.add_theme_color_override("font_color", COLORS[view.kind])
	_label.tooltip_text = view.tooltip
	_label.mouse_filter = Control.MOUSE_FILTER_STOP if not view.tooltip.is_empty() else Control.MOUSE_FILTER_PASS
	_button.text = view.button
	_button.tooltip_text = view.tooltip
	_button.visible = not view.button.is_empty()


func shown() -> Dictionary:
	return _shown


func button() -> Button:
	return _button
