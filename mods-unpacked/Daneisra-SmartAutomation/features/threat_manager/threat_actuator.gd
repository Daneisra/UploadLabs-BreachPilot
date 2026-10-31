extends RefCounted
## The only script allowed to change a threat level, through _call_native and nothing else.
##
## Unless action_policy.gd says otherwise, it cannot act: a would-be action only ends up in the log.
## All other checks run the same, which lets the dry run show what they would have decided.
##
## An action is safe because the state is read right before it, in one synchronous call: never
## because some time has passed. A window that cannot be proven free means no action, not a forced one.

const Policy := preload("action_policy.gd")

const NORMAL_TICK_SPEED := 0.05
const SPEED_TOLERANCE := 1e-6
const EPSILON := 1e-6
const LEVEL_STEP := 1
## Attempts in a row without a safe window before it is reported as a problem.
const STARVING_AFTER := 5
## Seconds of the game's timer to see the next attack end, after which the action is not proven clean.
const VERIFY_TIMEOUT := 60.0
const FORECAST_TOLERANCE := 0.15

var action_limit: int
var action_type: String
var actions_done := 0
var deferred_total := 0
var refused_counts: Dictionary = {}
var halt_reason := ""

var _armed: bool
var _attributes: Object
var _data: Object
var _min_level: int
var _max_allowed: int
var _verify_attacks: int
var _marker_path: String
var _pending: Dictionary = {}
var _claim: Dictionary = {}
var _verifying: Dictionary = {}
var _last_cycle := ""
var _in_call := false
var _halt_reported := true


## game holds the attributes and data nodes. options: action_limit, action_type, min_level, max_allowed,
## verify_attacks, marker_path.
func _init(armed: bool, game: Dictionary, options: Dictionary = {}) -> void:
	_armed = armed
	_attributes = game.get("attributes")
	_data = game.get("data")
	action_limit = options.get("action_limit", 1)
	action_type = options.get("action_type", "")
	_min_level = options.get("min_level", 0)
	_max_allowed = options.get("max_allowed", -1)
	_verify_attacks = options.get("verify_attacks", 1)
	_marker_path = options.get("marker_path", Policy.TRIAL_MARKER)


## The lock of this build. Changing it needs a new build, after a validation by the project's owner.
func _build_allows_actions() -> bool:
	return Policy.ACTIONS_ENABLED


## An action outside what the authorized trial allows, whatever the regulator proposed.
func _trial_refusal(pending: Dictionary) -> String:
	if pending.type != Policy.TRIAL_TYPE or pending.direction != Policy.TRIAL_DIRECTION or pending.from != Policy.TRIAL_FROM or pending.to != Policy.TRIAL_TO:
		return "outside_trial"
	if pending.expected.get("status") != "reliable" or pending.expected.get("p_success", -1.0) < Policy.TRIAL_MIN_TARGET_SUCCESS - EPSILON:
		return "target_forecast_not_reliable"
	if actions_done >= Policy.TRIAL_MAX_ACTIONS:
		return "action_limit"
	if FileAccess.file_exists(_marker_path):
		return "trial_already_used"
	return ""


## Written before the call, so that a crash or a restart cannot lead to a second action.
func _consume_trial() -> bool:
	DirAccess.make_dir_recursive_absolute(_marker_path.get_base_dir())
	var file := FileAccess.open(_marker_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"trial": Policy.TRIAL_ID, "unix_time": Time.get_unix_time_from_system()}))
	file.close()
	return FileAccess.file_exists(_marker_path)


func is_armed() -> bool:
	return _armed and _build_allows_actions()


## Armed and not stopped: a decision taken now could really be applied.
func can_act() -> bool:
	return is_armed() and halt_reason.is_empty()


func has_pending(type: String) -> bool:
	return not _pending.is_empty() and _pending.type == type


func is_verifying() -> bool:
	return not _verifying.is_empty()


func pending_direction() -> String:
	return _pending.get("direction", "")


## Stops everything until the session ends. The first reason is the one kept.
func halt(reason: String) -> void:
	if halt_reason.is_empty():
		halt_reason = reason
		_halt_reported = false
	_pending = {}


## The reason of a halt not told yet, once.
func take_new_halt() -> String:
	if _halt_reported:
		return ""
	_halt_reported = true
	return halt_reason


## Registers a decision. Returns why it was refused, or an empty text.
func request(type: String, direction: String, level: int, power: Dictionary, expected: Dictionary, decision: Dictionary) -> String:
	var reason := ""
	if not halt_reason.is_empty():
		reason = "halted"
	elif not _pending.is_empty():
		reason = "another_action_pending"
	elif is_verifying():
		reason = "previous_action_unverified"
	elif is_armed() and action_type.is_empty():
		reason = "no_action_type"
	elif not action_type.is_empty() and type != action_type:
		reason = "type_not_allowed"
	elif is_armed() and actions_done >= action_limit:
		reason = "action_limit"
	if not reason.is_empty():
		refused_counts[reason] = refused_counts.get(reason, 0) + 1
		return reason
	_pending = {
		"type": type, "direction": direction, "from": level, "to": level + (1 if direction == "raise" else -1),
		"power": power, "expected": expected, "decision": decision, "attempts": 0,
	}
	return ""


## Drops the waiting action of this type. Returns it, or an empty dictionary.
func cancel_pending(type: String) -> Dictionary:
	if not has_pending(type):
		return {}
	var cancelled := _pending
	_pending = {}
	return cancelled


## Tries the waiting action of this type. From the first read to the native call, nothing here waits.
func attempt(type: String, window: Variant, cycle_key: String, nodes_of_type: int, classifier_safe: bool, native_usable: bool, ceiling: int) -> Dictionary:
	if not has_pending(type):
		return {}
	var pending := _pending
	var refusal := _refusal(window, pending, cycle_key, nodes_of_type, classifier_safe, native_usable, ceiling)
	if not refusal.is_empty():
		refused_counts[refusal] = refused_counts.get(refusal, 0) + 1
		_pending = {}
		return {"outcome": "refused", "reason": refusal, "pending": pending}
	var busy := _busy_reason(window)
	if not busy.is_empty():
		pending.attempts += 1
		deferred_total += 1
		return {"outcome": "deferred", "reason": busy, "pending": pending, "starving": pending.attempts == STARVING_AFTER}
	_pending = {}
	if not is_armed():
		return {"outcome": "would_act", "pending": pending}
	return _perform(window, pending, cycle_key)


## Was this level change the mod's own? True only once per action.
func claims_level_change(type: String, level: int) -> bool:
	if _claim.is_empty() or _claim.type != type or _claim.to != level:
		return false
	_claim = {}
	return true


## Feeds an attack event: an action only counts as clean once the next attack went normally.
func note_event(type: String, event: Dictionary, claimed: bool) -> Dictionary:
	if not is_verifying() or _verifying.type != type:
		return {}
	match event.event:
		"level_changed":
			return {} if claimed else _end_verification("manual_override", "player_changed_level", event)
		"level_changed_reset":
			if claimed:
				return _end_verification("failed", "action_reset_an_attack", event)
			return _end_verification("manual_override", "player_changed_level", event)
		"success", "failure_power":
			return _judge_next_attack(event)
	return _end_verification("failed", event.event, event)


## Counts the wait for the next attack. Returns a result once it took too long.
func advance(seconds: float) -> Dictionary:
	if not is_verifying():
		return {}
	_verifying.waited += seconds
	if _verifying.waited < VERIFY_TIMEOUT:
		return {}
	return _end_verification("inconclusive", "no_attack_after_action", {})


## A game was loaded: nothing waiting or being verified still applies.
func on_reload() -> Dictionary:
	_pending = {}
	_claim = {}
	if not is_verifying():
		return {}
	return _end_verification("inconclusive", "reload_during_verification", {})


func summary() -> String:
	return "actuator_summary armed=%s actions=%d deferred_no_safe_window=%d refused=%s halted=%s" % [is_armed(), actions_done, deferred_total, JSON.stringify(refused_counts), halt_reason if not halt_reason.is_empty() else "no"]


## A reason that makes the action void, for now or for good. It is not retried.
func _refusal(window: Variant, pending: Dictionary, cycle_key: String, nodes_of_type: int, classifier_safe: bool, native_usable: bool, ceiling: int) -> String:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return "not_main_thread"
	if not halt_reason.is_empty():
		return "halted"
	if _in_call:
		return "action_in_progress"
	if is_armed() and actions_done >= action_limit:
		return "action_limit"
	if is_armed():
		var outside := _trial_refusal(pending)
		if not outside.is_empty():
			return outside
	if not is_instance_valid(window):
		return "window_gone"
	if window is Node and window.process_thread_group == Node.PROCESS_THREAD_GROUP_SUB_THREAD:
		return "window_on_sub_thread"
	if not native_usable:
		return "native_methods_unusable"
	if not is_instance_valid(_data) or not _data.auto_level_breach is bool:
		return "native_option_unknown"
	if _data.auto_level_breach:
		return "native_option_active"
	if not is_instance_valid(_attributes) or not (_attributes.tick_speed is float or _attributes.tick_speed is int):
		return "speed_unknown"
	if absf(_attributes.tick_speed - NORMAL_TICK_SPEED) > SPEED_TOLERANCE:
		return "speed_not_normal"
	if nodes_of_type != 1:
		return "not_a_single_node"
	if not classifier_safe:
		return "classifier_unsafe"
	if cycle_key == _last_cycle:
		return "same_cycle"
	if int(window.data.level) != pending.from:
		return "level_changed"
	if pending.to < _min_level or pending.to > int(window.data.max_level):
		return "target_out_of_bounds"
	if pending.direction == "raise":
		if _max_allowed >= 0 and pending.to > _max_allowed:
			return "above_allowed_maximum"
		if ceiling >= 0 and pending.to > ceiling:
			return "above_manual_ceiling"
	if window.breach_damage.production != pending.power.damage_rate or window.infection_damage.production != pending.power.infection_rate or window.vulnerability.count != pending.power.vulnerability:
		return "power_changed"
	return ""


## Why the window cannot be touched right now. The action stays waiting.
func _busy_reason(window: Variant) -> String:
	if window.detected:
		return "attack_in_progress"
	if window.max_firewall - window.firewall + window.breached > EPSILON:
		return "damage_present"
	if window.paused:
		return "paused"
	if window.time < window.max_time - EPSILON:
		return "timer_not_armed"
	return ""


func _perform(window: Node, pending: Dictionary, cycle_key: String) -> Dictionary:
	if not _consume_trial():
		halt("trial_marker_unwritable")
		return {"outcome": "refused", "reason": "trial_marker_unwritable", "pending": pending}
	# The last read: nothing but this comparison stands between the state and the call.
	if int(window.data.level) != pending.from or not _busy_reason(window).is_empty():
		halt("state_moved_before_call")
		return {"outcome": "refused", "reason": "state_moved_before_call", "pending": pending}
	_in_call = true
	_last_cycle = cycle_key
	actions_done += 1
	_call_native(window, pending.direction)
	_in_call = false

	var level_after := int(window.data.level)
	var result := {"outcome": "acted", "pending": pending, "level_after": level_after, "detected_after": window.detected, "time_after": window.time, "max_time_after": window.max_time}
	if level_after != pending.to:
		result.reason = "level_mismatch"
		halt("level_mismatch")
	elif not _busy_reason(window).is_empty():
		result.reason = "state_disturbed:%s" % _busy_reason(window)
		halt("state_disturbed_by_action")
	else:
		_claim = {"type": pending.type, "to": pending.to}
		_verifying = {"type": pending.type, "from": pending.from, "to": pending.to, "expected": pending.expected, "waited": 0.0, "remaining": _verify_attacks}
	if actions_done >= action_limit:
		halt("action_limit_reached")
	return result


## The single entry point to the game's level methods.
func _call_native(window: Node, direction: String) -> void:
	if not is_armed():
		halt("native_call_without_arming")
		return
	if direction == "raise":
		window.level_up(LEVEL_STEP)
	elif direction == "lower":
		window.level_down(LEVEL_STEP)


func _judge_next_attack(event: Dictionary) -> Dictionary:
	if event.level != _verifying.to:
		return _end_verification("failed", "unexpected_level", event)
	if not event.complete or not event.get("observed_start", false):
		return _end_verification("inconclusive", "next_attack_incomplete", event)
	var expected: Dictionary = _verifying.expected
	if event.event == "success":
		var used: float = event.used
		var low: float = expected.get("used_min", -1.0)
		var high: float = expected.get("used_max", -1.0)
		if (low >= 0.0 and used < low - FORECAST_TOLERANCE) or (high >= 0.0 and used > high + FORECAST_TOLERANCE):
			return _end_verification("failed", "duration_out_of_range", event)
	_verifying.remaining -= 1
	_verifying.waited = 0.0
	if event.event == "failure_power" and not expected.get("may_fail", true):
		_verifying.refuted = true
	if _verifying.remaining > 0:
		return {}
	# A failure is a normal attack: it can prove the forecast wrong, not the action.
	return _end_verification("verified", "forecast_refuted" if _verifying.get("refuted", false) else "next_attacks_normal", event)


func _end_verification(outcome: String, reason: String, event: Dictionary) -> Dictionary:
	var result := {"outcome": outcome, "reason": reason, "type": _verifying.type, "from": _verifying.from, "to": _verifying.to, "next_event": event.get("event", "none"), "next_used": event.get("used", -1.0)}
	_verifying = {}
	_claim = {}
	if outcome == "failed" or outcome == "inconclusive":
		halt("verification_%s:%s" % [outcome, reason])
	return result
