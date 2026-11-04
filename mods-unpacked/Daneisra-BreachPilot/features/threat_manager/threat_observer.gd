extends Node
## Connects the classifier to the game. It reads the game: only threat_actuator.gd can change a threat
## level, in the active mode.

const ApiGuard := preload("../../core/api_guard.gd")
const SaLog := preload("../../core/sa_log.gd")
const I18n := preload("../../core/i18n.gd")
const BreachClassifier := preload("breach_classifier.gd")
const BreachPrediction := preload("breach_prediction.gd")
const BreachSimulator := preload("breach_simulator.gd")
const BreachForecast := preload("breach_forecast.gd")
const PowerProfile := preload("power_profile.gd")
const RegulationState := preload("regulation_state.gd")
const ThreatRegulator := preload("threat_regulator.gd")
const GapProbe := preload("gap_probe.gd")
const GapStats := preload("gap_stats.gd")
const ThreatActuator := preload("threat_actuator.gd")
const AutomationControl := preload("automation_control.gd")
const LevelChoice := preload("level_choice.gd")
const HitLog := preload("../hacking_advisor/hit_log.gd")
const HackingGraph := preload("../hacking_advisor/hacking_graph.gd")
const HackingModel := preload("../hacking_advisor/hacking_model.gd")

## From this chance, measured on the hits really seen, a level is worth a real try. Below, a try only costs attacks.
const TRIAL_CHANCE := 0.3

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
	"infection_start", "infection_end", "infection_integral", "infection_growth", "infection_pulses", "infection_gain", "dealt_total", "complete", "observed_start",
	"threshold", "progress_age", "clues", "reason", "steps", "max_step", "mean_step", "real_seconds", "outputs", "trace",
]
## The slots an attack feeds: its own damage inputs are left out.
const ATTACK_SLOTS: Array[String] = ["breach_damage", "infection_damage", "vulnerability"]
const TRACED_EVENTS_PER_TYPE := 12
const FORECAST_TOLERANCE := 0.15
const FORECAST_CACHE_SIZE := 64
const SAVE_CANDIDATE := "(?i)save|slot|profile|file"
const SAVE_NODES_LOGGED := 12
## Read-only getters called with one level argument; each is checked before use.
## A plain level, to read what targets demand whatever level they hold.
const REFERENCE_LEVEL := 1
const NATIVE_GETTERS: Array[String] = ["get_max_firewall", "get_max_breach", "get_max_time", "is_elite"]
## What a level pays, read the same way. Without them the regulation keeps aiming at the highest level.
const REWARD_GETTERS: Array[String] = ["get_reward", "get_experience_reward"]
## Only reported as present or absent: this version must never call them.
const NATIVE_REPORTED: Array[String] = ["level_up", "level_down", "get_level", "get_max_level"]
## Blocks with their own words, as block.<reason>; any other is an anomaly, named by its reason.
const BLOCK_TEXTS: Array[String] = ["emergency_stop", "native_option", "speed", "native_methods", "classifier"]
## Far from what the game should use, so these hooks run first and last among the frame's _process.
const HOOK_PRIORITY := 1000000
const PROBE_REPORT_FRAMES := 18000


## Samples the windows at one point of the frame.
class FrameHook extends Node:
	var hook: String
	var target: Callable

	func _process(_delta: float) -> void:
		target.call(hook)


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
var _actuator: ThreatActuator
var _emergency := false
## An anomaly lasts until the game restarts: restarting the observer must not clear it.
var _session_halt := ""
var _last_refusal: Dictionary = {}
var _tick_index := 0
var _state: RegulationState = RegulationState.new()
var _regulators: Dictionary = {}
var _forecasts: Dictionary = {}
var _last_intervals: Dictionary = {}
var _observed_hits: Dictionary = {}
var _level_scans: Dictionary = {}
var _last_signatures: Dictionary = {}
var _last_hold_reason: Dictionary = {}
var _hit_log: HitLog = HitLog.new()
var _advice_action := Callable()
## The objective chosen in the panel: the regulation aims at the level that brings the most for it.
var _objective := LevelChoice.BALANCED
## Per type: each level's chance and rewards at the current power, measured one level a tick.
var _profit_tables: Dictionary = {}
var _last_choice: Dictionary = {}
var _gap_probe := false
var _gap_stats: GapStats
var _hooks: Array[FrameHook] = []
var _probe_hook := "F"
var _probe_frame_hook := "start"
var _probe_tick := 0
var _probe_frames := 0
var _probe_samples := 0
var _probe_cost_total := 0
var _probe_cost_max := 0
var _probe_last_frame_usec := 0
var _probe_longest_frame := 0
var _probe_ticks_after: Dictionary = {}
var _probe_tick_frame := -1
var _probe_ticks_this_frame := 0
var _probe_ticks_per_frame_max := 0


func _new_actuator(armed: bool) -> ThreatActuator:
	return ThreatActuator.new(armed, {"attributes": _attributes, "data": _data}, {
		"min_level": _regulation.min_level, "max_allowed": _regulation.max_allowed_level,
	})


## The attack interval last seen for each type: the advisor has no other way to know it.
func attack_intervals() -> Dictionary:
	return _last_intervals


## What attacks really did, by chain. It survives restarting the observer, like the player's chain.
func hit_log() -> HitLog:
	return _hit_log


## The game's own bit for stealth damage, 0 when it does not say.
func stealth_mask() -> int:
	return _stealth_mask


## Set before start: the nodes then get a button for it.
func set_advice_action(action: Callable) -> void:
	_advice_action = action


## regulation.mode is off, dry_run or active. Anything else means off: nothing acts by accident.
func set_objective(objective: String) -> void:
	if objective != _objective:
		_objective = objective
		_log.info("objective_selected objective=%s" % objective)


func configure(logger: SaLog, starvation_ratio: float, api_dump: bool, regulation: Dictionary = {}, gap_probe: bool = false) -> void:
	_log = logger
	_starvation_ratio = starvation_ratio
	_api_dump = api_dump
	_gap_probe = gap_probe
	_regulation.merge(regulation, true)
	# 0 or less is no limit, whoever passes the value: a cap at level 0 would send every node down.
	if int(_regulation.max_allowed_level) <= 0:
		_regulation.max_allowed_level = -1
	if not _regulation.mode in ["off", "dry_run", "active"]:
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
	if _regulation.mode != "off":
		_actuator = _new_actuator(_regulation.mode == "active")
		if _emergency:
			_actuator.halt("emergency_stop")
		elif not _session_halt.is_empty():
			_actuator.halt(_session_halt)
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
	_log_undo_candidates(root)
	if _gap_probe:
		_start_probe()
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
	_stop_probe()
	_detach_controls()
	if _actuator != null:
		_log.info(_actuator.summary())
		if not _actuator.halt_reason.is_empty():
			_session_halt = _actuator.halt_reason
		_actuator = null
	_last_refusal.clear()
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


## A game was loaded. Pauses stay: only the player's click ends one.
func _on_desktop_ready() -> void:
	if _actuator != null:
		for type: String in _regulators:
			_cancel_action(type, "game_loaded")
		_log_verification(_actuator.on_reload())
		_log_new_halt()
		for regulator: ThreatRegulator in _regulators.values():
			regulator.on_game_loaded()
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
	# A target is known by what it exposes: any attack node qualifies, whatever its name.
	if not ApiGuard.is_breach_like(window) or not window.is_node_ready():
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
		"native_usable": signatures.get("level_up", -1) == 1 and signatures.get("level_down", -1) == 1,
		"reward_getters": REWARD_GETTERS.all(func(getter: String) -> bool: return signatures.get(getter, -1) == 1),
	}
	_log_native_actions(window)
	_attach_control(_trackers[id])
	if _gap_stats != null:
		_trackers[id].probe = GapProbe.new()
		_trackers[id].screen_fields = "out_of_screen" in window and "is_far" in window
		_log.info("gap_probe_bound type=%s process_priority=%d hook_priority=%d" % [window.window, window.process_priority, HOOK_PRIORITY])
	_log.info("bind result=ok type=%s level=%d max_level=%d" % [window.window, window.data.level, window.data.max_level])
	_log_native_methods(window.window, signatures)
	if _api_dump:
		_dump_api(window)


func _on_tick() -> void:
	if _attributes.tick_speed != _last_tick_speed:
		_log.info("tick_speed from=%s to=%s" % [_format_value(_last_tick_speed), _format_value(_attributes.tick_speed)])
		var speed_moved := _last_tick_speed >= 0.0
		_last_tick_speed = _attributes.tick_speed
		if speed_moved:
			_on_speed_changed()
	for regulator: ThreatRegulator in _regulators.values():
		regulator.advance(_attributes.tick_speed)
	_tick_index += 1
	if _actuator != null:
		_log_verification(_actuator.advance(_attributes.tick_speed))
		_log_new_halt()
	if _gap_stats != null:
		_note_probe_tick()
	_advance_profit_tables()
	for id: int in _trackers.keys():
		var tracker: Dictionary = _trackers[id]
		if not is_instance_valid(tracker.window):
			_drop_tracker(id, "window_freed")
			continue
		if _gap_stats != null:
			_probe_at("T", tracker)
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
		if _gap_stats != null:
			_probe_at("B", tracker)
			_probe_deferred.call_deferred(window.get_instance_id())
		_report(tracker, tracker.classifier.on_breached(_sample(window)))


func _on_window_deleted(window: Variant) -> void:
	if is_instance_valid(window):
		_drop_tracker(window.get_instance_id(), "window_deleted")


func _on_setting_set(setting: String) -> void:
	if setting == "auto_level_breach":
		_log.info("setting native_auto_level=%s" % _data.auto_level_breach)
		_refresh_controls()


func _drop_tracker(id: int, reason: String) -> void:
	var tracker: Dictionary = _trackers.get(id, {})
	if tracker.is_empty():
		return
	_trackers.erase(id)
	if reason == "window_deleted" and _actuator != null and _level_of_type(tracker.type) < 0:
		_cancel_action(tracker.type, reason)
		_log_verification(_actuator.on_window_removed(tracker.type))
	_report(tracker, tracker.classifier.invalidate(reason))
	if _gap_stats != null:
		_finish_probe(tracker)


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
		if _gap_stats != null:
			_probe_result(tracker, event)
		_count_reliability(type, event.event)
		if event.event == "success":
			event.outputs = _outputs(tracker.window)
			event.next_ratio = BreachPrediction.next_ratio(event.ratio, event.level)
			event.merge(BreachPrediction.volley_model(event))
			_add_simulation(tracker, event)
		elif event.event.begins_with("failure"):
			_compare_native(tracker, event)
		_limit_trace(type, event)
		_log.info(_format(type, event))
		_note_hits(tracker, event)
		if event.event == "success":
			_check_prediction(type, event)
			_record_distribution(type, event)
		if _regulation.mode != "off":
			_regulate(tracker, event)


## The chain is read again at each attack: a rewired node must not mix with the measures of the old chain.
func _note_hits(tracker: Dictionary, event: Dictionary) -> void:
	if not event.get("complete", false) or not event.event in ["success", "failure_power"] or not is_instance_valid(tracker.window):
		return
	var graph := HackingGraph.snapshot(_globals.desktop)
	tracker.chain_key = HackingGraph.chain_key(graph, tracker.window, _attributes)
	tracker.infection_key = HackingGraph.chain_key(graph, tracker.window, _attributes, HackingGraph.INFECTION_SLOT)
	_hit_log.add(tracker.type, tracker.chain_key, event, tracker.infection_key)


func _start_probe() -> void:
	_gap_stats = GapStats.new()
	_probe_tick = 0
	_probe_frames = 0
	_probe_samples = 0
	_probe_cost_total = 0
	_probe_cost_max = 0
	_probe_last_frame_usec = 0
	_probe_longest_frame = 0
	_probe_ticks_after = {}
	_probe_ticks_per_frame_max = 0
	_probe_frame_hook = "start"
	for entry: Array in [["F", -HOOK_PRIORITY], ["L", HOOK_PRIORITY]]:
		var hook := FrameHook.new()
		hook.name = "GapHook%s" % entry[0]
		hook.hook = entry[0]
		hook.target = _on_frame_hook
		hook.process_priority = entry[1]
		add_child(hook)
		_hooks.append(hook)
	_log.info("gap_probe state=started")


func _stop_probe() -> void:
	if _gap_stats == null:
		return
	for hook: FrameHook in _hooks:
		hook.queue_free()
	_hooks.clear()
	for tracker: Dictionary in _trackers.values():
		_finish_probe(tracker)
	_log_probe_summary()
	_gap_stats = null
	_log.info("gap_probe state=stopped")


## Runs twice per frame: nothing is logged here except rare, bounded reports.
func _on_frame_hook(hook: String) -> void:
	var started := Time.get_ticks_usec()
	if hook == "F":
		_probe_frames += 1
		if _probe_last_frame_usec > 0:
			_probe_longest_frame = maxi(_probe_longest_frame, started - _probe_last_frame_usec)
		_probe_last_frame_usec = started
	_probe_hook = hook
	_probe_frame_hook = hook
	for tracker: Dictionary in _trackers.values():
		if is_instance_valid(tracker.window):
			_probe_collect(tracker.type, tracker.probe.feed(_probe_sample(tracker)))
	if hook == "L":
		_note_common_windows()
	_add_probe_cost(started)
	if hook == "L" and _probe_frames % PROBE_REPORT_FRAMES == 0:
		_log_probe_cost()


func _note_probe_tick() -> void:
	_probe_tick += 1
	_probe_ticks_after[_probe_frame_hook] = _probe_ticks_after.get(_probe_frame_hook, 0) + 1
	var frame := Engine.get_process_frames()
	_probe_ticks_this_frame = _probe_ticks_this_frame + 1 if frame == _probe_tick_frame else 1
	_probe_tick_frame = frame
	_probe_ticks_per_frame_max = maxi(_probe_ticks_per_frame_max, _probe_ticks_this_frame)


func _probe_at(hook: String, tracker: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	_probe_hook = hook
	_probe_collect(tracker.type, tracker.probe.feed(_probe_sample(tracker)))
	_add_probe_cost(started)


## An observation point after the breached signal. It is not a guarantee of anything by itself.
func _probe_deferred(id: int) -> void:
	var tracker: Dictionary = _trackers.get(id, {})
	if _gap_stats != null and not tracker.is_empty() and is_instance_valid(tracker.window):
		_probe_at("D", tracker)


func _probe_result(tracker: Dictionary, event: Dictionary) -> void:
	var stamp := {"hook": _probe_hook, "usec": Time.get_ticks_usec(), "frame": Engine.get_process_frames(), "tick": _probe_tick}
	_probe_collect(tracker.type, tracker.probe.note_result(event.event, stamp, event))


func _finish_probe(tracker: Dictionary) -> void:
	_probe_collect(tracker.type, tracker.probe.finish())
	_gap_stats.add_changes(tracker.type, tracker.probe.take_changes())
	if tracker.probe.results_unmatched > 0 or tracker.probe.gaps_interrupted > 0:
		_log.info("gap_probe_finished type=%s results_unmatched=%d gaps_interrupted=%d" % [tracker.type, tracker.probe.results_unmatched, tracker.probe.gaps_interrupted])


func _probe_sample(tracker: Dictionary) -> Dictionary:
	var window: Node = tracker.window
	return {
		"hook": _probe_hook,
		"usec": Time.get_ticks_usec(),
		"frame": Engine.get_process_frames(),
		"tick": _probe_tick,
		"detected": window.detected,
		"paused": window.paused,
		"time": window.time,
		"max_time": window.max_time,
		"firewall": window.firewall,
		"max_firewall": window.max_firewall,
		"breached": window.breached,
		"infection_count": window.infection_damage.count,
		"level": int(window.data.level),
		"tick_speed": _attributes.tick_speed,
		"damage_rate": window.breach_damage.production,
		"infection_rate": window.infection_damage.production,
		"offscreen": tracker.screen_fields and (window.out_of_screen or window.is_far),
		"native": _data.auto_level_breach,
	}


func _probe_collect(type: String, records: Array[Dictionary]) -> void:
	_probe_samples += 1
	for record: Dictionary in records:
		if record.kind == "level_change":
			_log_level_change(type, record)
			continue
		var outcome := _gap_stats.add(type, record)
		if outcome.sequence:
			_log_gap_sequence(type, record)
		if not outcome.report.is_empty():
			_log.info(_gap_stats.case_line(outcome.report))


func _note_common_windows() -> void:
	if _trackers.size() < 2:
		return
	var groups := {}
	for tracker: Dictionary in _trackers.values():
		if not is_instance_valid(tracker.window):
			continue
		var group: Array = groups.get(tracker.type, [0, true])
		group[0] += 1
		group[1] = group[1] and tracker.probe.is_available()
		groups[tracker.type] = group
	for type: String in groups:
		if groups[type][0] >= 2:
			_gap_stats.note_common(type, groups[type][0], groups[type][1])


func _add_probe_cost(started: int) -> void:
	var cost := Time.get_ticks_usec() - started
	_probe_cost_total += cost
	_probe_cost_max = maxi(_probe_cost_max, cost)


func _log_probe_cost() -> void:
	var frames := maxi(_probe_frames, 1)
	var per_frame := float(_probe_cost_total) / frames
	var mean_frame := 1000000.0 / maxf(Engine.get_frames_per_second(), 1.0)
	_log.info("gap_cost frames=%d samples=%d mean_us_per_frame=%.1f max_us=%d share_of_frame=%.3f%% fps=%.0f longest_frame_ms=%.1f ticks=%d ticks_after=%s ticks_per_frame_max=%d" % [_probe_frames, _probe_samples, per_frame, _probe_cost_max, per_frame / mean_frame * 100.0, Engine.get_frames_per_second(), _probe_longest_frame / 1000.0, _probe_tick, JSON.stringify(_probe_ticks_after), _probe_ticks_per_frame_max])


func _log_probe_summary() -> void:
	_log_probe_cost()
	for line: String in _gap_stats.summary_lines():
		_log.info(line)


func _log_gap_sequence(type: String, record: Dictionary) -> void:
	var origin: Dictionary = record.last_attack
	var parts := PackedStringArray(["gap_sequence", "type=%s" % type, "result=%s" % record.case_result, "level=%d" % record.level, "tick_speed=%s" % _format_value(record.tick_speed)])
	for field: String in ["known", "idle", "available", "start", "detected", "damage", "pile"]:
		var stamp: Dictionary = record[field]
		if stamp.is_empty():
			parts.append("%s=none" % field)
		else:
			parts.append("%s=%s:%dus:%df:%dt" % [field, stamp.hook, stamp.usec - origin.usec, stamp.frame - origin.frame, stamp.tick - origin.tick])
	for field: String in ["time_end", "time_idle", "max_time", "firewall_idle", "breached_idle", "pile_end", "pile_idle", "armed_at_idle", "no_window", "raw_us", "usable_us", "uncertainty_us", "start_sign"]:
		parts.append("%s=%s" % [field, _format_value(record[field])])
	_log.info(" ".join(parts))


func _log_level_change(type: String, record: Dictionary) -> void:
	var parts := PackedStringArray(["gap_level_change", "type=%s" % type])
	for field: String in record:
		if field != "kind" and field != "usec":
			parts.append("%s=%s" % [field, _format_value(record[field])])
	_log.info(" ".join(parts))


## Logs what the regulator decides and hands it to the actuator, which in this build only tells what
## it would have done.
func _regulate(tracker: Dictionary, event: Dictionary) -> void:
	var type: String = tracker.type
	var regulator := _regulator_for(type)
	regulator.set_native(_data.auto_level_breach)
	regulator.note_event(event.event, event.get("clues", ""))
	var is_level_event: bool = event.event == "level_changed" or event.event == "level_changed_reset"
	var level: int = event.get("to", event.get("level_after", -1))
	var claimed: bool = is_level_event and _actuator.claims_level_change(type, level)
	_log_verification(_actuator.note_event(type, event, claimed))
	_log_new_halt()
	if is_level_event:
		regulator.on_level_changed(level)
		if claimed:
			_log.info("level_origin type=%s level=%d origin=mod" % [type, level])
			return
		_cancel_action(type, "level_changed_by_other")
		if _data.auto_level_breach:
			_log.info("level_origin type=%s level=%d origin=native" % [type, level])
		else:
			_log.info("level_origin type=%s level=%d origin=player" % [type, level])
			_pause_automation(type, "player_level_change", level)
		return
	if not event.has("max_firewall") or not is_instance_valid(tracker.window):
		return

	var profile := PowerProfile.from_event(event, _last_intervals.get(type, 0.0))
	profile.signature = _with_target_rules(tracker, profile.signature)
	if profile.interval > 0.0 and event.complete:
		_last_intervals[type] = profile.interval
	_apply_observed_hits(type, event, profile)
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
	regulator.set_action_busy(_actuator.is_busy())
	var attack := {
		"event": event.event, "complete": event.complete, "level": event.level,
		"max_level": event.max_level, "signature": profile.signature,
	}
	var choice := _profit_choice(tracker, profile, regulator, event) if event.complete else {}
	if event.complete and event.event == "success" and not choice.is_empty():
		attack.profitable_level = choice.profitable
		attack.unlock_level = choice.unlock
		attack.unlock_chance = choice.get("unlock_chance", 0.0)
	elif event.complete and event.event == "success":
		var best := _best_raise(tracker, profile, regulator, event)
		if best > event.level:
			attack.best_level = best
			attack.best_forecast = _forecast_for(profile, _native_values(tracker, best), regulator.margin())
		else:
			attack.probe_possible = _may_work(tracker, profile, event)
	elif event.complete and event.event == "failure_power":
		var profitable: int = choice.get("profitable", -1)
		attack.target_down = profitable if profitable >= 0 and profitable < event.level else _best_lower(tracker, profile, regulator, event)
	var decision := regulator.on_attack(attack, current, next)
	var assumed := next
	if decision.decision != "hold":
		var aimed := _native_values(tracker, decision.assumed_level)
		# The margin is a caution against going up: without it, this says whether a lower level works.
		assumed = {} if aimed.is_empty() else _forecast_for(profile, aimed, regulator.margin() if decision.decision == "raise" else 0.0)
		# A try has no promise to keep, and without a hit seen the durations would rest on the announced figure.
		if decision.get("probe", false) or profile.get("hits_unseen", false):
			assumed = {"status": assumed.get("status", "none"), "outcome": assumed.get("outcome", "none"), "p_success": assumed.get("p_success", -1.0)}
	decision.hypothetical = not _actuator.can_act()
	if decision.get("forecast_contradicted", false):
		_log.warning("forecast_contradicted type=%s level=%d status=%s p=%s power=%s: raises suspended, no lower on this failure alone" % [type, event.level, current.get("status", "none"), _format_value(current.get("p_success", -1.0)), profile.signature])
	_log_decision(type, decision, next, assumed)
	_handle_action(tracker, event, decision, assumed)
	_refresh_controls()


## A success is proof enough to forget a lower, and a failure to forget a raise. Then the attack's end
## is an occasion to act: the failure is known at a tick, and a success resets the window after the signal.
func _handle_action(tracker: Dictionary, event: Dictionary, decision: Dictionary, assumed: Dictionary) -> void:
	var type: String = tracker.type
	if _actuator.has_pending(type):
		var direction := _actuator.pending_direction()
		# A lower chosen for what a level brings does not wait for a failure, and a success does not contradict it.
		var by_choice := _actuator.pending_by_choice()
		if (direction == "raise" and event.event == "failure_power") or (direction == "lower" and event.event == "success" and not by_choice):
			_cancel_action(type, "contradicted_by_attack")
	if decision.decision != "hold":
		var power := {"damage_rate": event.damage_rate, "infection_rate": event.infection_rate, "vulnerability": event.vulnerability}
		var refused := _actuator.request(type, decision.decision, event.level, power, assumed, decision)
		if not refused.is_empty():
			_regulator_for(type).cancel_last_action()
			_log_refusal(type, decision.decision, refused)
	if not _actuator.has_pending(type):
		return
	var cycle_key := "%d|%d" % [tracker.window.get_instance_id(), event.cycle_id]
	if event.event == "failure_power":
		_attempt_action(tracker, cycle_key, "tick")
	elif event.event == "success":
		_attempt_after_success.call_deferred(tracker.window.get_instance_id(), cycle_key)


func _attempt_after_success(id: int, cycle_key: String) -> void:
	var tracker: Dictionary = _trackers.get(id, {})
	if _actuator != null and not tracker.is_empty():
		_attempt_action(tracker, cycle_key, "deferred")


func _attempt_action(tracker: Dictionary, cycle_key: String, moment: String) -> void:
	var type: String = tracker.type
	var nodes := 0
	for other: Dictionary in _trackers.values():
		if other.type == type and is_instance_valid(other.window):
			nodes += 1
	var regulator := _regulator_for(type)
	var levels_before := _levels_text()
	var state_before := _state_text(tracker.window)
	var result := _actuator.attempt(type, tracker.window, cycle_key, nodes, not regulator.is_unsafe(), tracker.native_usable, _state.is_paused(type))
	if result.is_empty():
		return
	var pending: Dictionary = result.pending
	var trace := _action_trace(pending)
	match result.outcome:
		"would_act":
			_log.info("action_would_apply type=%s %s" % [type, trace])
		"acted":
			_log.info("action_applied type=%s %s level_after=%d detected_after=%s time_after=%s max_time_after=%s problem=%s levels_before=%s levels_after=%s moment=%s tick=%d frame=%d usec=%d state_before=%s state_after=%s" % [type, trace, result.level_after, result.detected_after, _format_value(result.time_after), _format_value(result.max_time_after), result.get("reason", "none"), levels_before, _levels_text(), moment, _tick_index, Engine.get_process_frames(), Time.get_ticks_usec(), state_before, _state_text(tracker.window)])
		"deferred":
			_log.info("action_deferred_no_safe_window type=%s %s attempts=%d state=%s total=%d moment=%s tick=%d frame=%d state_before=%s" % [type, trace, pending.attempts, result.reason, _actuator.deferred_total, moment, _tick_index, Engine.get_process_frames(), state_before])
			if result.starving:
				_log.warning("action_starving type=%s direction=%s attempts=%d: no safe window was found, the action keeps waiting" % [type, pending.direction, pending.attempts])
		"refused":
			regulator.cancel_last_action()
			_log_refusal(type, pending.direction, result.reason)
	_log_new_halt()


func _state_text(window: Node) -> String:
	return "detected:%s,time:%s,max_time:%s,firewall:%s,max_firewall:%s,breached:%s,paused:%s" % [window.detected, _format_value(window.time), _format_value(window.max_time), _format_value(window.firewall), _format_value(window.max_firewall), _format_value(window.breached), window.paused]


## The level of every watched node, to see that an action touched only its own.
func _levels_text() -> String:
	var levels := PackedStringArray()
	for tracker: Dictionary in _trackers.values():
		if is_instance_valid(tracker.window):
			levels.append("%s:%d" % [tracker.type, int(tracker.window.data.level)])
	return ",".join(levels)


## Everything that motivated an action, on one line.
func _action_trace(pending: Dictionary) -> String:
	var decision: Dictionary = pending.decision
	var expected: Dictionary = pending.expected
	return "direction=%s level=%d target=%d reason=%s certain=%s verify_attacks=%s profile=%s margin=%s window_attacks=%d window_failures=%d successes_in_row=%d failures_needed=%s risk=%s forecast_status=%s forecast_outcome=%s forecast_p=%s used_max=%s" % [
		pending.direction, pending.from, pending.to, decision.reason, decision.get("certain", false), decision.get("verify_attacks", "default"), decision.profile, _format_value(decision.margin),
		decision.window_attacks, decision.window_failures, decision.successes_in_row, decision.get("needed", "none"),
		_format_value(decision.get("risk", -1.0)), expected.get("status", "none"), expected.get("outcome", "none"),
		_format_value(expected.get("p_success", -1.0)), _format_value(expected.get("used_max", -1.0)),
	]


func _cancel_action(type: String, reason: String) -> void:
	var cancelled := _actuator.cancel_pending(type)
	if cancelled.is_empty():
		return
	_regulator_for(type).cancel_last_action()
	_log.info("action_cancelled type=%s direction=%s reason=%s attempts=%d" % [type, cancelled.direction, reason, cancelled.attempts])


## Refusals repeat at every attack: only a new reason is logged, the summary has the counts.
func _log_refusal(type: String, direction: String, reason: String) -> void:
	var key := "%s|%s" % [direction, reason]
	if _last_refusal.get(type, "") == key:
		return
	_last_refusal[type] = key
	_log.info("action_refused type=%s direction=%s reason=%s" % [type, direction, reason])


func _log_verification(result: Dictionary) -> void:
	if not result.is_empty():
		_log.info("action_verification type=%s from=%d to=%d outcome=%s reason=%s next_event=%s next_used=%s" % [result.type, result.from, result.to, result.outcome, result.reason, result.next_event, _format_value(result.next_used)])


func _log_new_halt() -> void:
	var reason := _actuator.take_new_halt()
	if not reason.is_empty():
		_log.warning("regulation_stopped reason=%s actions=%d" % [reason, _actuator.actions_done])
		_refresh_controls()


func _on_speed_changed() -> void:
	for type: String in _regulators:
		_regulators[type].on_speed_changed()
		if _actuator != null:
			_cancel_action(type, "speed_changed")
	_refresh_controls()


## Stops all actions until the game is restarted, even if the observer starts again.
func emergency_stop() -> void:
	_emergency = true
	_log.warning("emergency_stop actuator=%s" % ("none" if _actuator == null else "stopped"))
	if _actuator != null:
		for type: String in _regulators:
			_cancel_action(type, "emergency_stop")
		_actuator.halt("emergency_stop")
		_log_new_halt()
	_refresh_controls()


## Adds the row under the node's level buttons, once. Without them, the node just has no control.
func _attach_control(tracker: Dictionary) -> void:
	var actions: Node = tracker.window.find_child("ActionContainer", true, false)
	var source: Node = tracker.window.find_child("AddButton", true, false)
	if actions == null or not source is Button or actions.get_parent() == null:
		_log.info("automation_control type=%s result=unavailable" % tracker.type)
		return
	var parent: Node = actions.get_parent()
	var old: Node = parent.get_node_or_null(AutomationControl.NODE_NAME)
	if old != null:
		parent.remove_child(old)
		old.queue_free()
	var control := AutomationControl.new()
	control.setup(source, _on_control_pressed.bind(tracker.type), _advice_action)
	parent.add_child(control)
	tracker.control = control
	control.show_state(_automation_view(tracker.type))


func _detach_controls() -> void:
	for tracker: Dictionary in _trackers.values():
		var control: Variant = tracker.get("control")
		if is_instance_valid(control):
			control.get_parent().remove_child(control)
			control.queue_free()


func _refresh_controls() -> void:
	for tracker: Dictionary in _trackers.values():
		var control: Variant = tracker.get("control")
		if is_instance_valid(control):
			control.show_state(_automation_view(tracker.type))


## Why this type cannot act whatever the player does. A resume button cannot lift any of these.
func _block_reason(type: String) -> String:
	if _emergency:
		return "emergency_stop"
	if not _actuator.halt_reason.is_empty():
		return _actuator.halt_reason
	if _data.auto_level_breach:
		return "native_option"
	if absf(_attributes.tick_speed - ThreatActuator.NORMAL_TICK_SPEED) > ThreatActuator.SPEED_TOLERANCE:
		return "speed"
	for tracker: Dictionary in _trackers.values():
		if tracker.type == type and not tracker.native_usable:
			return "native_methods"
	if _regulators.has(type) and _regulators[type].is_unsafe():
		return "classifier"
	return ""


## What the node shows: a pause and a block are two separate things, and both can be true.
func _automation_view(type: String) -> Dictionary:
	if _actuator == null:
		return {"kind": "disabled", "text": I18n.t("state.disabled"), "button": "", "tooltip": ""}
	var block := _block_reason(type)
	var block_text := I18n.t("block.%s" % block) if BLOCK_TEXTS.has(block) else I18n.t("block.anomaly", {"reason": block})
	if _state.is_paused(type):
		var note := "" if block.is_empty() else I18n.t("state.blocked_after_resume", {"reason": block_text})
		return {"kind": "pause", "text": I18n.t("state.paused"), "button": I18n.t("control.resume"), "tooltip": note}
	if not block.is_empty():
		return {"kind": "blocked", "text": I18n.t("state.blocked"), "button": "", "tooltip": block_text}
	# Without the right to act, saying "active" would be false.
	var text := I18n.t("state.active" if _actuator.is_armed() else "state.simulation")
	return {"kind": "active", "text": text, "button": I18n.t("control.pause"), "tooltip": ""}


func _on_control_pressed(type: String) -> void:
	if _actuator == null:
		return
	if _state.is_paused(type):
		_resume_automation(type)
	elif _automation_view(type).kind == "active":
		_pause_automation(type, "player_button", _level_of_type(type))


func _pause_automation(type: String, why: String, level: int) -> void:
	_cancel_action(type, why)
	if _state.pause(type, why):
		_regulator_for(type).set_paused(true)
		_log.info("automation_pause type=%s reason=%s level=%d" % [type, why, level])
	_refresh_controls()


## Only lifts the pause and starts observing again: this can never change a level by itself.
func _resume_automation(type: String) -> void:
	var level := _level_of_type(type)
	if not _state.resume(type):
		return
	_regulator_for(type).on_resume(level)
	_log.info("automation_resume type=%s level=%d" % [type, level])
	_refresh_controls()


func _level_of_type(type: String) -> int:
	for tracker: Dictionary in _trackers.values():
		if tracker.type == type and is_instance_valid(tracker.window):
			return int(tracker.window.data.level)
	return -1


## Where the game's Ctrl+Z may live: would it also undo a change made by the mod? Names only.
func _log_undo_candidates(root: Node) -> void:
	var pattern := RegEx.create_from_string("(?i)undo|redo|history")
	for node: Node in root.get_children():
		var script: Script = node.get_script()
		if node == self or script == null:
			continue
		var found := PackedStringArray()
		for method: Dictionary in script.get_script_method_list():
			if pattern.search(method.name) != null:
				found.append(method.name)
		if not found.is_empty():
			_log.info("inventory undo_candidates node=%s methods=%s" % [node.name, ",".join(found)])


## What can be learned about the level methods without calling them: their arguments and which
## methods the node's buttons reach. Names only.
func _log_native_actions(window: Node) -> void:
	var script: Script = window.get_script()
	var methods := PackedStringArray()
	while script != null:
		for method: Dictionary in script.get_script_method_list():
			if method.name in ["level_up", "level_down", "animate_level_up", "animate_level_down", "reset", "_on_add_button_pressed", "_on_reduce_button_pressed"]:
				var arguments := PackedStringArray()
				for argument: Dictionary in method.args:
					arguments.append("%s:%s" % [argument.name, type_string(argument.type)])
				methods.append("%s(%s)defaults=%d" % [method.name, ",".join(arguments), method.default_args.size()])
		script = script.get_base_script()
	var buttons := PackedStringArray()
	for button: Node in window.find_children("*", "BaseButton", true, false):
		var targets := PackedStringArray()
		for connection: Dictionary in button.pressed.get_connections():
			var target: Callable = connection.callable
			targets.append("%s.%s" % ["self" if target.get_object() == window else str(target.get_object()), target.get_method()])
		buttons.append("%s>%s" % [button.name, "+".join(targets)])
	_log.info("native_actions type=%s methods=%s buttons=%s" % [window.window, ";".join(methods), ";".join(buttons)])


func _regulator_for(type: String) -> ThreatRegulator:
	if not _regulators.has(type):
		var regulator := ThreatRegulator.new(_regulation.profile, _regulation.max_allowed_level, _regulation.min_level)
		regulator.set_paused(_state.is_paused(type))
		_regulators[type] = regulator
	return _regulators[type]


## Which levels work at this power: the answer only changes with the power or the levels unlocked.
func _level_scan(tracker: Dictionary, profile: Dictionary, margin: float, top: int) -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%s|%s" % [tracker.type, profile.signature, profile.damage_rate, profile.get("hit_spread", false), profile.interval, margin, top]
	if _level_scans.has(key):
		return _level_scans[key]
	if _level_scans.size() >= FORECAST_CACHE_SIZE:
		_level_scans.clear()
	var scan := {}
	for level: int in range(0, top + 1):
		var target := _native_values(tracker, level)
		if not target.is_empty():
			var result := BreachForecast.forecast(profile, target, margin)
			scan[level] = result.p_success if result.status == "reliable" else -1.0
	_level_scans[key] = scan
	return scan


## The hits and the infection measured on the chain, and whether attacks can be drawn from them.
## What infection does is in its measure. An unknown effect on the payload, or a game that does not name
## stealth, leaves a real trial to decide.
func _chain_measure(tracker: Dictionary, profile: Dictionary) -> Dictionary:
	var hits := _hit_log.multipliers(tracker.get("chain_key", ""))
	var infection := _hit_log.infection(tracker.get("infection_key", ""))
	var unknown_effect: bool = (profile.breach_variation & ~_stealth_mask) != 0 or (_stealth_mask == 0 and profile.infection_variation != 0)
	var enough: bool = hits.size() >= HackingModel.MIN_HITS and (profile.infection_rate <= 0.0 or infection.pulses >= HackingModel.MIN_PULSES)
	return {"hits": hits, "infection": infection, "measured": enough, "usable": enough and profile.interval > 0.0 and not unknown_effect}


func _level_outcome(profile: Dictionary, target: Dictionary, measure: Dictionary) -> Dictionary:
	var model := HackingModel.new({"time_factor": 1.0})
	return model.attack_outcome(target, profile.announced_rate * profile.interval, profile.infection_rate * profile.interval, 1.0 + profile.vulnerability, measure.hits, profile.interval, (profile.breach_variation & _stealth_mask) != 0, (profile.infection_variation & _stealth_mask) != 0, measure.infection)


## The level that brings the most for the objective, and the level to win to open the next one.
## {} when the chain is not measured or the game does not tell the rewards: the highest level is then aimed at.
## profitable is -1 while the levels are being measured, which keeps the level where it is.
func _profit_choice(tracker: Dictionary, profile: Dictionary, regulator: ThreatRegulator, event: Dictionary) -> Dictionary:
	if not tracker.get("reward_getters", false) or tracker.getters.values().has(false):
		return {}
	var measure := _chain_measure(tracker, profile)
	if not measure.usable:
		return {}
	# The measure is kept as it was when it became enough: an attack must not pay for a new table.
	# Another chain with the same announced power hits otherwise: its hits are in a table of their own.
	var key := "%s|%s|%s|%s|%s" % [tracker.type, profile.signature, profile.interval, tracker.get("chain_key", ""), tracker.get("infection_key", "")]
	var table: Dictionary = _profit_tables.get(tracker.type, {})
	if table.get("key", "") != key:
		table = {"key": key, "window": tracker.window, "profile": profile, "measure": measure, "levels": {}, "next": maxi(_regulation.min_level, 0), "top": event.max_level}
		_profit_tables[tracker.type] = table
	table.top = maxi(table.top, event.max_level)
	if table.next <= table.top:
		return {"profitable": -1, "unlock": -1}
	var reachable := {}
	for level: int in table.levels:
		if level >= _regulation.min_level and level <= event.max_level and regulator.can_reach(level):
			reachable[level] = table.levels[level]
	var profitable := LevelChoice.profitable(reachable, _objective, tracker.type, regulator.required_success(), regulator.home_level(event.level))
	if profitable < 0:
		return {}
	var trial: float = TRIAL_CHANCE if regulator.allows_trials() else regulator.required_success()
	var choice := {"profitable": profitable, "unlock": LevelChoice.to_unlock(reachable, event.level, event.max_level, trial)}
	if choice.unlock >= 0:
		choice.unlock_chance = reachable[choice.unlock].chance
	var text := "%s|%d|%d" % [_objective, choice.profitable, choice.unlock]
	if _last_choice.get(tracker.type, "") != text:
		_last_choice[tracker.type] = text
		_log.info("level_choice type=%s objective=%s level=%d profitable=%d unlock=%d" % [tracker.type, _objective, event.level, choice.profitable, choice.unlock])
	return choice


## One level a tick over all types: a level costs up to some milliseconds, and the game must not stutter.
func _advance_profit_tables() -> void:
	for type: String in _profit_tables.keys():
		var table: Dictionary = _profit_tables[type]
		if table.next > table.top:
			continue
		if not is_instance_valid(table.window):
			_profit_tables.erase(type)
			return
		var level: int = table.next
		table.next += 1
		var target := _native_values({"window": table.window, "getters": {}}, level)
		var reward: Variant = table.window.get_reward(level)
		var xp: Variant = table.window.get_experience_reward(level)
		if not target.is_empty() and (reward is float or reward is int) and (xp is float or xp is int):
			var outcome := _level_outcome(table.profile, target, table.measure)
			table.levels[level] = {"chance": outcome.chance, "cycle": outcome.cycle, "reward": float(reward), "xp": float(xp)}
		if table.next > table.top:
			_log_profit_table(type, table)
		return


func _log_profit_table(type: String, table: Dictionary) -> void:
	var parts := PackedStringArray()
	for level: int in table.levels:
		var entry: Dictionary = table.levels[level]
		if entry.chance > 0.0:
			var brought := LevelChoice.rates(entry)
			parts.append("%d:%.2f:%.2f:%s:%s" % [level, entry.chance, entry.cycle, _format_value(brought.reward), _format_value(brought.xp)])
	_log.info("profit_levels type=%s top=%d levels=%s" % [type, table.top, ";".join(parts)])


## Could the next level work with some luck? Strong hits count for a quarter of the gap above the lowest.
func _may_work(tracker: Dictionary, profile: Dictionary, event: Dictionary) -> bool:
	var seen: Dictionary = _observed_hits.get(tracker.type, {})
	# Once enough hits are known, the answer holds for this power: an attack must not pay for a new calculation.
	var measure := _chain_measure(tracker, profile)
	var key := "may|%s|%s|%s|%s|%s" % [tracker.type, profile.signature, event.level, profile.interval, "measured" if measure.measured else "%s|%s" % [seen.get("lowest", -1.0), seen.get("highest", 0.0)]]
	if _level_scans.has(key):
		return _level_scans[key]
	if _level_scans.size() >= FORECAST_CACHE_SIZE:
		_level_scans.clear()
	var answer := false
	var target := _native_values(tracker, event.level + 1)
	if not target.is_empty() and event.level + 1 <= event.max_level and measure.usable:
		answer = _level_outcome(profile, target, measure).chance >= TRIAL_CHANCE
	elif not target.is_empty() and event.level + 1 <= event.max_level:
		var hopeful := profile.duplicate()
		hopeful.erase("hit_spread")
		if profile.get("hit_spread", false) and seen.get("lowest", -1.0) > 0.0 and profile.interval > 0.0:
			hopeful.damage_rate = (seen.lowest + (seen.highest - seen.lowest) * 0.25) / profile.interval
		var result := BreachForecast.forecast(hopeful, target, 0.0)
		# Without a forecast, whatever the reason, a real trial decides: the way back exists. Only having no damage at all rules it out.
		var unknown: bool = result.status == "invalid" and not result.reasons.has("no_damage") and not result.reasons.has("low_hit")
		answer = unknown or result.status == "uncertain" or (result.status == "reliable" and result.p_success >= 0.5)
	_level_scans[key] = answer
	return answer


## The highest level the forecast is sure of, or -1.
func _best_raise(tracker: Dictionary, profile: Dictionary, regulator: ThreatRegulator, event: Dictionary) -> int:
	var scan := _level_scan(tracker, profile, regulator.margin(), event.max_level)
	for level: int in range(event.max_level, event.level, -1):
		if scan.get(level, -1.0) >= 1.0 - ThreatActuator.EPSILON and regulator.can_reach(level):
			return level
	return -1


## The highest level below that should work. If none does, one step down: the next failures go further.
func _best_lower(tracker: Dictionary, profile: Dictionary, regulator: ThreatRegulator, event: Dictionary) -> int:
	var scan := _level_scan(tracker, profile, 0.0, event.level)
	for level: int in range(event.level - 1, -1, -1):
		if scan.get(level, -1.0) >= regulator.required_success() - ThreatActuator.EPSILON:
			return level
	return event.level - 1


## Remembers the hits seen at this power, and lets the forecasts count on them.
func _apply_observed_hits(type: String, event: Dictionary, profile: Dictionary) -> void:
	var seen: Dictionary = _observed_hits.get(type, {})
	if seen.get("signature") != profile.signature:
		seen = {"signature": profile.signature, "lowest": -1.0, "highest": 0.0}
		_observed_hits[type] = seen
	if event.complete and event.has("max_hit"):
		seen.highest = maxf(seen.highest, event.max_hit)
	if event.complete and event.has("low_hit"):
		seen.lowest = event.low_hit if seen.lowest < 0.0 else minf(seen.lowest, event.low_hit)
	PowerProfile.apply_observed_hits(profile, seen.lowest, seen.highest)
	if profile.get("hit_spread", false) and not seen.get("logged", false):
		seen.logged = true
		_log.info("hit_spread type=%s announced=%s lowest=%s highest=%s" % [type, _format_value(event.damage_rate), _format_value(seen.lowest), _format_value(seen.highest)])


func _forecast_for(profile: Dictionary, target: Dictionary, margin: float) -> Dictionary:
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [profile.signature, profile.damage_rate, profile.get("hit_spread", false), profile.interval, profile.tick_speed, profile.infection_offset, target.firewall, target.breach, target.time, margin]
	if _forecasts.has(key):
		return _forecasts[key]
	if _forecasts.size() >= FORECAST_CACHE_SIZE:
		_forecasts.clear()
	var result := BreachForecast.forecast(profile, target, margin)
	_forecasts[key] = result
	return result


## Compares what happened with what the forecast allowed. Anything outside is signaled for analysis.
func _check_forecast(type: String, regulator: ThreatRegulator, event: Dictionary, profile: Dictionary, current: Dictionary) -> void:
	if not event.complete or current.status == "invalid" or profile.get("hits_unseen", false):
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
func _log_decision(type: String, decision: Dictionary, next: Dictionary, assumed: Dictionary) -> void:
	if decision.decision == "hold":
		if _last_hold_reason.get(type, "") == decision.reason:
			return
		_last_hold_reason[type] = decision.reason
	else:
		_last_hold_reason[type] = ""
	var parts := PackedStringArray([_regulation.mode, "type=%s" % type])
	for key: String in decision:
		parts.append("%s=%s" % [key, _format_value(decision[key])])
	parts.append("next_status=%s" % next.get("status", "none"))
	parts.append("next_outcome=%s" % next.get("outcome", "none"))
	parts.append("next_p=%s" % _format_value(next.get("p_success", -1.0)))
	parts.append("next_used_max=%s" % _format_value(next.get("used_max", -1.0)))
	if decision.decision != "hold":
		# What the hypothetical decision would lead to, supposing it were applied.
		parts.append("assumed_status=%s" % assumed.get("status", "none"))
		parts.append("assumed_outcome=%s" % assumed.get("outcome", "none"))
		parts.append("assumed_p=%s" % _format_value(assumed.get("p_success", -1.0)))
		parts.append("assumed_used_max=%s" % _format_value(assumed.get("used_max", -1.0)))
	_log.info(" ".join(parts))


func _log_regulators() -> void:
	for type: String in _regulators:
		var regulator: ThreatRegulator = _regulators[type]
		_log.info("regulator_summary type=%s profile=%s repeats_suppressed=%d model_trust=%s unsafe=%s paused=%s" % [type, regulator.profile_name, regulator.suppressed_repeats, regulator.model_trust(), regulator.is_unsafe(), _state.is_paused(type)])


## Looks for what could identify a save slot. Only names and types are logged: a value may hold a
## profile name or a personal path, and logs are shared in bug reports.
func _log_save_candidates() -> void:
	var pattern := RegEx.create_from_string(SAVE_CANDIDATE)
	var root := get_tree().root
	for node: Node in root.get_children():
		if node == self or node.get_script() == null:
			continue
		var found := PackedStringArray()
		for property: Dictionary in node.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and pattern.search(property.name) != null:
				found.append("%s=%s" % [property.name, type_string(typeof(node.get(property.name)))])
		var methods := PackedStringArray()
		for method: Dictionary in node.get_script().get_script_method_list():
			if pattern.search(method.name) != null:
				methods.append(method.name)
		if node == _data or node == _globals or not found.is_empty() or not methods.is_empty():
			_log.info("inventory save_candidates node=%s %s methods=%s" % [node.name, " ".join(found), ",".join(methods)])
	# Screens of the current scene can hold the slot, too. Only their paths and names are read.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var nodes := PackedStringArray()
	for node: Node in scene.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and pattern.search(script.resource_path.get_file()) != null:
			nodes.append("%s(%s)" % [node.name, script.resource_path.get_file()])
			if nodes.size() >= SAVE_NODES_LOGGED:
				break
	if not nodes.is_empty():
		_log.info("inventory save_nodes %s" % ",".join(nodes))


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
## A purchase can change what a target demands while the power stays the same: more time to attack, say.
## That is a new situation too. The reference level never moves, so that climbing changes nothing here.
func _with_target_rules(tracker: Dictionary, signature: String) -> String:
	var rules := _native_values(tracker, REFERENCE_LEVEL)
	if rules.is_empty():
		return signature
	return "%s|%.3f|%.3f|%.3f" % [signature, rules.firewall, rules.breach, rules.time]


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
	for method: String in NATIVE_GETTERS + REWARD_GETTERS + NATIVE_REPORTED:
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
	# What a node's definition holds, to learn how the game counts the nodes one may place.
	for key: String in _data.windows:
		if _data.windows[key] is Dictionary and _data.windows[key].get("category") == "hacking":
			_log.info("inventory window_fields=%s:%s" % [key, ",".join(_data.windows[key].keys())])
			break


func _format(type: String, event: Dictionary) -> String:
	var parts := PackedStringArray(["event=%s" % event.event, "type=%s" % type])
	for field: String in EVENT_FIELDS:
		if event.has(field):
			parts.append("%s=%s" % [field, _format_value(event[field])])
	return " ".join(parts)


## What the target gives, as the game shows it on its outputs: resource, rate and stock. Read only, to check
## what an elite level really brings against an ordinary one.
func _outputs(window: Variant) -> String:
	if not is_instance_valid(window) or not window.get("containers") is Array:
		return ""
	var skipped := []
	for name: String in ATTACK_SLOTS:
		skipped.append(window.get(name))
	var parts := PackedStringArray()
	for slot: Variant in window.containers:
		if not is_instance_valid(slot) or skipped.has(slot):
			continue
		var production: Variant = slot.get("production")
		var count: Variant = slot.get("count")
		if (production is float or production is int) and (count is float or count is int):
			parts.append("%s:%s:%s" % [slot.get("resource"), _format_value(float(production)), _format_value(float(count))])
	return ",".join(parts)


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
