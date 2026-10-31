extends Node
## Connects the classifier to the game. Read-only: it never changes the threat level.

const ApiGuard := preload("../../core/api_guard.gd")
const SaLog := preload("../../core/sa_log.gd")
const BreachClassifier := preload("breach_classifier.gd")
const BreachPrediction := preload("breach_prediction.gd")
const BreachSimulator := preload("breach_simulator.gd")
const BreachForecast := preload("breach_forecast.gd")
const PowerProfile := preload("power_profile.gd")
const RegulationState := preload("regulation_state.gd")
const ThreatRegulator := preload("threat_regulator.gd")

const WATCHED_WINDOWS: Array[String] = ["breach_corps", "breach_government"]
const RESCAN_TICKS := 100
const DISTRIBUTION_REPORT_EVERY := 50
const RELIABILITY_REPORT_EVERY := 200
const SIMULATION_CACHE_SIZE := 64
const NATIVE_TOLERANCE := 1e-6
const HIT_TOLERANCE := 1.001
const EVENT_FIELDS: Array[String] = [
	"cycle_id", "level", "level_after", "from", "to", "max_level", "time_left", "used", "ratio", "next_ratio",
	"volleys", "min_hit", "max_hit", "expected_max_hit", "model_volleys", "model_volleys_worst", "next_volleys", "next_volleys_worst",
	"next_used", "next_max_time", "next_model_ratio", "next_model_ratio_worst",
	"sim_dist", "sim_p", "sim_next_volleys", "sim_next_dist", "sim_next_p", "sim_trusted", "sim_reasons", "next_source", "formula_ok", "native_matches",
	"max_time", "max_firewall", "max_breach", "damage_rate", "vulnerability", "breach_variation", "infection_variation",
	"infection_rate", "infection_offset", "interval", "tick_speed",
	"infection_start", "infection_end", "infection_integral", "dealt_total", "complete", "observed_start",
	"threshold", "progress_age", "clues", "reason", "steps", "max_step", "mean_step", "real_seconds", "trace",
]
const TRACED_EVENTS_PER_TYPE := 12
const FORECAST_TOLERANCE := 0.15
const FORECAST_CACHE_SIZE := 64
const SAVE_CANDIDATE := "(?i)save|slot|profile|file"
## Read-only getters called with one level argument; each is checked before use.
const NATIVE_GETTERS: Array[String] = ["get_max_firewall", "get_max_breach", "get_max_time", "is_elite"]
## Only reported as present or absent: this version must never call them.
const NATIVE_REPORTED: Array[String] = ["level_up", "level_down", "get_level", "get_max_level", "get_reward", "get_experience_reward"]

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
var _distributions: Dictionary = {}
var _reliability: Dictionary = {}
var _simulations: Dictionary = {}
var _stealth_mask := 0
var _ticks_since_scan := 0
var _last_tick_speed := -1.0
var _traced_events: Dictionary = {}
var _regulation: Dictionary = {"mode": "off", "profile": "balanced", "max_allowed_level": -1, "min_level": 0}
var _state: RegulationState = RegulationState.new()
var _regulators: Dictionary = {}
var _forecasts: Dictionary = {}
var _last_intervals: Dictionary = {}
var _last_signatures: Dictionary = {}
var _last_hold_reason: Dictionary = {}


## regulation.mode can only be off or dry_run: nothing in this version can apply a decision.
func configure(logger: SaLog, starvation_ratio: float, api_dump: bool, regulation: Dictionary = {}) -> void:
	_log = logger
	_starvation_ratio = starvation_ratio
	_api_dump = api_dump
	_regulation.merge(regulation, true)
	if _regulation.mode != "dry_run":
		_regulation.mode = "off"


func regulation_mode() -> String:
	return _regulation.mode


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
	_signals.desktop_ready.connect(_on_desktop_ready)
	_signals.setting_set.connect(_on_setting_set)
	_log.info("observer state=started native_auto_level=%s regulation_mode=%s profile=%s" % [_data.auto_level_breach, _regulation.mode, _regulation.profile])
	_log_inventory(root)
	_log_save_candidates()
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
	_signals.desktop_ready.disconnect(_on_desktop_ready)
	_signals.setting_set.disconnect(_on_setting_set)
	_log_regulators()
	for key: String in _distributions:
		_log_distribution(key)
	for type: String in _reliability:
		_log_reliability(type)
	_trackers.clear()
	_last_success.clear()
	_distributions.clear()
	_reliability.clear()
	_simulations.clear()
	_traced_events.clear()
	_last_tick_speed = -1.0
	_regulators.clear()
	_forecasts.clear()
	_last_hold_reason.clear()
	_log.info("observer state=stopped")


func _exit_tree() -> void:
	stop()


## A game was loaded. The slot is unknown, so ceilings must not follow the player into another save.
func _on_desktop_ready() -> void:
	_state.set_slot("")
	for regulator: ThreatRegulator in _regulators.values():
		regulator.set_ceiling(-1)
	_log_save_candidates()
	_scan_desktop()


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
	var signatures := _native_signatures(window)
	_trackers[id] = {
		"window": window,
		"type": window.window,
		"classifier": BreachClassifier.new(_starvation_ratio),
		"getters": _usable_getters(signatures),
	}
	_log.info("bind result=ok type=%s level=%d max_level=%d" % [window.window, window.data.level, window.data.max_level])
	_log_native_methods(window.window, signatures)
	if _api_dump:
		_dump_api(window)


func _on_tick() -> void:
	if _attributes.tick_speed != _last_tick_speed:
		_log.info("tick_speed from=%s to=%s" % [_format_value(_last_tick_speed), _format_value(_attributes.tick_speed)])
		_last_tick_speed = _attributes.tick_speed
	for regulator: ThreatRegulator in _regulators.values():
		regulator.advance(_attributes.tick_speed)
	for id: int in _trackers.keys():
		var tracker: Dictionary = _trackers[id]
		if not is_instance_valid(tracker.window):
			_drop_tracker(id, "window_freed")
			continue
		_report(tracker, tracker.classifier.observe(_sample(tracker.window)))
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
		_report(tracker, tracker.classifier.on_breached(_sample(window)))


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
	_report(tracker, tracker.classifier.invalidate(reason))


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
		"breach_variation": window.breach_damage.variation,
		"infection_count": window.infection_damage.count,
		"infection_rate": window.infection_damage.production,
		"infection_variation": window.infection_damage.variation,
		"vulnerability": window.vulnerability.count,
		"tick_speed": _attributes.tick_speed,
		"now_usec": Time.get_ticks_usec(),
	}


func _report(tracker: Dictionary, events: Array[Dictionary]) -> void:
	var type: String = tracker.type
	for event: Dictionary in events:
		_count_reliability(type, event.event)
		if event.event == "success":
			event.next_ratio = BreachPrediction.next_ratio(event.ratio, event.level)
			event.merge(BreachPrediction.volley_model(event))
			_add_simulation(tracker, event)
		elif event.event.begins_with("failure"):
			_compare_native(tracker, event)
		_limit_trace(type, event)
		_log.info(_format(type, event))
		if event.event == "success":
			_check_prediction(type, event)
			_record_distribution(type, event)
		if _regulation.mode == "dry_run":
			_simulate_regulation(tracker, event)


## Dry run: logs what the regulator would decide. Nothing here can change the game.
func _simulate_regulation(tracker: Dictionary, event: Dictionary) -> void:
	var type: String = tracker.type
	var regulator := _regulator_for(type)
	regulator.set_native(_data.auto_level_breach)
	regulator.note_event(event.event, event.get("clues", ""))
	if event.event == "level_changed" or event.event == "level_changed_reset":
		var level: int = event.get("to", event.get("level_after", -1))
		regulator.on_level_changed(level)
		if not _data.auto_level_breach:
			_state.apply_manual(type, level)
			regulator.set_ceiling(level)
			_log.info("manual_ceiling type=%s ceiling=%d scope=%s" % [type, level, "slot" if _state.is_persistent() else "session"])
		return
	if not event.has("max_firewall") or not is_instance_valid(tracker.window):
		return

	var profile := PowerProfile.from_event(event, _last_intervals.get(type, 0.0))
	if profile.interval > 0.0 and event.complete:
		_last_intervals[type] = profile.interval
	if _last_signatures.get(type, profile.signature) != profile.signature:
		_log.info("power_change type=%s from=%s to=%s" % [type, _last_signatures[type], profile.signature])
	_last_signatures[type] = profile.signature

	var current := {}
	var next := {"status": "invalid", "reasons": PackedStringArray(["no_native_values"])}
	var current_target := _native_values(tracker, event.level)
	if not current_target.is_empty():
		current = _forecast_for(profile, current_target, 0.0)
		_check_forecast(type, regulator, event, profile, current)
	var next_target := _native_values(tracker, event.level + 1)
	if not next_target.is_empty():
		next = _forecast_for(profile, next_target, regulator.margin())
	var decision := regulator.on_attack({
		"event": event.event, "complete": event.complete, "level": event.level,
		"max_level": event.max_level, "signature": profile.signature,
	}, current, next)
	_log_decision(type, decision, next)


func _regulator_for(type: String) -> ThreatRegulator:
	if not _regulators.has(type):
		var regulator := ThreatRegulator.new(_regulation.profile, _regulation.max_allowed_level, _regulation.min_level)
		regulator.set_ceiling(_state.ceiling(type))
		_regulators[type] = regulator
	return _regulators[type]


func _forecast_for(profile: Dictionary, target: Dictionary, margin: float) -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%s|%s|%s" % [profile.signature, profile.interval, profile.tick_speed, profile.infection_offset, target.firewall, target.breach, target.time, margin]
	if _forecasts.has(key):
		return _forecasts[key]
	if _forecasts.size() >= FORECAST_CACHE_SIZE:
		_forecasts.clear()
	var result := BreachForecast.forecast(profile, target, margin)
	_forecasts[key] = result
	return result


## Compares what happened with what the forecast allowed. Anything outside is signaled for analysis.
func _check_forecast(type: String, regulator: ThreatRegulator, event: Dictionary, profile: Dictionary, current: Dictionary) -> void:
	if not event.complete or current.status == "invalid":
		return
	if event.event != "success" and event.event != "failure_power":
		return
	var in_range: bool
	var observed: String
	if event.event == "success":
		observed = _format_value(event.used)
		in_range = current.used_min >= 0.0 and event.used >= current.used_min - FORECAST_TOLERANCE
		if current.used_max >= 0.0:
			in_range = in_range and event.used <= current.used_max + FORECAST_TOLERANCE
		elif not current.may_fail:
			in_range = false
	else:
		observed = "failed"
		in_range = current.may_fail
	if PowerProfile.has_infection(profile):
		regulator.note_forecast_check(in_range)
	if not in_range:
		_log.info("forecast_check type=%s level=%d result=out_of_range observed=%s used_min=%s used_max=%s may_fail=%s infection_offset=%s trust=%s" % [type, event.level, observed, _format_value(current.used_min), _format_value(current.used_max), current.may_fail, _format_value(event.get("infection_offset", -1.0)), regulator.model_trust()])
	else:
		_log.debug("forecast_check type=%s level=%d result=in_range observed=%s" % [type, event.level, observed])


## Raises and lowers are always logged; a hold only when its reason changes.
func _log_decision(type: String, decision: Dictionary, next: Dictionary) -> void:
	if decision.decision == "hold":
		if _last_hold_reason.get(type, "") == decision.reason:
			return
		_last_hold_reason[type] = decision.reason
	else:
		_last_hold_reason[type] = ""
	var parts := PackedStringArray(["dry_run", "type=%s" % type])
	for key: String in decision:
		parts.append("%s=%s" % [key, _format_value(decision[key])])
	parts.append("next_status=%s" % next.get("status", "none"))
	parts.append("next_outcome=%s" % next.get("outcome", "none"))
	parts.append("next_p=%s" % _format_value(next.get("p_success", -1.0)))
	parts.append("next_used_max=%s" % _format_value(next.get("used_max", -1.0)))
	_log.info(" ".join(parts))


func _log_regulators() -> void:
	for type: String in _regulators:
		var regulator: ThreatRegulator = _regulators[type]
		_log.info("regulator_summary type=%s profile=%s repeats_suppressed=%d model_trust=%s unsafe=%s ceiling=%d" % [type, regulator.profile_name, regulator.suppressed_repeats, regulator.model_trust(), regulator.is_unsafe(), _state.ceiling(type)])


## Looks for what could identify a save slot. Only names and simple values are read.
func _log_save_candidates() -> void:
	var pattern := RegEx.create_from_string(SAVE_CANDIDATE)
	for node: Node in [_data, _globals]:
		var found := PackedStringArray()
		for property: Dictionary in node.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and pattern.search(property.name) != null:
				var value: Variant = node.get(property.name)
				var shown: String = str(value).left(40) if value is String or value is int or value is float or value is bool else type_string(typeof(value))
				found.append("%s=%s" % [property.name, shown])
		_log.info("inventory save_candidates node=%s %s" % [node.name, " ".join(found)])


## Traces are long, so only the first attacks of each type keep theirs.
func _limit_trace(type: String, event: Dictionary) -> void:
	if not event.has("trace"):
		return
	_traced_events[type] = _traced_events.get(type, 0) + 1
	if _traced_events[type] > TRACED_EVENTS_PER_TYPE:
		event.erase("trace")


func _compare_native(tracker: Dictionary, event: Dictionary) -> void:
	if not is_instance_valid(tracker.window):
		return
	var current := _native_values(tracker, event.level)
	if not current.is_empty():
		event.native_matches = _matches(current.firewall, event.max_firewall) and _matches(current.breach, event.max_breach) and _matches(current.time, event.max_time)


func _add_simulation(tracker: Dictionary, event: Dictionary) -> void:
	if not is_instance_valid(tracker.window):
		return
	_compare_native(tracker, event)
	if not event.complete or event.volleys < 2 or event.damage_rate <= 0.0:
		return

	var interval: float = event.used / (event.volleys - 1)
	var base_hit: float = event.damage_rate * interval
	var bonus: float = 1.0 + event.vulnerability
	var stealth: bool = _stealth_mask != 0 and (event.get("breach_variation", 0) & _stealth_mask) != 0
	event.expected_max_hit = ceilf(base_hit) * bonus

	var hp := BreachPrediction.hp_factor(event.level)
	var formula := {
		"firewall": event.max_firewall * hp,
		"breach": event.max_breach * hp,
		"time": event.max_time * hp / BreachPrediction.ratio_factor(event.level),
	}
	var next := _native_values(tracker, event.level + 1)
	event.next_source = "native" if not next.is_empty() else "formula"
	if next.is_empty():
		next = formula
	else:
		event.formula_ok = absf(formula.firewall + formula.breach - next.firewall - next.breach) <= 1.0 and _matches(formula.time, next.time)

	var now := _simulate(event.max_firewall, event.max_breach, event.max_time, interval, base_hit, bonus, stealth)
	var after := _simulate(next.firewall, next.breach, next.time, interval, base_hit, bonus, stealth)
	if not now.ok or not after.ok:
		return
	event.sim_dist = BreachSimulator.format_distribution(now.distribution)
	event.sim_p = now.p_success
	event.sim_next_dist = BreachSimulator.format_distribution(after.distribution)
	event.sim_next_p = after.p_success
	event.sim_next_volleys = "%d-%d" % [after.best, after.worst]
	var reasons := _untrusted_reasons(event, now, after, stealth, floorf(base_hit) * bonus)
	event.sim_trusted = reasons.is_empty()
	if not reasons.is_empty():
		event.sim_reasons = ",".join(reasons)


## Why the simulation should not be believed for this attack. Nothing acts on this yet.
func _untrusted_reasons(event: Dictionary, now: Dictionary, after: Dictionary, stealth: bool, lowest_hit: float) -> PackedStringArray:
	var reasons := PackedStringArray()
	if event.has("infection_integral") and event.infection_integral > 0.0:
		reasons.append("infection")
	if stealth:
		reasons.append("stealth")
	if now.low_hit:
		reasons.append("low_hit")
	if now.truncated:
		reasons.append("truncated")
	if after.truncated:
		reasons.append("next_truncated")
	if not now.distribution.has(event.volleys):
		reasons.append("volleys_out_of_range")
	if event.has("max_hit") and not event.has("infection_integral"):
		if event.max_hit > event.expected_max_hit * HIT_TOLERANCE:
			reasons.append("hit_above_model")
		if event.min_hit * HIT_TOLERANCE < lowest_hit:
			reasons.append("hit_below_model")
	return reasons


func _simulate(firewall: float, breach: float, max_time: float, interval: float, base_hit: float, bonus: float, stealth: bool) -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%s|%s" % [firewall, breach, max_time, interval, base_hit, bonus, stealth]
	if _simulations.has(key):
		return _simulations[key]
	if _simulations.size() >= SIMULATION_CACHE_SIZE:
		_simulations.clear()
	var result := BreachSimulator.simulate(firewall, breach, max_time, interval, base_hit, bonus, stealth)
	_simulations[key] = result
	return result


func _check_prediction(type: String, current: Dictionary) -> void:
	var previous: Dictionary = _last_success.get(type, {})
	_last_success[type] = current
	if previous.is_empty():
		return
	var reason := BreachPrediction.incomparable_reason(previous, current)
	if reason.is_empty():
		_log.info("prediction_check type=%s level=%d observed=%.4f coefficient=%.4f volleys=%.4f sim_next_p=%s sim_next_dist=%s" % [type, current.level, current.ratio, previous.next_ratio, previous.get("next_model_ratio", -1.0), previous.get("sim_next_p", "none"), previous.get("sim_next_dist", "none")])
	else:
		_log.debug("prediction_check type=%s level=%d skipped=%s" % [type, current.level, reason])


## Compares the volleys seen with the simulation, grouped by identical conditions.
func _record_distribution(type: String, event: Dictionary) -> void:
	if not event.complete or not event.has("sim_dist"):
		return
	var key := "%s|%d|%s|%s" % [type, event.level, event.damage_rate, event.max_time]
	if not _distributions.has(key):
		_distributions[key] = {"type": type, "level": event.level, "damage_rate": event.damage_rate, "max_time": event.max_time, "sim": event.sim_dist, "counts": {}, "total": 0}
	var entry: Dictionary = _distributions[key]
	entry.counts[event.volleys] = entry.counts.get(event.volleys, 0) + 1
	entry.total += 1
	if entry.total % DISTRIBUTION_REPORT_EVERY == 0:
		_log_distribution(key)


func _log_distribution(key: String) -> void:
	var entry: Dictionary = _distributions[key]
	_log.info("distribution_check type=%s level=%d damage_rate=%s max_time=%s n=%d observed=%s sim=%s" % [entry.type, entry.level, _format_value(entry.damage_rate), _format_value(entry.max_time), entry.total, JSON.stringify(entry.counts), entry.sim])


func _count_reliability(type: String, event_name: String) -> void:
	if not _reliability.has(type):
		_reliability[type] = {"total": 0, "counts": {}}
	var entry: Dictionary = _reliability[type]
	entry.counts[event_name] = entry.counts.get(event_name, 0) + 1
	entry.total += 1
	if entry.total % RELIABILITY_REPORT_EVERY == 0:
		_log_reliability(type)


func _log_reliability(type: String) -> void:
	var entry: Dictionary = _reliability[type]
	_log.info("reliability_check type=%s total=%d counts=%s" % [type, entry.total, JSON.stringify(entry.counts)])


## Name to argument count for every method of the window's script and its base scripts.
func _native_signatures(window: Node) -> Dictionary:
	var signatures := {}
	var script: Script = window.get_script()
	while script != null:
		for method: Dictionary in script.get_script_method_list():
			if not signatures.has(method.name):
				signatures[method.name] = method.args.size()
		script = script.get_base_script()
	return signatures


func _usable_getters(signatures: Dictionary) -> Dictionary:
	var usable := {}
	for getter: String in NATIVE_GETTERS:
		usable[getter] = signatures.get(getter, -1) == 1
	return usable


## Exact values of a level according to the game. Returns {} unless every getter is usable.
func _native_values(tracker: Dictionary, level: int) -> Dictionary:
	if tracker.getters.values().has(false):
		return {}
	var window: Node = tracker.window
	var firewall: Variant = window.get_max_firewall(level)
	var breach: Variant = window.get_max_breach(level)
	var time: Variant = window.get_max_time(level)
	if not (firewall is float or firewall is int) or not (breach is float or breach is int) or not (time is float or time is int):
		return {}
	return {"firewall": float(firewall), "breach": float(breach), "time": float(time), "elite": window.is_elite(level)}


func _matches(a: float, b: float) -> bool:
	return absf(a - b) <= NATIVE_TOLERANCE * maxf(1.0, absf(b))


func _log_native_methods(type: String, signatures: Dictionary) -> void:
	var found := PackedStringArray()
	var absent := PackedStringArray()
	for method: String in NATIVE_GETTERS + NATIVE_REPORTED:
		if signatures.has(method):
			found.append("%s/%d" % [method, signatures[method]])
		else:
			absent.append(method)
	_log.info("native_methods type=%s present=%s absent=%s" % [type, ",".join(found), ",".join(absent)])


## Reports what the player can use, to know which measurements are possible in this save.
func _log_inventory(root: Node) -> void:
	var utils := root.get_node_or_null("Utils")
	if utils != null and utils.get_script() != null:
		var constants: Dictionary = utils.get_script().get_script_constant_map()
		var variations: Variant = constants.get("damage_variation")
		if variations is Dictionary:
			_stealth_mask = variations.get("STEALTH", 0)
			_log.info("inventory damage_variation=%s" % JSON.stringify(variations))
	if "unlocks" in _globals and _globals.unlocks is Dictionary:
		var research := PackedStringArray()
		for key: String in ["research.infection_damage", "research.injection", "research.hacking"]:
			research.append("%s=%s" % [key, _globals.unlocks.get(key, "absent")])
		_log.info("inventory %s" % " ".join(research))
	if not "windows" in _data or not _data.windows is Dictionary:
		return
	var unlocked: Variant = _globals.unlock_tracker.get("windows") if "unlock_tracker" in _globals and _globals.unlock_tracker is Dictionary else null
	var hacking := PackedStringArray()
	for key: String in _data.windows:
		var definition: Variant = _data.windows[key]
		if definition is Dictionary and definition.get("category") == "hacking":
			var is_unlocked: Variant = unlocked.has(key) if unlocked != null else "unknown"
			hacking.append("%s:%s:%s" % [key, is_unlocked, definition.get("requirement", [])])
	_log.info("inventory hacking_windows=%s" % ";".join(hacking))


func _format(type: String, event: Dictionary) -> String:
	var parts := PackedStringArray(["event=%s" % event.event, "type=%s" % type])
	for field: String in EVENT_FIELDS:
		if event.has(field):
			parts.append("%s=%s" % [field, _format_value(event[field])])
	return " ".join(parts)


func _format_value(value: Variant) -> String:
	if value is float and absf(value) < 1e9:
		return String.num(value, 4)
	return str(value)


func _dump_api(window: Node) -> void:
	var properties := PackedStringArray()
	for property: Dictionary in window.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			properties.append(property.name)
	var signal_names := PackedStringArray()
	for item: Dictionary in window.get_signal_list():
		signal_names.append(item.name)
	var methods := PackedStringArray()
	for method: String in _native_signatures(window):
		methods.append(method)
	_log.info("api_dump type=%s properties=%s" % [window.window, ",".join(properties)])
	_log.info("api_dump type=%s signals=%s" % [window.window, ",".join(signal_names)])
	_log.info("api_dump type=%s methods=%s" % [window.window, ",".join(methods)])
