extends Node
## Connects the classifier to the game. Read-only: it never changes the threat level.

const ApiGuard := preload("../../core/api_guard.gd")
const SaLog := preload("../../core/sa_log.gd")
const BreachClassifier := preload("breach_classifier.gd")
const BreachPrediction := preload("breach_prediction.gd")

const WATCHED_WINDOWS: Array[String] = ["breach_corps"]
const RESCAN_TICKS := 100
const EVENT_FIELDS: Array[String] = [
	"cycle_id", "level", "level_after", "from", "to", "max_level", "time_left", "used", "ratio", "next_ratio",
	"volleys", "min_hit", "max_hit", "model_volleys", "model_volleys_worst", "next_volleys", "next_volleys_worst",
	"next_used", "next_max_time", "next_model_ratio", "next_model_ratio_worst",
	"max_time", "max_firewall", "max_breach", "damage_rate", "vulnerability", "complete", "observed_start",
	"threshold", "progress_age", "clues", "reason", "steps", "max_step", "mean_step", "real_seconds",
]

var _log: SaLog
var _starvation_ratio := 0.25
var _api_dump := false
var _active := false
var _signals: Node
var _globals: Node
var _attributes: Node
var _data: Node
var _trackers: Dictionary = {}
var _rejected: Dictionary = {}
var _last_success: Dictionary = {}
var _ticks_since_scan := 0


func configure(logger: SaLog, starvation_ratio: float, api_dump: bool) -> void:
	_log = logger
	_starvation_ratio = starvation_ratio
	_api_dump = api_dump


func is_active() -> bool:
	return _active


func start() -> void:
	if _active:
		return
	var root := get_tree().root
	_signals = root.get_node("Signals")
	_globals = root.get_node("Globals")
	_attributes = root.get_node("Attributes")
	_data = root.get_node("Data")
	_active = true
	_signals.tick.connect(_on_tick)
	_signals.breached.connect(_on_breached)
	_signals.window_created.connect(_bind_window)
	_signals.window_initialized.connect(_bind_window)
	_signals.window_deleted.connect(_on_window_deleted)
	_signals.desktop_ready.connect(_scan_desktop)
	_signals.setting_set.connect(_on_setting_set)
	_log.info("observer state=started native_auto_level=%s" % _data.auto_level_breach)
	# The desktop may already exist: desktop_ready would then never come.
	_scan_desktop()


func stop() -> void:
	if not _active:
		return
	_active = false
	_signals.tick.disconnect(_on_tick)
	_signals.breached.disconnect(_on_breached)
	_signals.window_created.disconnect(_bind_window)
	_signals.window_initialized.disconnect(_bind_window)
	_signals.window_deleted.disconnect(_on_window_deleted)
	_signals.desktop_ready.disconnect(_scan_desktop)
	_signals.setting_set.disconnect(_on_setting_set)
	_trackers.clear()
	_last_success.clear()
	_log.info("observer state=stopped")


func _exit_tree() -> void:
	stop()


func _scan_desktop() -> void:
	var desktop: Variant = _globals.desktop
	if not is_instance_valid(desktop) or not "windows" in desktop or not is_instance_valid(desktop.windows):
		return
	for child: Node in desktop.windows.get_children():
		_bind_window(child)


func _bind_window(window: Variant) -> void:
	if not is_instance_valid(window) or not window is Node or not "window" in window:
		return
	if not window.window in WATCHED_WINDOWS or not window.is_node_ready():
		return
	var id: int = window.get_instance_id()
	if _trackers.has(id) or _rejected.has(id):
		return
	var missing := ApiGuard.missing_breach_api(window)
	if not missing.is_empty():
		_rejected[id] = true
		_log.error("bind result=failed type=%s missing=%s" % [window.window, ",".join(missing)])
		return
	_trackers[id] = {"window": window, "type": window.window, "classifier": BreachClassifier.new(_starvation_ratio)}
	_log.info("bind result=ok type=%s level=%d max_level=%d" % [window.window, window.data.level, window.data.max_level])
	if _api_dump:
		_dump_api(window)


func _on_tick() -> void:
	for id: int in _trackers.keys():
		var tracker: Dictionary = _trackers[id]
		if not is_instance_valid(tracker.window):
			_drop_tracker(id, "window_freed")
			continue
		_report(tracker.window.window, tracker.classifier.observe(_sample(tracker.window)))
	if _trackers.is_empty():
		_ticks_since_scan += 1
		if _ticks_since_scan >= RESCAN_TICKS:
			_ticks_since_scan = 0
			_scan_desktop()


func _on_breached(window: Variant) -> void:
	if not is_instance_valid(window):
		return
	_bind_window(window)
	var tracker: Dictionary = _trackers.get(window.get_instance_id(), {})
	if not tracker.is_empty():
		_report(window.window, tracker.classifier.on_breached(_sample(window)))


func _on_window_deleted(window: Variant) -> void:
	if is_instance_valid(window):
		_drop_tracker(window.get_instance_id(), "window_deleted")


func _on_setting_set(setting: String) -> void:
	if setting == "auto_level_breach":
		_log.info("setting native_auto_level=%s" % _data.auto_level_breach)


func _drop_tracker(id: int, reason: String) -> void:
	var tracker: Dictionary = _trackers.get(id, {})
	if tracker.is_empty():
		return
	_trackers.erase(id)
	_report(tracker.type, tracker.classifier.invalidate(reason))


func _sample(window: Node) -> Dictionary:
	return {
		"instance_id": window.get_instance_id(),
		"level": int(window.data.level),
		"max_level": int(window.data.max_level),
		"time": window.time,
		"max_time": window.max_time,
		"detected": window.detected,
		"paused": window.paused,
		"firewall": window.firewall,
		"max_firewall": window.max_firewall,
		"breached": window.breached,
		"max_breach": window.max_breach,
		"damage_rate": window.breach_damage.production,
		"vulnerability": window.vulnerability.count,
		"tick_speed": _attributes.tick_speed,
		"now_usec": Time.get_ticks_usec(),
	}


func _report(type: String, events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		if event.event == "success":
			event.next_ratio = BreachPrediction.next_ratio(event.ratio, event.level)
			event.merge(BreachPrediction.volley_model(event))
		_log.info(_format(type, event))
		if event.event == "success":
			_check_prediction(type, event)


func _check_prediction(type: String, current: Dictionary) -> void:
	var previous: Dictionary = _last_success.get(type, {})
	_last_success[type] = current
	if previous.is_empty():
		return
	var reason := BreachPrediction.incomparable_reason(previous, current)
	if reason.is_empty():
		_log.info("prediction_check type=%s level=%d observed=%.4f coefficient=%.4f volleys=%.4f" % [type, current.level, current.ratio, previous.next_ratio, previous.get("next_model_ratio", -1.0)])
	else:
		_log.debug("prediction_check type=%s level=%d skipped=%s" % [type, current.level, reason])


func _format(type: String, event: Dictionary) -> String:
	var parts := PackedStringArray(["event=%s" % event.event, "type=%s" % type])
	for field: String in EVENT_FIELDS:
		if event.has(field):
			parts.append("%s=%s" % [field, _format_value(event[field])])
	return " ".join(parts)


func _format_value(value: Variant) -> String:
	if value is float and absf(value) < 1e9:
		return String.num(value, 3)
	return str(value)


func _dump_api(window: Node) -> void:
	var properties := PackedStringArray()
	for property: Dictionary in window.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			properties.append(property.name)
	var signal_names := PackedStringArray()
	for item: Dictionary in window.get_signal_list():
		signal_names.append(item.name)
	_log.info("api_dump type=%s properties=%s" % [window.window, ",".join(properties)])
	_log.info("api_dump type=%s signals=%s" % [window.window, ",".join(signal_names)])
