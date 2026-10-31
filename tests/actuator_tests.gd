extends RefCounted
## Actuator checks, tested without the game. The fake window only follows what we think the game does:
## these tests cannot prove what a real call to the game's methods would do.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/"
const Actuator := preload(MOD + "features/threat_manager/threat_actuator.gd")
const Regulator := preload(MOD + "features/threat_manager/threat_regulator.gd")
const Forecast := preload(MOD + "features/threat_manager/breach_forecast.gd")

var _check_call: Callable
var _thread_result := {}


class ArmedActuator extends Actuator:
	func _build_allows_actions() -> bool:
		return true

	func _trial_refusal(_pending: Dictionary) -> String:
		return ""

	func _consume_trial() -> bool:
		return true


## Only the build's lock is opened: the trial's own limits stay real.
class TrialActuator extends Actuator:
	func _build_allows_actions() -> bool:
		return true


class FakeResource:
	var production := 30.0
	var count := 0.0


class FakeWindow extends Node:
	var data := {"level": 4.0, "max_level": 6.0}
	var detected := false
	var paused := false
	var time := 6.0
	var max_time := 6.0
	var firewall := 50.0
	var max_firewall := 50.0
	var breached := 0.0
	var breach_damage := FakeResource.new()
	var infection_damage := FakeResource.new()
	var vulnerability := FakeResource.new()
	var behavior := "normal"
	var calls: Array[String] = []

	func level_up(steps: int) -> void:
		_change("up", steps)

	func level_down(steps: int) -> void:
		_change("down", -steps)

	func _change(name_called: String, steps: int) -> void:
		calls.append("%s:%d" % [name_called, abs(steps)])
		match behavior:
			"ignored":
				return
			"double":
				data.level += steps * 2
			"starts_attack":
				data.level += steps
				detected = true
			_:
				data.level += steps


class FakeSettings extends Node:
	var auto_level_breach: Variant = false
	var tick_speed: Variant = 0.05


func run(check: Callable) -> void:
	_check_call = check
	_test_shipped_build_cannot_act()
	_test_refusals()
	_test_not_main_thread()
	_test_no_forced_action()
	_test_one_action()
	_test_incoherence()
	_test_verification()
	_test_stop_rules()
	_test_trial_limits()
	_test_regulator_support()
	_test_closed_loop()


func _check(condition: bool, label: String) -> void:
	_check_call.call(condition, label)


func _setup(armed: bool = true, options: Dictionary = {}) -> Dictionary:
	var settings := FakeSettings.new()
	var window := FakeWindow.new()
	var merged := {"action_limit": 5, "action_type": "breach_corps"}
	merged.merge(options, true)
	var actuator: Actuator = ArmedActuator.new(armed, {"attributes": settings, "data": settings}, merged)
	return {"actuator": actuator, "window": window, "settings": settings}


func _free(setup: Dictionary) -> void:
	if is_instance_valid(setup.window):
		setup.window.free()
	setup.settings.free()


func _request(setup: Dictionary, direction: String = "raise", level: int = 4, expected: Dictionary = {}) -> String:
	var power := {"damage_rate": 30.0, "infection_rate": 30.0, "vulnerability": 0.0}
	var decision := {"reason": "conditions_met"}
	return setup.actuator.request("breach_corps", direction, level, power, expected, decision)


func _attempt(setup: Dictionary, cycle: String = "1|1", nodes: int = 1, safe: bool = true, usable: bool = true, paused: bool = false) -> Dictionary:
	return setup.actuator.attempt("breach_corps", setup.window, cycle, nodes, safe, usable, paused)


func _attack(level: int, event: String = "success", complete: bool = true, used: float = 3.0) -> Dictionary:
	return {"event": event, "level": level, "complete": complete, "observed_start": true, "used": used}


func _test_shipped_build_cannot_act() -> void:
	var settings := FakeSettings.new()
	var window := FakeWindow.new()
	var shipped := Actuator.new(true, {"attributes": settings, "data": settings}, {"action_limit": 5, "action_type": "breach_corps"})
	_check(not shipped.is_armed(), "this build's actuator cannot be armed, even when asked")
	shipped.request("breach_corps", "raise", 4, {"damage_rate": 30.0, "infection_rate": 30.0, "vulnerability": 0.0}, {}, {})
	var result := shipped.attempt("breach_corps", window, "1|1", 1, true, true, false)
	_check(result.outcome == "would_act" and window.calls.is_empty(), "all checks can pass and still nothing is called")
	shipped._call_native(window, "raise")
	_check(window.calls.is_empty() and shipped.halt_reason == "native_call_without_arming", "a direct call stops everything instead of acting")
	_check(not Actuator.Policy.ACTIONS_ENABLED, "the repository's policy keeps actions closed")
	var policy_source := FileAccess.get_file_as_string(MOD + "features/threat_manager/action_policy.gd")
	_check(policy_source.count("const ACTIONS_ENABLED := false") == 1, "the lock is closed in the source")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOD + "manifest.json"))
	var modes: Array = manifest.extra.godot.config_schema.properties.regulation_mode.enum
	_check(modes == ["off", "dry_run"], "the options offer no active mode")
	window.free()
	settings.free()


func _test_refusals() -> void:
	var cases: Array = [
		["native_option_active", func(s: Dictionary) -> void: s.settings.auto_level_breach = true],
		["native_option_unknown", func(s: Dictionary) -> void: s.settings.auto_level_breach = null],
		["speed_not_normal", func(s: Dictionary) -> void: s.settings.tick_speed = 0.25],
		["speed_unknown", func(s: Dictionary) -> void: s.settings.tick_speed = null],
		["level_changed", func(s: Dictionary) -> void: s.window.data.level = 5.0],
		["target_out_of_bounds", func(s: Dictionary) -> void: s.window.data.max_level = 4.0],
		["power_changed", func(s: Dictionary) -> void: s.window.breach_damage.production = 60.0],
		["power_changed", func(s: Dictionary) -> void: s.window.vulnerability.count = 0.5],
	]
	for entry: Array in cases:
		var setup := _setup()
		_request(setup)
		entry[1].call(setup)
		var result := _attempt(setup)
		_check(result.outcome == "refused" and result.reason == entry[0], "refused: %s" % entry[0])
		_check(setup.window.calls.is_empty() and not setup.actuator.has_pending("breach_corps"), "%s calls nothing and is not retried" % entry[0])
		_free(setup)

	var gone := _setup()
	_request(gone)
	gone.window.free()
	_check(_attempt(gone).reason == "window_gone", "refused: the window no longer exists")
	_free(gone)

	for args: Array in [[2, true, true, "not_a_single_node"], [0, true, true, "not_a_single_node"], [1, false, true, "classifier_unsafe"], [1, true, false, "native_methods_unusable"]]:
		var setup := _setup()
		_request(setup)
		_check(_attempt(setup, "1|1", args[0], args[1], args[2]).reason == args[3], "refused: %s" % args[3])
		_free(setup)

	var capped := _setup()
	_request(capped)
	_check(_attempt(capped, "1|1", 1, true, true, true).reason == "manual_pause", "a pause stops the action")
	_free(capped)
	var limited := _setup(true, {"max_allowed": 4})
	_request(limited)
	_check(_attempt(limited).reason == "above_allowed_maximum", "the allowed maximum is never crossed")
	_free(limited)
	var bottom := _setup(true, {"min_level": 4})
	_request(bottom, "lower")
	_check(_attempt(bottom).reason == "target_out_of_bounds", "the minimum level is never crossed")
	_free(bottom)

	var typed := _setup(true, {"action_type": "breach_government"})
	_check(_request(typed) == "type_not_allowed", "only the allowed type can act")
	_free(typed)
	var untyped := _setup(true, {"action_type": ""})
	_check(_request(untyped) == "no_action_type", "an armed actuator needs an explicit type")
	_free(untyped)


func _attempt_on_thread(setup: Dictionary) -> void:
	_thread_result = _attempt(setup)


func _test_not_main_thread() -> void:
	var setup := _setup()
	_request(setup)
	var thread := Thread.new()
	thread.start(_attempt_on_thread.bind(setup))
	thread.wait_to_finish()
	_check(_thread_result.get("reason") == "not_main_thread", "a call from another thread is refused")
	_check(setup.window.calls.is_empty(), "and nothing is called")
	_free(setup)


func _test_no_forced_action() -> void:
	for entry: Array in [["attack_in_progress", "detected", true], ["damage_present", "firewall", 40.0], ["damage_present", "breached", 3.0], ["paused", "paused", true], ["timer_not_armed", "time", 5.0]]:
		var setup := _setup()
		_request(setup)
		setup.window.set(entry[1], entry[2])
		var result := _attempt(setup)
		_check(result.outcome == "deferred" and result.reason == entry[0], "no safe window: %s" % entry[0])
		_check(setup.window.calls.is_empty() and setup.actuator.has_pending("breach_corps"), "%s calls nothing and keeps the action waiting" % entry[0])
		_free(setup)

	var waiting := _setup()
	_request(waiting, "lower")
	waiting.window.detected = true
	var starving := 0
	for i: int in 8:
		if _attempt(waiting, "1|%d" % i).starving:
			starving += 1
	_check(starving == 1, "a lower that finds no window is reported once")
	_check(waiting.actuator.deferred_total == 8, "every report is counted")
	_check(waiting.window.calls.is_empty(), "the protections are not bypassed")
	waiting.window.detected = false
	_check(_attempt(waiting, "1|9").outcome == "acted" and waiting.window.calls == ["down:1"], "the action happens at the next safe occasion")
	_free(waiting)


func _test_one_action() -> void:
	var setup := _setup()
	_check(_request(setup) == "", "a decision is accepted")
	_check(_request(setup) == "another_action_pending", "a second one waits for its turn")
	var done := _attempt(setup)
	_check(done.outcome == "acted" and setup.window.calls == ["up:1"], "one call, of one level")
	_check(setup.window.data.level == 5.0 and done.level_after == 5, "the level is read back")
	_check(setup.actuator.is_verifying(), "the action is not a success yet")
	_check(_request(setup, "raise", 5) == "previous_action_unverified", "no new action before the verification")
	_check(not setup.actuator.claims_level_change("breach_government", 5), "another type's change is not ours")
	_check(not setup.actuator.claims_level_change("breach_corps", 6), "another level is not ours")
	_check(setup.actuator.claims_level_change("breach_corps", 5), "the change is recognized as the mod's")
	_check(not setup.actuator.claims_level_change("breach_corps", 5), "only once")
	_free(setup)

	var again := _setup()
	_request(again)
	_attempt(again, "7|3")
	again.actuator.note_event("breach_corps", _attack(5), false)
	_request(again, "raise", 5)
	var same := _attempt(again, "7|3")
	_check(same.reason == "same_cycle" and again.window.calls.size() == 1, "at most one action per attack")
	_free(again)


func _test_incoherence() -> void:
	for entry: Array in [["ignored", "level_mismatch"], ["double", "level_mismatch"], ["starts_attack", "state_disturbed_by_action"]]:
		var setup := _setup()
		setup.window.behavior = entry[0]
		_request(setup)
		_attempt(setup)
		_check(setup.actuator.halt_reason == entry[1], "%s stops at once: %s" % [entry[0], setup.actuator.halt_reason])
		_check(not setup.actuator.is_verifying(), "%s leaves nothing to verify" % entry[0])
		_check(_request(setup) == "halted", "%s refuses anything after" % entry[0])
		_check(setup.actuator.take_new_halt() == entry[1] and setup.actuator.take_new_halt() == "", "%s is reported once" % entry[0])
		_free(setup)


func _verified_setup(expected: Dictionary = {}) -> Dictionary:
	var setup := _setup()
	_request(setup, "raise", 4, expected)
	_attempt(setup)
	setup.actuator.claims_level_change("breach_corps", 5)
	return setup


func _test_verification() -> void:
	var clean := _verified_setup({"used_min": 2.5, "used_max": 3.5, "may_fail": false})
	var fine: Dictionary = clean.actuator.note_event("breach_corps", _attack(5), false)
	_check(fine.outcome == "verified" and clean.actuator.halt_reason.is_empty(), "a normal next attack proves the action clean")
	_free(clean)

	var other := _verified_setup()
	_check(other.actuator.note_event("breach_government", _attack(3), false).is_empty() and other.actuator.is_verifying(), "another type's attack proves nothing")
	_free(other)

	var failed := _verified_setup({"may_fail": false})
	_check(failed.actuator.note_event("breach_corps", _attack(5, "failure_power"), false).reason == "forecast_refuted" and failed.actuator.halt_reason.is_empty(), "a failed attack blames the forecast, not the action")
	_free(failed)

	var cases: Array = [
		["failed", "action_reset_an_attack", {"event": "level_changed_reset", "level": 4}, true],
		["failed", "reset_unknown", {"event": "reset_unknown", "level": 5}, false],
		["failed", "failure_starved", {"event": "failure_starved", "level": 5}, false],
		["failed", "invalidated", {"event": "invalidated"}, false],
		["failed", "unexpected_level", _attack(4), false],
		["failed", "duration_out_of_range", _attack(5, "success", true, 5.9), false],
		["inconclusive", "next_attack_incomplete", _attack(5, "success", false), false],
	]
	for entry: Array in cases:
		var setup := _verified_setup({"used_min": 2.5, "used_max": 3.5})
		var result: Dictionary = setup.actuator.note_event("breach_corps", entry[2], entry[3])
		_check(result.outcome == entry[0] and result.reason == entry[1], "next attack %s: %s" % [entry[0], entry[1]])
		_check(setup.actuator.halt_reason.begins_with("verification_%s" % entry[0]), "%s stops the regulation" % entry[1])
		_free(setup)

	var manual := _verified_setup()
	var override: Dictionary = manual.actuator.note_event("breach_corps", {"event": "level_changed", "to": 3}, false)
	_check(override.outcome == "manual_override" and manual.actuator.halt_reason.is_empty(), "the player's change ends the verification, without blame")
	_free(manual)

	var quiet := _verified_setup()
	_check(quiet.actuator.advance(59.0).is_empty(), "the next attack is given time")
	_check(quiet.actuator.advance(2.0).reason == "no_attack_after_action", "an action never followed by an attack is not proven")
	_check(not quiet.actuator.halt_reason.is_empty(), "and it stops the regulation")
	_free(quiet)

	var loaded := _verified_setup()
	_check(loaded.actuator.on_reload().reason == "reload_during_verification", "a load during the verification ends it")
	_check(not loaded.actuator.halt_reason.is_empty(), "and it stops the regulation")
	_free(loaded)


func _test_stop_rules() -> void:
	var single := _setup(true, {"action_limit": 1})
	_request(single)
	_attempt(single)
	_check(single.actuator.halt_reason == "action_limit_reached", "the limit stops the regulation right after the action")
	_check(single.actuator.is_verifying(), "the verification still goes on")
	_check(single.actuator.note_event("breach_corps", _attack(5), false).outcome == "verified", "and it still concludes")
	_check(_request(single, "raise", 5) == "halted" and single.window.calls.size() == 1, "and no second action can follow")
	_free(single)

	var stopped := _setup()
	_request(stopped)
	stopped.actuator.halt("emergency_stop")
	_check(not stopped.actuator.has_pending("breach_corps"), "the emergency stop drops the waiting action")
	_check(_attempt(stopped).is_empty() and _request(stopped) == "halted" and stopped.window.calls.is_empty(), "nothing can act after it")
	_check(not stopped.actuator.can_act() and stopped.actuator.is_armed(), "a stopped actuator cannot act")
	_free(stopped)

	var cancelled := _setup()
	_request(cancelled)
	_check(cancelled.actuator.cancel_pending("breach_government").is_empty(), "cancelling another type changes nothing")
	_check(cancelled.actuator.cancel_pending("breach_corps").direction == "raise", "a waiting action can be cancelled")
	_check(_attempt(cancelled).is_empty(), "and it does not happen")
	_free(cancelled)
	var summary: String = _setup_summary()
	_check(summary.contains("deferred_no_safe_window=1") and summary.contains("armed=true"), "the summary counts the reports")


const MARKER := "user://smart_automation_test/trial_used.json"


func _trial(window_level: float) -> Dictionary:
	var settings := FakeSettings.new()
	var window := FakeWindow.new()
	window.data.level = window_level
	var actuator := TrialActuator.new(true, {"attributes": settings, "data": settings}, {
		"action_limit": Actuator.Policy.TRIAL_MAX_ACTIONS, "action_type": Actuator.Policy.TRIAL_TYPE, "marker_path": MARKER, "verify_attacks": 3,
	})
	return {"actuator": actuator, "window": window, "settings": settings}


func _trial_attempt(setup: Dictionary, type: String, direction: String, level: int, expected: Dictionary = {"status": "reliable", "p_success": 1.0}) -> Dictionary:
	var power := {"damage_rate": 30.0, "infection_rate": 30.0, "vulnerability": 0.0}
	setup.actuator.action_type = type
	setup.actuator.request(type, direction, level, power, expected, {"reason": "conditions_met"})
	return setup.actuator.attempt(type, setup.window, "1|%d" % setup.actuator.actions_done, 1, true, true, false)


func _test_trial_limits() -> void:
	var policy := Actuator.Policy
	_check(policy.TRIAL_TYPE == "breach_government" and policy.TRIAL_MIN_LEVEL == 0 and policy.TRIAL_MAX_LEVEL == 4, "the trial is the authorized one")
	_check(policy.TRIAL_MAX_ACTIONS == 4 and policy.TRIAL_PROFILE == "conservative" and policy.TRIAL_MIN_GAP == 60.0, "with 4 actions, in the conservative profile, 60 s apart")
	_check(not policy.TRIAL_MARKER.ends_with("trial_used.json") and not policy.TRIAL_MARKER.ends_with("trial_2_used.json"), "earlier markers are left alone")
	DirAccess.remove_absolute(MARKER)
	for entry: Array in [["breach_corps", "raise", 2.0, 2], ["breach_government", "raise", 4.0, 4], ["breach_government", "lower", 5.0, 5], ["breach_government", "raise", 5.0, 5]]:
		var outside := _trial(entry[2])
		outside.window.data.max_level = 6.0
		var result := _trial_attempt(outside, entry[0], entry[1], entry[3])
		_check(result.reason == "outside_trial" and outside.window.calls.is_empty(), "the trial refuses %s %s from %d" % [entry[0], entry[1], entry[3]])
		_check(not FileAccess.file_exists(MARKER), "a refusal does not use up the trial")
		_free(outside)

	for expected: Dictionary in [{}, {"status": "uncertain", "p_success": 1.0}, {"status": "invalid"}, {"status": "reliable", "p_success": 0.99}, {"status": "reliable", "p_success": 0.0}]:
		var weak := _trial(2.0)
		var result := _trial_attempt(weak, "breach_government", "raise", 2, expected)
		_check(result.reason == "target_forecast_not_reliable" and weak.window.calls.is_empty(), "no change towards a level not forecast safe: %s" % str(expected))
		_free(weak)

	var busy := _trial(2.0)
	busy.window.detected = true
	_check(_trial_attempt(busy, "breach_government", "raise", 2).outcome == "deferred", "the trial waits for a safe window")
	_check(busy.window.calls.is_empty() and not FileAccess.file_exists(MARKER), "waiting does not use up the trial")
	_free(busy)

	# Four changes, with a verification and a delay between each: never more.
	var chain := _trial(0.0)
	for action: int in 4:
		var level: int = chain.window.data.level
		var result := _trial_attempt(chain, "breach_government", "raise", level)
		_check(result.outcome == "acted", "change %d is made: %s" % [action + 1, str(result)])
		_check(FileAccess.file_exists(MARKER), "the marker is written")
		if action == 3:
			break
		_check(chain.actuator.halt_reason.is_empty(), "the regulation goes on after change %d" % (action + 1))
		_check(_trial_attempt(chain, "breach_government", "raise", level + 1).is_empty() or chain.actuator.is_verifying(), "no change before the verification")
		chain.actuator.claims_level_change("breach_government", level + 1)
		for attack: int in 3:
			chain.actuator.note_event("breach_government", _attack(level + 1), false)
		_check(not chain.actuator.is_verifying(), "it concludes after 3 attacks")
		_check(_trial_attempt(chain, "breach_government", "raise", level + 1).reason == "too_soon_after_last_action", "the next change must wait")
		_check(chain.window.calls.size() == action + 1, "and nothing happens")
		chain.actuator.advance(Actuator.Policy.TRIAL_MIN_GAP + 1.0)
	_check(chain.window.calls == ["up:1", "up:1", "up:1", "up:1"] and chain.window.data.level == 4.0, "four calls in all: %s" % str(chain.window.calls))
	_check(chain.actuator.halt_reason == "action_limit_reached", "the regulation stops at the limit")
	_check(_trial_attempt(chain, "breach_government", "lower", 4) == {} and chain.window.calls.size() == 4, "a fifth change is impossible")
	var marker_text := FileAccess.get_file_as_string(MARKER)
	_check(marker_text.contains("\"actions\":4"), "the marker counts them: %s" % marker_text)
	_free(chain)

	var restarted := _trial(2.0)
	_check(_trial_attempt(restarted, "breach_government", "raise", 2).reason == "trial_already_used", "a new session cannot act, even with actions left")
	_check(restarted.window.calls.is_empty(), "and nothing moves")
	_free(restarted)
	DirAccess.remove_absolute(MARKER)

	var paused := _trial(2.0)
	paused.actuator.action_type = "breach_government"
	paused.actuator.request("breach_government", "raise", 2, {"damage_rate": 30.0, "infection_rate": 30.0, "vulnerability": 0.0}, {"status": "reliable", "p_success": 1.0}, {})
	_check(paused.actuator.attempt("breach_government", paused.window, "1|1", 1, true, true, true).reason == "manual_pause", "a pause is checked right before the call")
	_check(paused.window.calls.is_empty() and not FileAccess.file_exists(MARKER), "and nothing is called")
	_free(paused)

	var unwritable := _trial(2.0)
	unwritable.actuator._marker_path = "user://smart_automation_test/trial_used.json/not_a_folder/marker.json"
	DirAccess.make_dir_recursive_absolute("user://smart_automation_test")
	var marker_file := FileAccess.open(MARKER, FileAccess.WRITE)
	marker_file.close()
	var refused := _trial_attempt(unwritable, "breach_government", "raise", 2)
	_check(refused.reason == "trial_marker_unwritable" and unwritable.window.calls.is_empty(), "no marker, no action")
	_check(unwritable.actuator.halt_reason == "trial_marker_unwritable", "and it stops")
	_free(unwritable)
	DirAccess.remove_absolute(MARKER)

	# The player's real figures, read from the session logs.
	var profile := {"damage_rate": 35.3078, "infection_rate": 0.0, "vulnerability": 0.0, "breach_variation": 0, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0}
	var level_3 := Forecast.forecast(profile, {"firewall": 68.0, "breach": 68.0, "time": 6.0}, 0.2)
	_check(level_3.status == "reliable" and is_equal_approx(level_3.p_success, 1.0), "level 3 respects the margin at 35.31 damage: %s" % str(level_3))
	var level_4 := Forecast.forecast(profile, {"firewall": 101.0, "breach": 101.0, "time": 6.0}, 0.2)
	_check(level_4.status == "reliable" and level_4.p_success < 1.0, "level 4 does not, so the raises stop at 3: %s" % str(level_4))


func _setup_summary() -> String:
	var setup := _setup()
	_request(setup)
	setup.window.detected = true
	_attempt(setup)
	var text: String = setup.actuator.summary()
	_free(setup)
	return text


func _feed(regulator: Regulator, count: int, event: String, level: int, current: Dictionary, next: Dictionary) -> Array[Dictionary]:
	var decisions: Array[Dictionary] = []
	for i: int in count:
		regulator.advance(4.0)
		decisions.append(regulator.on_attack({"event": event, "complete": true, "level": level, "max_level": 99, "signature": "s"}, current, next))
	return decisions


func _test_regulator_support() -> void:
	var reliable := {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 3.0, "infected": false}
	for status: Dictionary in [{"status": "uncertain"}, {"status": "invalid"}, {}]:
		var regulator := Regulator.new("balanced")
		var decisions := _feed(regulator, 30, "failure_power", 5, status, {})
		var lowers := decisions.filter(func(d: Dictionary) -> bool: return d.decision == "lower")
		_check(lowers.is_empty() and decisions.back().reason == "forecast_not_reliable", "no lower without a reliable forecast: %s" % str(status))
		_check(decisions.back().window_failures >= 2, "the failures stay visible in the log")

	var proposing := Regulator.new("aggressive")
	var first: Dictionary = _feed(proposing, 10, "success", 4, {}, reliable).filter(func(d: Dictionary) -> bool: return d.decision == "raise")[0]
	_check(first.window_attacks > 0 and first.successes_in_row >= 2 and first.margin == 0.0, "a decision carries its evidence")
	proposing.cancel_last_action()
	_check(proposing._actions.is_empty(), "a cancelled action costs no budget")
	var retry := _feed(proposing, 1, "success", 4, {}, reliable)
	_check(retry[0].decision == "raise", "and it can be proposed again")

	var lowering := Regulator.new("balanced")
	_feed(lowering, 2, "success", 6, {}, {})
	var hopeless := {"status": "reliable", "outcome": "fail", "p_success": 0.0}
	_check(_feed(lowering, 2, "failure_power", 6, hopeless, {}).back().decision == "lower", "a lower is proposed")
	_check(lowering._blocked.has(6), "it blocks the level")
	lowering.cancel_last_action()
	_check(not lowering._blocked.has(6), "cancelling it lifts the block")

	var stale := Regulator.new("balanced")
	_feed(stale, 2, "success", 6, {}, {})
	_feed(stale, 2, "failure_power", 6, hopeless, {})
	stale.advance(4.0)
	stale.on_attack({"event": "success", "complete": true, "level": 6, "max_level": 99, "signature": "other"}, {}, {})
	stale.cancel_last_action()
	_check(stale._blocked.is_empty(), "cancelling after a power change does not bring old blocks back")

	var speed := Regulator.new("balanced")
	_feed(speed, 2, "success", 6, {}, {})
	_feed(speed, 1, "failure_power", 6, hopeless, {})
	speed.on_speed_changed()
	_check(speed._history.is_empty(), "attacks seen at another speed are forgotten")
	_check(_feed(speed, 1, "failure_power", 6, hopeless, {})[0].reason == "stabilizing", "and the regulator stabilizes again")


## The anti-oscillation figures asked for the review: the regulator's decisions are applied to a
## simulated game with random attacks. One attack lasts 4 s, so 20000 attacks are about 22 hours.
func _closed_loop(profile: String, seed_value: int, attacks: int, chance: Callable, forecast: Callable) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var regulator := Regulator.new(profile)
	var accepted: float = Regulator.PROFILES[profile].p
	var level := 0
	var result := {"reversals": 0, "moves": 0, "unjustified_lowers": 0, "at_best": 0, "failures": 0}
	var last := ""
	for attack: int in attacks:
		var progress := float(attack) / attacks
		regulator.advance(4.0)
		var true_chance: float = chance.call(level, progress)
		var success := random.randf() < true_chance
		result.failures += 0 if success else 1
		var best := 0
		while chance.call(best + 1, progress) >= accepted:
			best += 1
		result.at_best += 1 if level == best else 0
		var decision := regulator.on_attack(
			{"event": "success" if success else "failure_power", "complete": true, "level": level, "max_level": 30, "signature": "power%d" % floori(progress * 3.0)},
			{"status": "reliable", "p_success": forecast.call(level, progress)},
			{"status": "reliable", "p_success": forecast.call(level + 1, progress), "used_nominal": 3.0, "infected": false})
		if decision.decision == "hold":
			continue
		result.moves += 1
		if decision.decision == "lower" and true_chance >= accepted:
			result.unjustified_lowers += 1
		if not last.is_empty() and last != decision.decision:
			result.reversals += 1
		last = decision.decision
		level = decision.assumed_level
		regulator.on_level_changed(level)
	return result


func _test_closed_loop() -> void:
	var step := func(best: int) -> Callable:
		return func(level: int, _progress: float) -> float: return 1.0 if level <= best else 0.0
	var marginal := func(level: int, _progress: float) -> float:
		if level <= 6:
			return 1.0
		return 0.97 if level == 7 else 0.0
	var changing := func(level: int, progress: float) -> float:
		var best: int = [5, 8, 6][floori(progress * 3.0)]
		return 1.0 if level <= best else 0.0
	var scenarios := {"stable": [step.call(8), step.call(8)], "marginal_97": [marginal, marginal], "wrong_forecast": [step.call(8), step.call(9)], "power_changes": [changing, changing]}
	for scenario: String in scenarios:
		for profile: String in Regulator.PROFILES:
			var total := {"reversals": 0, "moves": 0, "unjustified_lowers": 0, "at_best": 0, "failures": 0}
			var seeds := [1, 2, 3, 4, 5]
			for seed_value: int in seeds:
				var run_result := _closed_loop(profile, seed_value, 20000, scenarios[scenario][0], scenarios[scenario][1])
				for key: String in total:
					total[key] += run_result[key]
			var share: float = float(total.at_best) / (20000.0 * seeds.size()) * 100.0
			print("closed loop %s %s, 5 x 22 h: reversals %d, moves %d, unjustified lowers %d, failures %d, at best level %.1f%%" % [scenario, profile, total.reversals, total.moves, total.unjustified_lowers, total.failures, share])
			if scenario != "marginal_97":
				_check(total.unjustified_lowers == 0, "%s %s: no lower of a level that works" % [scenario, profile])
			if scenario == "stable":
				_check(total.reversals == 0 and share > 99.0, "%s %s stays at the best level" % [scenario, profile])
			if scenario == "marginal_97" and profile == "aggressive":
				_check(total.unjustified_lowers <= 10, "chance rarely lowers a level inside the accepted risk: %d" % total.unjustified_lowers)
			if scenario == "wrong_forecast":
				# Blocks last until the power changes, which this scenario does twice per run.
				_check(total.reversals <= seeds.size() * 5, "%s %s: a refuted level is tried once per power: %d" % [scenario, profile, total.reversals])
