extends SceneTree
## Simulated tests. Run with:
## Godot_console.exe --headless --path . --script res://tests/run_tests.gd
## These scenarios are built from our reading of the game: they do not replace the in-game tests.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/"
const Classifier := preload(MOD + "features/threat_manager/breach_classifier.gd")
const Prediction := preload(MOD + "features/threat_manager/breach_prediction.gd")
const Simulator := preload(MOD + "features/threat_manager/breach_simulator.gd")
const Observer := preload(MOD + "features/threat_manager/threat_observer.gd")
const ApiGuard := preload(MOD + "core/api_guard.gd")
const SaLog := preload(MOD + "core/sa_log.gd")
const ModMain := preload(MOD + "mod_main.gd")
const RegulationTests := preload("regulation_tests.gd")
const GapProbeTests := preload("gap_probe_tests.gd")
const ActuatorTests := preload("actuator_tests.gd")
const Actuator := preload(MOD + "features/threat_manager/threat_actuator.gd")

const TICK := 0.05
const TIME_LIMIT := 120

var _failures := 0
var _checks := 0


class FakeSignals extends Node:
	signal tick
	signal breached(window)
	signal window_created(window)
	signal window_initialized(window)
	signal window_deleted(window)
	signal desktop_ready
	signal setting_set(setting)


class FakeGlobals extends Node:
	var desktop: Variant


class FakeAttributes extends Node:
	var tick_speed := TICK


class FakeData extends Node:
	var auto_level_breach := false


class FakeDesktop extends Node:
	var windows: Node


class FakeResource:
	var production := 100.0
	var count := 0.0
	var variation := 0


class FakeBreach extends Node:
	var window := "breach_corps"
	var data := {"level": 3.0, "max_level": 5.0}
	var time := 10.0
	var max_time := 10.0
	var detected := false
	var firewall := 50.0
	var max_firewall := 50.0
	var breached := 0.0
	var max_breach := 50.0
	var paused := false
	var breach_damage := FakeResource.new()
	var infection_damage := FakeResource.new()
	var vulnerability := FakeResource.new()
	var forbidden_calls := 0

	func get_max_firewall(level: int) -> float:
		return 50.0 * pow(1.5, level - 3)

	func get_max_breach(level: int) -> float:
		return 50.0 * pow(1.5, level - 3)

	func get_max_time(level: int) -> float:
		return 20.0 if is_elite(level) else 10.0

	func is_elite(level: int) -> bool:
		return level > 0 and level % 5 == 0

	func level_up(_times: int) -> void:
		forbidden_calls += 1

	func level_down(_times: int) -> void:
		forbidden_calls += 1


## Follows what we think the game does when its level methods are called.
class ActingBreach extends FakeBreach:
	var calls: Array[String] = []
	var fixed_time := 0.0
	var true_hit := 0.0

	func _init() -> void:
		var main := VBoxContainer.new()
		main.name = "MainContainer"
		var actions := HBoxContainer.new()
		actions.name = "ActionContainer"
		var raise := Button.new()
		raise.name = "AddButton"
		raise.theme_type_variation = &"ButtonActionBlue"
		actions.add_child(raise)
		main.add_child(actions)
		add_child(main)

	func get_max_time(level: int) -> float:
		return fixed_time if fixed_time > 0.0 else super(level)

	func level_up(steps: int) -> void:
		calls.append("up:%d" % steps)
		data.level += steps
		_rearm()

	func level_down(steps: int) -> void:
		calls.append("down:%d" % steps)
		data.level -= steps
		_rearm()

	func _rearm() -> void:
		max_firewall = get_max_firewall(int(data.level))
		firewall = max_firewall
		max_breach = get_max_breach(int(data.level))
		max_time = get_max_time(int(data.level))
		time = max_time


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


class TrialObserver extends Observer:
	func _actions_allowed() -> bool:
		return true

	func _new_actuator(armed: bool) -> Observer.ThreatActuator:
		return TrialActuator.new(armed, {"attributes": _attributes, "data": _data}, {
			"action_limit": _regulation.action_limit, "action_type": _regulation.action_type,
			"min_level": _regulation.min_level, "max_allowed": _regulation.max_allowed_level,
			"action_types": _regulation.action_types, "verify_attacks": Observer.Policy.TRIAL_VERIFY_ATTACKS, "marker_path": "user://smart_automation_test/observer_trial_used.json",
		})


## Only the tests open both locks.
class ArmedObserver extends Observer:
	func _actions_allowed() -> bool:
		return true

	func _accepts_active_without_trial() -> bool:
		return true

	func _new_actuator(armed: bool) -> Observer.ThreatActuator:
		return ArmedActuator.new(armed, {"attributes": _attributes, "data": _data}, {
			"action_limit": _regulation.action_limit, "action_type": _regulation.action_type,
			"min_level": _regulation.min_level, "max_allowed": _regulation.max_allowed_level,
		})


## A window of a type the mod watches, without the game's getters.
class FakeGetterless extends Node:
	var window := "breach_government"
	var data := {"level": 1.0, "max_level": 2.0}
	var time := 10.0
	var max_time := 10.0
	var detected := false
	var firewall := 50.0
	var max_firewall := 50.0
	var breached := 0.0
	var max_breach := 50.0
	var paused := false
	var breach_damage := FakeResource.new()
	var infection_damage := FakeResource.new()
	var vulnerability := FakeResource.new()


func _initialize() -> void:
	# A runtime error ends _run before it can quit: fail instead of hanging.
	create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run.call_deferred()


func _on_time_limit() -> void:
	printerr("FAILED: the tests did not finish within %d s, a script error probably stopped them" % TIME_LIMIT)
	print("%d checks, %d failures" % [_checks, _failures + 1])
	quit(2)


func _run() -> void:
	for script: GDScript in [Classifier, Prediction, Simulator, Observer, ApiGuard, SaLog, ModMain, RegulationTests, GapProbeTests, ActuatorTests, Actuator]:
		_check(script.can_instantiate(), "compiles: %s" % script.resource_path)
	if _failures > 0:
		print("%d checks, %d failures" % [_checks, _failures])
		quit(1)
		return
	_test_success()
	_test_power_failure()
	_test_hidden_reset()
	_test_level_change_during_attack()
	_test_idle_level_change()
	_test_starved()
	_test_paused()
	_test_partial_reload()
	_test_unknown_reset()
	_test_replaced_instance()
	_test_fast_successes()
	_test_success_without_observed_cycle()
	_test_simulation_speed()
	_test_native_auto_level()
	_test_prediction()
	_test_volley_model()
	_test_simulator()
	_test_infection_measures()
	_test_guard()
	_test_no_level_change_in_source()
	await _test_observer()
	await _test_government_and_native_values()
	await _test_mod_main()
	RegulationTests.new().run(_check)
	await _test_dry_run_in_observer()
	GapProbeTests.new().run(_check)
	await _test_gap_probe_in_observer()
	ActuatorTests.new().run(_check)
	await _test_actions_in_observer()
	await _test_trial_in_observer()
	await _test_automation_control()
	await _test_descent_in_observer()
	await _test_announced_damage_in_observer()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _sample(overrides: Dictionary = {}) -> Dictionary:
	var sample := {
		"instance_id": 1, "level": 3, "max_level": 5, "time": 10.0, "max_time": 10.0,
		"detected": false, "paused": false, "firewall": 50.0, "max_firewall": 50.0,
		"breached": 0.0, "max_breach": 50.0, "damage_rate": 100.0, "vulnerability": 0.0,
		"breach_variation": 0, "infection_count": 0.0, "infection_rate": 0.0, "infection_variation": 0,
		"tick_speed": TICK, "now_usec": 0,
	}
	sample.merge(overrides, true)
	return sample


## Runs a full attack from idle down to time_end, dealing damage at every tick.
func _attack(classifier: Classifier, time_end: float, tick: float = TICK, deals_damage: bool = true) -> void:
	classifier.observe(_sample())
	var time := 10.0
	var dealt := 0.0
	while time - tick >= time_end - 1e-6:
		time -= tick
		if deals_damage:
			dealt += 0.01
		classifier.observe(_sample({"time": time, "detected": true, "firewall": 50.0 - dealt}))


func _names(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> String: return e.event)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAILED: ", label)


func _test_success() -> void:
	var c := Classifier.new()
	_attack(c, 7.0)
	var events := c.on_breached(_sample({"time": 7.0, "detected": true}))
	_check(_names(events) == ["success"], "success emits one event")
	_check(is_equal_approx(events[0].time_left, 7.0), "success keeps the time left")
	_check(is_equal_approx(events[0].ratio, 0.3), "success computes the ratio")
	_check(events[0].complete, "observed attack is complete")
	_check(c.observe(_sample()).is_empty(), "the reset after a success is not classified")
	_check(c.state == Classifier.State.IDLE, "idle after success")


func _test_power_failure() -> void:
	var c := Classifier.new()
	_attack(c, TICK)
	_check(c.state == Classifier.State.ATTACKING, "attacking during the attack")
	var events := c.observe(_sample())
	_check(_names(events) == ["failure_power"], "expired timer with progress is failure_power")


func _test_hidden_reset() -> void:
	var c := Classifier.new()
	_attack(c, TICK)
	var events := c.observe(_sample({"time": 10.0 - TICK, "detected": true, "firewall": 49.0}))
	_check(_names(events) == ["failure_power"], "a rising timer reveals a reset hidden by new damage")
	_check(c.state == Classifier.State.ATTACKING, "the next attack is tracked")
	var next := c.on_breached(_sample({"time": 9.0, "detected": true}))
	_check(next[0].cycle_id == 2, "the next attack has its own cycle id")
	_check(next[0].complete, "the attack that restarted in the same tick stays complete")


func _test_level_change_during_attack() -> void:
	for level: int in [2, 4]:
		var c := Classifier.new()
		_attack(c, 8.0)
		var events := c.observe(_sample({"level": level}))
		_check(_names(events) == ["level_changed_reset"], "manual level change is never a failure")
	var late := Classifier.new()
	_attack(late, TICK)
	_check(_names(late.observe(_sample({"level": 4}))) == ["level_changed_reset"], "even with the timer almost expired")


func _test_idle_level_change() -> void:
	var c := Classifier.new()
	c.observe(_sample())
	_check(_names(c.observe(_sample({"level": 4}))) == ["level_changed"], "idle level change is logged")


func _test_starved() -> void:
	var c := Classifier.new()
	_attack(c, TICK, TICK, false)
	_check(_names(c.observe(_sample())) == ["failure_starved"], "no damage at all is failure_starved")

	var later := Classifier.new()
	later.observe(_sample())
	later.observe(_sample({"time": 9.95, "detected": true, "firewall": 40.0}))
	var time := 9.95
	while time > TICK + 1e-6:
		time -= TICK
		later.observe(_sample({"time": time, "detected": true, "firewall": 40.0}))
	_check(_names(later.observe(_sample())) == ["failure_starved"], "damage that stopped early is failure_starved")


func _test_paused() -> void:
	var c := Classifier.new()
	c.observe(_sample())
	c.observe(_sample({"time": 5.0, "detected": true, "firewall": 40.0, "paused": true}))
	_check(c.state == Classifier.State.SUSPENDED, "pause suspends")
	c.observe(_sample({"time": 5.0 - TICK, "detected": true, "firewall": 39.0, "paused": true}))
	var events := c.observe(_sample({"time": TICK, "detected": true, "firewall": 30.0, "paused": true}))
	_check(events.is_empty(), "no event while paused")
	_check(_names(c.observe(_sample({"paused": true}))) == ["failure_paused"], "expiry during a pause is failure_paused")


func _test_partial_reload() -> void:
	var c := Classifier.new()
	c.observe(_sample({"time": 6.0, "detected": true, "firewall": 30.0}))
	var time := 6.0
	var firewall := 30.0
	while time > TICK + 1e-6:
		time -= TICK
		firewall -= 0.01
		c.observe(_sample({"time": time, "detected": true, "firewall": firewall}))
	var events := c.observe(_sample())
	_check(_names(events) == ["reset_unknown"], "failure of a partial cycle is not failure_power")
	_check(events[0].clues == "partial_cycle", "the clue names the partial cycle")

	var ok := Classifier.new()
	ok.observe(_sample({"time": 6.0, "detected": true, "firewall": 30.0}))
	var success := ok.on_breached(_sample({"time": 5.0, "detected": true}))
	_check(not success[0].complete, "success of a partial cycle is incomplete")


func _test_unknown_reset() -> void:
	var c := Classifier.new()
	_attack(c, 6.0)
	var events := c.observe(_sample())
	_check(_names(events) == ["reset_unknown"], "reset with time left is unknown")
	_check(events[0].clues.contains("time_not_expired"), "clue: time had not expired")

	var not_rearmed := Classifier.new()
	_attack(not_rearmed, TICK)
	var other := not_rearmed.observe(_sample({"time": 5.0}))
	_check(other[0].clues.contains("time_not_rearmed"), "clue: timer not back to its maximum")


func _test_replaced_instance() -> void:
	var c := Classifier.new()
	_attack(c, 5.0)
	var events := c.observe(_sample({"instance_id": 2}))
	_check(_names(events) == ["invalidated"], "a new instance invalidates the cycle")
	var gone := Classifier.new()
	_attack(gone, 5.0)
	_check(_names(gone.invalidate("window_deleted")) == ["invalidated"], "deletion invalidates the cycle")
	_check(gone.state == Classifier.State.UNBOUND, "unbound after invalidation")
	_check(gone.invalidate("again").is_empty(), "invalidating twice reports nothing")


func _test_fast_successes() -> void:
	var c := Classifier.new()
	c.observe(_sample())
	var ids := []
	for i: int in 5:
		var events := c.on_breached(_sample({"time": 10.0, "detected": true}))
		_check(_names(events) == ["success"], "one observation per fast attack")
		ids.append(events[0].cycle_id)
	_check(ids == [1, 2, 3, 4, 5], "each fast attack has its own cycle")
	_check(c.observe(_sample()).is_empty(), "nothing to classify afterwards")


func _test_success_without_observed_cycle() -> void:
	var c := Classifier.new()
	c.observe(_sample())
	var events := c.on_breached(_sample({"time": 9.9, "detected": true}))
	_check(not events[0].observed_start, "an attack seen only through its signal is flagged")


func _test_simulation_speed() -> void:
	var fast_tick := 0.5
	var c := Classifier.new()
	c.observe(_sample({"tick_speed": fast_tick}))
	var time := 10.0
	var firewall := 50.0
	while time > fast_tick + 1e-6:
		time -= fast_tick
		firewall -= 1.0
		c.observe(_sample({"time": time, "detected": true, "firewall": firewall, "tick_speed": fast_tick}))
	var events := c.observe(_sample({"tick_speed": fast_tick}))
	_check(_names(events) == ["failure_power"], "a higher speed keeps the failure classified")

	# Measured in the game: a change of speed during an attack shifts the time used by 0.15 s.
	var mixed := Classifier.new()
	_attack(mixed, 8.0)
	mixed.observe(_sample({"time": 7.75, "detected": true, "firewall": 40.0, "tick_speed": 0.25}))
	_check(not mixed.on_breached(_sample({"time": 7.5, "detected": true, "firewall": 30.0, "tick_speed": 0.25}))[0].complete, "a speed change during the attack makes the measure incomplete")

	var mixed_failure := Classifier.new()
	_attack(mixed_failure, 5.0)
	var mixed_time := 4.75
	var mixed_firewall := 30.0
	mixed_failure.observe(_sample({"time": mixed_time, "detected": true, "firewall": mixed_firewall, "tick_speed": 0.25}))
	while mixed_time > 0.25 + 1e-6:
		mixed_time -= 0.25
		mixed_firewall -= 0.5
		mixed_failure.observe(_sample({"time": mixed_time, "detected": true, "firewall": mixed_firewall, "tick_speed": 0.25}))
	var mixed_events := mixed_failure.observe(_sample({"tick_speed": 0.25}))
	_check(mixed_events[0].clues == "speed_changed", "a failure across a speed change is not failure_power, got: %s" % mixed_events[0].get("clues", mixed_events[0].event))

	var slow := Classifier.new()
	_attack(slow, 8.0)
	_check(_names(slow.observe(_sample({"tick_speed": fast_tick}))) == ["reset_unknown"], "speed change does not turn a reset into a failure")


func _test_native_auto_level() -> void:
	var c := Classifier.new()
	_attack(c, 6.0)
	var events := c.on_breached(_sample({"time": 6.0, "detected": true, "level": 4}))
	_check(events[0].level == 3, "the success is credited to the attacked level")
	_check(events[0].level_after == 4, "the native raise is recorded")
	_check(events[0].complete, "the measure stays usable")
	_check(_names(c.observe(_sample({"level": 4}))) == ["level_changed"], "native raise is logged, not a failure")


func _test_prediction() -> void:
	_check(not Prediction.is_elite(0), "level 0 is not elite")
	_check(Prediction.is_elite(5) and Prediction.is_elite(10), "multiples of 5 are elite")
	_check(is_equal_approx(Prediction.ratio_factor(1), 1.5), "normal to normal")
	_check(is_equal_approx(Prediction.ratio_factor(4), 3.75), "normal to elite")
	_check(is_equal_approx(Prediction.ratio_factor(5), 0.6), "elite to normal")
	_check(is_equal_approx(Prediction.next_ratio(0.2, 4), 0.75), "next ratio")

	var a := {"complete": true, "level": 3, "damage_rate": 100.0, "max_firewall": 50.0, "max_breach": 50.0}
	var b := {"complete": true, "level": 4, "damage_rate": 102.0, "max_firewall": 75.0, "max_breach": 75.0}
	_check(Prediction.incomparable_reason(a, b) == "", "comparable measures")
	_check(Prediction.incomparable_reason(a, b.merged({"complete": false}, true)) == "incomplete", "incomplete")
	_check(Prediction.incomparable_reason(a, b.merged({"level": 6}, true)) == "not_consecutive", "not consecutive")
	_check(Prediction.incomparable_reason(a, b.merged({"damage_rate": 120.0}, true)) == "damage_changed", "damage changed")
	_check(Prediction.incomparable_reason(a, b.merged({"damage_rate": 0.0}, true)) == "no_damage_rate", "no damage rate")
	_check(Prediction.incomparable_reason(a, b.merged({"max_firewall": 200.0}, true)) == "difficulty_changed", "difficulty changed")


## Figures measured in the game on 2026-10-31: level 2, firewall 18, breach 72, 25.8 damage per second.
func _measured_success(overrides: Dictionary = {}) -> Dictionary:
	var success := {
		"complete": true, "level": 2, "volleys": 4, "used": 3.0, "max_time": 5.0, "damage_rate": 25.8,
		"vulnerability": 0.0, "max_firewall": 18.0, "max_breach": 72.0,
	}
	success.merge(overrides, true)
	return success


func _test_volley_model() -> void:
	_check(Prediction.volleys_needed(18.0, 72.0, 25.8) == 4, "the firewall excess of a volley is lost")
	_check(Prediction.volleys_needed(45.0, 45.0, 25.8) == 4, "the second node of the measured setup")
	_check(Prediction.volleys_needed(0.0, 72.0, 25.8) == 3, "no firewall")

	var model := Prediction.volley_model(_measured_success())
	_check(model.model_volleys == 4, "the model reproduces the measured level")
	_check(model.next_volleys == 7, "level 3 needs 7 volleys")
	_check(is_equal_approx(model.next_used, 6.0), "level 3 needs 6 seconds")
	_check(is_equal_approx(model.next_model_ratio, 1.2), "level 3 is predicted to fail")
	_check(Prediction.next_ratio(0.6, 2) < 1.0, "while the coefficient alone predicts success")

	var to_elite := Prediction.volley_model(_measured_success({"level": 4}))
	_check(is_equal_approx(to_elite.next_max_time, 10.0), "an elite level doubles the time")
	var from_elite := Prediction.volley_model(_measured_success({"level": 5, "max_time": 10.0}))
	_check(is_equal_approx(from_elite.next_max_time, 5.0), "leaving an elite level halves the time")
	_check(Prediction.volley_model(_measured_success({"complete": false})).is_empty(), "no model from a partial measure")
	_check(Prediction.volley_model(_measured_success({"volleys": 1})).is_empty(), "no model without an interval")

	# Measured in the game: 40.865 per second gave 5 volleys, 6 in 14% of the attacks and 7 once.
	var random_hits := Prediction.volley_model(_measured_success({
		"level": 4, "volleys": 5, "used": 4.0, "max_time": 6.0, "damage_rate": 40.865,
		"max_firewall": 40.4, "max_breach": 161.6,
	}))
	_check(random_hits.model_volleys == 5, "lucky hits of 41 need 5 volleys")
	_check(random_hits.model_volleys_worst == 7, "hits of 40 need 7 volleys, the worst case seen")

	var whole := Prediction.volley_model(_measured_success({"damage_rate": 26.0}))
	_check(whole.model_volleys == whole.model_volleys_worst, "a whole damage value has a single outcome")
	_check(Prediction.volley_model(_measured_success({"damage_rate": 0.5})).is_empty(), "a hit rounding down to 0 gives no model")

	var changed := Classifier.new()
	_attack(changed, 6.0)
	changed.observe(_sample({"time": 5.95, "detected": true, "firewall": 30.0, "damage_rate": 200.0}))
	_check(not changed.on_breached(_sample({"time": 5.9, "detected": true, "firewall": 20.0, "damage_rate": 200.0}))[0].complete, "damage changing during the attack makes the measure incomplete")

	var lost := Classifier.new()
	_attack(lost, 5.0)
	var lost_time := 4.9
	var lost_firewall := 30.0
	lost.observe(_sample({"time": lost_time, "detected": true, "firewall": lost_firewall, "damage_rate": 50.0}))
	while lost_time > TICK + 1e-6:
		lost_time -= TICK
		lost_firewall -= 0.01
		lost.observe(_sample({"time": lost_time, "detected": true, "firewall": lost_firewall, "damage_rate": 50.0}))
	var lost_events := lost.observe(_sample({"damage_rate": 50.0}))
	_check(_names(lost_events) == ["reset_unknown"], "a failure while the damage changed is not failure_power")
	_check(lost_events[0].clues == "damage_changed", "the clue names the damage change, got: %s" % lost_events[0].clues)

	var hits := Classifier.new()
	hits.observe(_sample())
	hits.observe(_sample({"time": 9.95, "detected": true, "firewall": 0.0}))
	hits.observe(_sample({"time": 9.9, "detected": true, "firewall": 0.0, "breached": 40.0}))
	var hit_events := hits.on_breached(_sample({"time": 9.85, "detected": true, "firewall": 0.0, "breached": 81.0}))
	_check(is_equal_approx(hit_events[0].min_hit, 40.0) and is_equal_approx(hit_events[0].max_hit, 41.0), "breach hits are measured")

	var c := Classifier.new()
	c.observe(_sample())
	var time := 10.0
	var firewall := 50.0
	for tick: int in 60:
		time -= TICK
		if tick % 20 == 0:
			firewall -= 5.0
		c.observe(_sample({"time": time, "detected": true, "firewall": firewall}))
	var events := c.on_breached(_sample({"time": time, "detected": true, "firewall": firewall - 5.0}))
	_check(events[0].volleys == 4, "volleys are counted, including the last one")


func _test_simulator() -> void:
	# Measured in the game over 430 attacks: 5 volleys 85.8%, 6 volleys 14.0%, 7 volleys 0.2%.
	var measured := Simulator.simulate(40.4, 161.6, 6.0, 1.0, 40.865)
	_check(measured.ok and absf(measured.distribution[5] - 0.8574) < 0.001, "5 volleys matches the measured share")
	_check(absf(measured.distribution[6] - 0.1414) < 0.001, "6 volleys matches the measured share")
	_check(absf(measured.distribution[7] - 0.0012) < 0.0005, "7 volleys matches the measured share")
	_check(measured.best == 5 and measured.worst == 7, "best and worst cases")
	_check(absf(measured.p_success - 0.9988) < 0.001, "a tie with the timer counts as a failure")

	var total := 0.0
	for key: int in measured.distribution:
		total += measured.distribution[key]
	_check(is_equal_approx(total, 1.0), "probabilities add up to 1")

	var level_3 := Simulator.simulate(27.0, 108.0, 5.0, 1.0, 25.8)
	_check(level_3.worst == 7 and level_3.best == 7, "level 3 at 25.8 needs 7 volleys either way")
	_check(is_zero_approx(level_3.p_success), "level 3 at 25.8 always fails, as seen in the game")
	var level_3_up := Simulator.simulate(27.0, 108.0, 5.0, 1.0, 30.959)
	_check(is_equal_approx(level_3_up.p_success, 1.0) and level_3_up.worst == 5, "level 3 at 30.96 always succeeds, as seen in the game")
	var level_4_up := Simulator.simulate(40.4, 161.6, 5.0, 1.0, 30.959)
	_check(is_zero_approx(level_4_up.p_success), "level 4 at 30.96 always fails, as seen in the game")
	var elite := Simulator.simulate(303.0, 1212.0, 10.0, 1.0, 61.917)
	_check(is_zero_approx(elite.p_success), "elite level 5 at 61.9 always fails, as seen in the game")

	var whole := Simulator.simulate(18.0, 72.0, 5.0, 1.0, 26.0)
	_check(whole.distribution.size() == 1 and whole.distribution[4] == 1.0, "a whole hit gives one outcome")
	var bonus := Simulator.simulate(0.0, 100.0, 10.0, 1.0, 20.0, 1.5)
	_check(bonus.distribution.has(4), "vulnerability multiplies the hits")
	var stealth := Simulator.simulate(1000.0, 60.0, 10.0, 1.0, 20.0, 1.0, true)
	_check(stealth.distribution.has(3), "stealth hits ignore the firewall")
	var loud := Simulator.simulate(10.0, 60.0, 10.0, 1.0, 20.0)
	_check(loud.distribution.has(4), "a firewall hit is not carried over to the breach bar")

	_check(not Simulator.simulate(10.0, 10.0, 5.0, 1.0, 0.0).ok, "no damage gives no result")
	_check(not Simulator.simulate(10.0, 10.0, 5.0, 0.0, 5.0).ok, "no interval gives no result")
	_check(Simulator.simulate(10.0, 10.0, 5.0, 1.0, 5.5).low_hit, "small hits are flagged")

	var huge := Simulator.simulate(1e9, 1e12, 10.0, 1.0, 40.5)
	_check(huge.truncated and huge.worst == -1, "an unreachable target stops at the volley limit")
	_check(is_zero_approx(huge.p_success), "the unfinished share counts as failed")
	var started := Time.get_ticks_usec()
	for i: int in 100:
		Simulator.simulate(1000.0 + i, 60000.0, 100.0, 1.0, 1000.5)
	var extreme := (Time.get_ticks_usec() - started) / 100.0
	started = Time.get_ticks_usec()
	for i: int in 100:
		Simulator.simulate(40.4 + i, 161.6, 12.0, 1.0, 40.865)
	var typical := (Time.get_ticks_usec() - started) / 100.0
	print("simulator: %.0f us at the volley limit, %.0f us for a typical attack" % [extreme, typical])
	_check(extreme < 16000.0, "the extreme case stays under one frame")
	_check(typical < 1000.0, "a typical attack costs under 1 ms")
	var beyond := Simulator.simulate(40.4, 161.6, 2.0, 1.0, 40.865)
	_check(beyond.distribution.is_empty() and is_equal_approx(beyond.beyond_limit, 1.0), "volleys past the timer are not explored")
	_check(beyond.best == 5 and beyond.worst == 7, "best and worst cases stay known past the timer")
	_check(not beyond.truncated, "running out of time is not a truncation")
	_check(Simulator.format_distribution({6: 0.25, 5: 0.75}) == "5:0.7500,6:0.2500", "distribution text is sorted")


func _test_infection_measures() -> void:
	var c := Classifier.new()
	c.observe(_sample())
	var breached := 0.0
	var time := 10.0
	var count := 20.0
	for tick: int in 40:
		time -= TICK
		breached += count * TICK
		if tick % 20 == 0:
			breached += 30.0
		c.observe(_sample({"time": time, "detected": true, "firewall": 0.0, "breached": breached, "infection_count": count, "infection_variation": 2}))
	var events := c.on_breached(_sample({"time": time, "detected": true, "firewall": 0.0, "breached": breached + 30.0 + count * TICK, "infection_count": count, "infection_variation": 2}))
	var success := events[0]
	_check(success.volleys == 3, "infection ticks are not counted as volleys, got %d" % success.volleys)
	_check(absf(success.max_hit - 30.0) < 0.01, "a hit is measured without the infection of its tick")
	_check(absf(success.infection_integral - 39.0) < 2.0, "infection over time is summed")
	_check(success.infection_variation == 2, "infection variation is recorded")
	_check(success.has("dealt_total"), "total damage is recorded for comparison")
	_check(success.trace.split(";").size() >= 7 and success.trace.split(";").size() <= 9, "infection is traced every quarter second")

	var long_trace := Classifier.new()
	long_trace.observe(_sample())
	var long_time := 100.0
	for tick: int in 1000:
		long_time -= TICK
		long_trace.observe(_sample({"time": long_time, "max_time": 100.0, "detected": true, "firewall": 0.0, "infection_count": 5.0}))
	var bounded := long_trace.on_breached(_sample({"time": long_time, "max_time": 100.0, "detected": true, "firewall": 0.0, "infection_count": 5.0}))[0]
	_check(bounded.trace.split(";").size() == Classifier.TRACE_POINTS, "the trace is bounded")

	var plain := Classifier.new()
	_attack(plain, 7.0)
	var plain_event := plain.on_breached(_sample({"time": 7.0, "detected": true}))[0]
	_check(not plain_event.has("infection_integral"), "no infection fields without infection")
	_check(not plain_event.has("breach_variation"), "no variation field without a variation")

	var flagged := Classifier.new()
	flagged.observe(_sample())
	flagged.observe(_sample({"time": 9.95, "detected": true, "firewall": 40.0, "breach_variation": 4}))
	_check(flagged.on_breached(_sample({"time": 9.9, "detected": true, "firewall": 30.0, "breach_variation": 4}))[0].breach_variation == 4, "stealth variation is recorded")


## Nothing may change the level except the actuator's single entry point, whatever else changes.
func _test_no_level_change_in_source() -> void:
	var forbidden := RegEx.create_from_string("\\bdata\\.(level|max_level) *[-+*/]?= |auto_level_breach *= |set_setting\\(")
	var native_call := RegEx.create_from_string("\\.level_(up|down)\\(|\\.call(_deferred)?\\(\"level_|\"level_(up|down)\"\\)")
	var pending: Array[String] = [MOD]
	var scanned := 0
	var actuator_source := FileAccess.get_file_as_string(MOD + "features/threat_manager/threat_actuator.gd")
	_check(native_call.search_all(actuator_source).size() == 2, "the actuator holds one call of each level method")
	var entry_start := actuator_source.find("func _call_native(")
	var entry_end := actuator_source.find("\nfunc ", entry_start + 1)
	var outside := actuator_source.substr(0, entry_start) + actuator_source.substr(entry_end)
	_check(native_call.search(outside) == null, "both calls are inside its single entry point")
	_check(outside.count("_call_native(") == 1, "which has a single caller")
	var main_source := FileAccess.get_file_as_string(MOD + "mod_main.gd")
	_check(main_source.contains("\"mode\": \"dry_run\" if settings.regulation_mode == \"dry_run\" else \"off\""), "the options cannot ask for the active mode directly")
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		for sub: String in DirAccess.get_directories_at(folder):
			pending.append(folder.path_join(sub))
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				scanned += 1
				var source := FileAccess.get_file_as_string(folder.path_join(file))
				_check(forbidden.search(source) == null, "no direct write of a level in %s" % file)
				if file != "threat_actuator.gd":
					_check(native_call.search(source) == null, "no call of a level method in %s" % file)
				_check(RegEx.create_from_string("\\bawait\\b").search(source) == null or file == "mod_main.gd", "no waiting in %s" % file)
	_check(scanned >= 7, "the source scan found the mod's scripts")


func _test_government_and_native_values() -> void:
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var corps := FakeBreach.new()
	var government := FakeBreach.new()
	government.window = "breach_government"
	var other := FakeBreach.new()
	other.window = "breach_bank"
	game.desktop.windows.add_child(corps)
	game.desktop.windows.add_child(government)
	game.desktop.windows.add_child(other)

	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, false)
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	_check(_count("bind result=ok type=breach_corps") == 1, "Corps is observed")
	_check(_count("bind result=ok type=breach_government") == 1, "Government is observed")
	_check(_count("type=breach_bank") == 0, "other Breach types stay out of scope")

	corps.breach_damage.production = 30.0
	game.Signals.tick.emit()
	for step: Array in [[9.95, 20.0, 0.0], [8.95, 0.0, 0.0], [7.95, 0.0, 30.0]]:
		corps.detected = true
		corps.time = step[0]
		corps.firewall = step[1]
		corps.breached = step[2]
		game.Signals.tick.emit()
	corps.time = 6.95
	corps.breached = 60.0
	game.Signals.breached.emit(corps)
	_check(_count("event=success type=breach_corps") == 1, "a Corps success is reported under its own type")
	_check(_count("next_source=native") == 1, "the next level comes from the game's getters")
	_check(_count("native_matches=true") == 1, "the getters match the current level")
	_check(_count("sim_next_p=") == 1, "the simulation of the next level is logged")
	_check(_count("event=success type=breach_government") == 0, "Government is not credited with it")
	_check(corps.forbidden_calls == 0 and government.forbidden_calls == 0, "level_up and level_down are never called")
	_check(corps.data.level == 3.0 and government.data.level == 3.0, "no level changed")

	corps.detected = false
	corps.time = 10.0
	corps.firewall = 50.0
	corps.breached = 0.0
	game.Signals.tick.emit()
	for step: Array in [[9.95, 30.0], [0.10, 20.0], [0.05, 20.0]]:
		corps.detected = true
		corps.time = step[0]
		corps.firewall = step[1]
		game.Signals.tick.emit()
	corps.detected = false
	corps.time = 10.0
	corps.firewall = 50.0
	game.Signals.tick.emit()
	_check(_count("event=failure_power type=breach_corps") == 1, "a failure is reported under its own type")
	_check(_count("native_matches=true") == 2, "failures are compared with the game's getters too")
	_check(_count("tick_speed from=") == 1, "the tick speed is logged once while it does not change")
	_attributes_of(game).tick_speed = 0.25
	game.Signals.tick.emit()
	_check(_count("tick_speed from=0.05 to=0.25") == 1, "a change of tick speed is logged")
	_attributes_of(game).tick_speed = TICK
	game.Signals.tick.emit()

	observer.stop()
	_check(_count("reliability_check type=breach_corps") == 1, "reliability is summarized at stop")
	_check(_count("distribution_check type=breach_corps") == 1, "the distribution is compared at stop")

	var bare := FakeGetterless.new()
	game.desktop.windows.add_child(bare)
	ModLoaderLog.messages.clear()
	observer.start()
	_check(_count("absent=get_max_firewall") == 1, "a window without getters binds and reports them missing")
	bare.breach_damage.production = 30.0
	game.Signals.tick.emit()
	bare.detected = true
	bare.time = 9.95
	game.Signals.tick.emit()
	bare.firewall = 20.0
	bare.time = 8.95
	game.Signals.tick.emit()
	bare.firewall = 0.0
	bare.time = 7.95
	game.Signals.tick.emit()
	bare.time = 6.95
	bare.breached = 30.0
	game.Signals.tick.emit()
	ModLoaderLog.messages.clear()
	bare.time = 5.95
	bare.breached = 60.0
	game.Signals.breached.emit(bare)
	_check(_count("event=success type=breach_government") == 1, "observation works without getters")
	_check(_count("next_source=formula") == 1, "the next level falls back on the formula, labeled as such")
	_check(_count("next_source=native") == 0, "no native value is claimed without getters")

	observer.stop()
	observer.queue_free()
	await _remove_fake_game(game)


func _test_guard() -> void:
	var empty := Node.new()
	root.add_child(empty)
	_check(ApiGuard.missing_autoload_api(empty).size() == 4, "every missing autoload is reported")
	empty.free()
	var window := Node.new()
	_check(ApiGuard.missing_breach_api(window).has("time"), "missing window property is reported")
	window.free()
	var breach := FakeBreach.new()
	_check(ApiGuard.missing_breach_api(breach).is_empty(), "complete window passes")
	breach.free()


func _install_fake_game() -> Dictionary:
	var game := {}
	for entry: Array in [["Signals", FakeSignals.new()], ["Globals", FakeGlobals.new()], ["Attributes", FakeAttributes.new()], ["Data", FakeData.new()]]:
		entry[1].name = entry[0]
		root.add_child(entry[1])
		game[entry[0]] = entry[1]
	var desktop := FakeDesktop.new()
	desktop.windows = Node.new()
	desktop.add_child(desktop.windows)
	root.add_child(desktop)
	game.desktop = desktop
	return game


func _attributes_of(game: Dictionary) -> FakeAttributes:
	return game.Attributes


func _remove_fake_game(game: Dictionary) -> void:
	for node: Node in game.values():
		node.queue_free()
	await process_frame


func _test_observer() -> void:
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var breach := FakeBreach.new()
	game.desktop.windows.add_child(breach)
	var other := Node.new()
	game.desktop.windows.add_child(other)

	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, true)
	root.add_child(observer)

	ModLoaderLog.messages.clear()
	observer.start()
	_check(_count("bind result=ok") == 1, "an existing desktop is bound at once")
	_check(_count("api_dump") == 3, "api dump logs properties, signals and methods")
	_check(_count("native_methods type=breach_corps") == 1, "native methods are reported")

	observer.start()
	game.Signals.desktop_ready.emit()
	game.Signals.window_initialized.emit(breach)
	_check(_count("bind result=ok") == 1, "no double binding")

	breach.detected = true
	breach.time = 7.0
	game.Signals.tick.emit()
	game.Signals.breached.emit(breach)
	_check(_count("event=success") == 1, "one success per signal after a repeated start")
	_check(_count("next_ratio=") == 1, "the prediction is logged")
	_check(_count(" level=3 ") >= 1, "the game's float levels are logged as integers")
	_check(breach.data.level == 3 and breach.data.max_level == 5, "the observer changes nothing")
	_check(breach.forbidden_calls == 0, "the observer never calls level_up or level_down")

	observer.stop()
	observer.stop()
	game.Signals.breached.emit(breach)
	_check(_count("event=success") == 1, "nothing is observed once stopped")
	_check(game.Signals.tick.get_connections().is_empty(), "stop disconnects everything")

	observer.start()
	_check(game.Signals.tick.get_connections().size() == 1, "restart connects once")
	game.Signals.breached.emit(breach)
	_check(_count("event=success") == 2, "observed again after a restart, once")

	game.Signals.setting_set.emit("auto_level_breach")
	_check(_count("setting native_auto_level") == 1, "the native option is logged")

	breach.detected = true
	game.Signals.tick.emit()
	game.Signals.window_deleted.emit(breach)
	_check(_count("event=invalidated type=breach_corps") == 1, "deleting the window invalidates its cycle")
	game.Signals.tick.emit()

	var fresh := FakeBreach.new()
	game.desktop.windows.add_child(fresh)
	game.Signals.window_initialized.emit(fresh)
	_check(_count("bind result=ok") == 3, "a new window is bound")
	fresh.free()
	game.Signals.tick.emit()
	_check(_count("event=") >= 3, "a freed window does not crash the tick")

	observer.stop()
	observer.queue_free()
	await _remove_fake_game(game)


func _count(text: String) -> int:
	var total := 0
	for message: String in ModLoaderLog.messages:
		if message.contains(text):
			total += 1
	return total


func _test_dry_run_in_observer() -> void:
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var corps := FakeBreach.new()
	game.desktop.windows.add_child(corps)
	corps.breach_damage.production = 30.0
	corps.infection_damage.production = 0.0

	var refused := Observer.new()
	refused.configure(SaLog.new("info"), 0.25, false, {"mode": "active"})
	_check(refused.regulation_mode() == "off", "any mode other than dry_run falls back to off")
	refused.free()

	var off := Observer.new()
	off.configure(SaLog.new("info"), 0.25, false)
	_check(off.regulation_mode() == "off", "regulation is off by default")
	off.free()

	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, false, {"mode": "dry_run", "profile": "aggressive"})
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	game.Signals.tick.emit()
	for attack: int in 8:
		for step: Array in [[9.95, 20.0, 0.0], [8.95, 0.0, 0.0], [7.95, 0.0, 30.0]]:
			corps.detected = true
			corps.time = step[0]
			corps.firewall = step[1]
			corps.breached = step[2]
			game.Signals.tick.emit()
		corps.time = 6.95
		corps.breached = 60.0
		game.Signals.breached.emit(corps)
		corps.detected = false
		corps.time = 10.0
		corps.firewall = 50.0
		corps.breached = 0.0
		game.Signals.tick.emit()
	_check(_count("dry_run type=") >= 1, "decisions are logged")
	_check(_count("hypothetical=true") == _count("dry_run type="), "every decision is marked hypothetical")
	_check(_count("decision=raise") == 1, "a raise is proposed once, not at every attack")
	_check(_count("real_level=3") >= 1 and _count("assumed_level=4") == 1, "the real level and the assumed level are told apart")
	_check(corps.data.level == 3.0 and corps.forbidden_calls == 0, "the dry run changes nothing")
	_check(_count("inventory save_candidates") == 2, "save identifier candidates are reported")

	corps.data.level = 2.0
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=2 origin=player") == 1 and _count("automation_pause type=breach_corps reason=player_level_change level=2") == 1, "a manual change pauses the type")
	game.Signals.desktop_ready.emit()
	corps.data.level = 3.0
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=3 origin=player") == 1 and _count("automation_pause") == 1, "a manual raise is noted, and the pause goes on")

	game.Data.auto_level_breach = true
	corps.data.level = 4.0
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=4 origin=native") == 1, "a level change made by the native option is not manual")
	game.Data.auto_level_breach = false

	observer.stop()
	_check(_count("regulator_summary type=breach_corps") == 1, "the regulator is summarized at stop")
	observer.queue_free()
	await _remove_fake_game(game)


## One attack on the fake window: a success, or a failure when the timer runs out.
func _play_attack(game: Dictionary, breach: FakeBreach, success: bool) -> void:
	var start: float = breach.max_time
	if not success:
		var hit: float = breach.breach_damage.production
		for volley: int in int(start):
			breach.detected = true
			breach.time = start - 0.05 - volley
			breach.firewall = maxf(breach.max_firewall - hit * (volley + 1), 0.0)
			breach.breached = maxf(hit * (volley + 1) - breach.max_firewall, 0.0)
			game.Signals.tick.emit()
		breach.time = 0.05
		game.Signals.tick.emit()
		breach.detected = false
		breach.time = breach.max_time
		breach.firewall = breach.max_firewall
		breach.breached = 0.0
		game.Signals.tick.emit()
		await process_frame
		return
	for step: Array in [[start - 0.05, 0.6, 0.0], [start - 1.05, 0.0, 0.0], [start - 2.05, 0.0, 0.5]]:
		breach.detected = true
		breach.time = step[0]
		breach.firewall = breach.max_firewall * step[1]
		breach.breached = breach.max_breach * step[2]
		game.Signals.tick.emit()
	breach.time = start - 3.05
	breach.breached = breach.max_breach
	game.Signals.breached.emit(breach)
	breach.detected = false
	breach.time = breach.max_time
	breach.firewall = breach.max_firewall
	breach.breached = 0.0
	await process_frame
	game.Signals.tick.emit()


func _armed_setup(game: Dictionary, options: Dictionary) -> ArmedObserver:
	var regulation := {"mode": "active", "profile": "aggressive", "action_type": "breach_corps", "action_limit": 5}
	regulation.merge(options, true)
	var observer := ArmedObserver.new()
	observer.configure(SaLog.new("info"), 0.25, false, regulation)
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	game.Signals.tick.emit()
	return observer


func _test_actions_in_observer() -> void:
	# The real observer never opens: whatever the configuration asks.
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var corps := ActingBreach.new()
	game.desktop.windows.add_child(corps)
	corps.breach_damage.production = 60.0
	corps.infection_damage.production = 0.0
	var shipped := Observer.new()
	shipped.configure(SaLog.new("info"), 0.25, false, {"mode": "active", "profile": "aggressive", "action_type": "breach_corps"})
	_check(shipped.regulation_mode() == "off", "asking for active in this build gives off")
	shipped.free()

	var shadow := Observer.new()
	shadow.configure(SaLog.new("info"), 0.25, false, {"mode": "dry_run", "profile": "aggressive"})
	root.add_child(shadow)
	ModLoaderLog.messages.clear()
	shadow.start()
	game.Signals.tick.emit()
	for attack: int in 8:
		await _play_attack(game, corps, true)
	_check(_count("action_would_apply type=breach_corps") == 1, "the dry run shows what the actuator would have done")
	_check(corps.calls.is_empty() and corps.data.level == 3.0, "and it does nothing")
	shadow.stop()
	_check(_count("actuator_summary armed=false actions=0") == 1, "the summary says it was not armed")
	shadow.queue_free()
	await process_frame

	# Everything below uses the fake game with both locks opened by the tests.
	var observer := _armed_setup(game, {})
	for attack: int in 8:
		await _play_attack(game, corps, true)
		if not corps.calls.is_empty():
			break
	_check(corps.calls == ["up:1"], "a raise calls the game once, after the reset: %s" % str(corps.calls))
	_check(_count("action_applied type=breach_corps direction=raise level=3 target=4") == 1, "the action is traced")
	_check(_count("forecast_status=") == 1 and _count("margin=") >= 1 and _count("successes_in_row=") >= 1, "with its evidence")
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=4 origin=mod") == 1, "the mod's change is told apart")
	_check(_count("automation_pause") == 0, "and it does not pause")
	await _play_attack(game, corps, true)
	_check(_count("action_verification type=breach_corps from=3 to=4 outcome=verified") == 1, "the next attack verifies it: %s" % _last("action_verification"))

	# The player comes first: the change pauses the type.
	corps.detected = true
	corps.time = corps.max_time - 0.05
	corps.firewall = corps.max_firewall * 0.5
	game.Signals.tick.emit()
	corps.data.level = 2.0
	corps._rearm()
	corps.detected = false
	game.Signals.tick.emit()
	_check(_count("automation_pause type=breach_corps reason=player_level_change level=2") == 1, "the player's change pauses the type")
	observer.stop()
	observer.queue_free()
	await process_frame

	# Lowering: known at a tick, done in the same call, and only if the window is free.
	corps.calls.clear()
	corps.data.level = 4.0
	corps._rearm()
	corps.breach_damage.production = 12.0
	var lowering := _armed_setup(game, {})
	for attack: int in 20:
		await _play_volleys(game, corps)
		if not corps.calls.is_empty():
			break
	_check(corps.calls == ["down:1"], "a lower calls the game once: %s, %s" % [str(corps.calls), _last("active type=")])
	_check(_count("action_applied type=breach_corps direction=lower level=4 target=3") == 1, "the lower is traced: %s" % _last("action_"))
	_check(_count("window_failures=") >= 1, "with the failures that motivated it")
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=3 origin=mod") == 1, "the lower is told apart from a player's change")
	game.Signals.desktop_ready.emit()
	_check(_count("action_verification type=breach_corps from=4 to=3 outcome=interrupted reason=reload_during_verification") == 1, "a load during the verification is reported")
	_check(_count("regulation_stopped") == 0, "and it is not an anomaly")
	corps.data.level = 4.0
	corps._rearm()

	# The emergency stop survives a restart of the observer.
	lowering.emergency_stop()
	_check(_count("emergency_stop actuator=stopped") == 1, "the emergency stop is logged")
	lowering.stop()
	lowering.start()
	var before := corps.calls.size()
	game.Signals.tick.emit()
	for attack: int in 12:
		await _play_attack(game, corps, true)
	_check(corps.calls.size() == before, "nothing acts after the emergency stop, even restarted")
	_check(_count("regulation_stopped reason=emergency_stop") >= 1, "the new actuator says why it is stopped")
	lowering.stop()
	lowering.queue_free()
	await process_frame

	# A single action, as in the first real test.
	corps.calls.clear()
	corps.data.level = 3.0
	corps._rearm()
	corps.breach_damage.production = 60.0
	var single := _armed_setup(game, {"action_limit": 1})
	for attack: int in 30:
		await _play_attack(game, corps, true)
	_check(corps.calls.size() == 1, "one action allowed, one action made: %s" % str(corps.calls))
	_check(_count("regulation_stopped reason=action_limit_reached actions=1") == 1, "the regulation stops right after it")
	single.stop()
	_check(_count("actions=1 deferred_no_safe_window=0") == 1, "the summary counts it")
	single.queue_free()
	await process_frame

	# No safe window: the action waits, and is never forced.
	corps.calls.clear()
	corps.data.level = 3.0
	corps._rearm()
	var busy := _armed_setup(game, {})
	for attack: int in 12:
		if _count("action_deferred_no_safe_window") > 0:
			break
		corps.detected = true
		corps.time = corps.max_time - 0.05
		corps.firewall = corps.max_firewall * 0.6
		game.Signals.tick.emit()
		corps.time = corps.max_time - 3.05
		corps.firewall = 0.0
		corps.breached = corps.max_breach
		game.Signals.breached.emit(corps)
		# The next attack is already there when the deferred check runs.
		corps.time = corps.max_time - 0.05
		corps.firewall = corps.max_firewall * 0.9
		corps.breached = 0.0
		await process_frame
	_check(_count("action_deferred_no_safe_window type=breach_corps direction=raise") == 1, "an attack in progress defers the action")
	_check(_count("state=attack_in_progress total=1") == 1, "the report counts it: %s" % _last("action_"))
	_check(corps.calls.is_empty(), "and nothing is called")
	corps.detected = false
	corps.time = corps.max_time
	corps.firewall = corps.max_firewall
	game.Signals.tick.emit()
	await _play_attack(game, corps, false)
	_check(_count("action_cancelled type=breach_corps direction=raise reason=contradicted_by_attack") == 1, "a failure drops a waiting raise: %s" % _last("action_"))
	_check(corps.calls.is_empty(), "so it never happens")
	busy.stop()
	busy.queue_free()
	await process_frame

	# No action at speed x5, and attacks seen there are forgotten.
	corps.calls.clear()
	corps.data.level = 3.0
	corps._rearm()
	var fast := _armed_setup(game, {})
	game.Attributes.tick_speed = 0.25
	game.Signals.tick.emit()
	for attack: int in 12:
		await _play_attack(game, corps, true)
	_check(corps.calls.is_empty(), "no action at speed x5")
	_check(_count("action_refused type=breach_corps direction=raise reason=speed_not_normal") == 1, "the reason is logged once: %s" % _last("action_"))
	game.Attributes.tick_speed = TICK
	fast.stop()
	fast.queue_free()
	await process_frame

	# The native option blocks everything.
	game.Data.auto_level_breach = true
	var native := _armed_setup(game, {})
	for attack: int in 12:
		await _play_attack(game, corps, true)
	_check(corps.calls.is_empty(), "no action while the native option is active")
	game.Data.auto_level_breach = false
	native.stop()
	native.queue_free()
	await process_frame
	await _remove_fake_game(game)


## Volleys one second apart, as measured in the game: the attack ends when the bars are empty or the
## timer runs out. restart: the next attack begins on the very tick of the reset, with no free state.
func _play_volleys(game: Dictionary, breach: FakeBreach, restart: bool = false) -> void:
	var start: float = breach.max_time
	var hit: float = breach.breach_damage.production
	if breach is ActingBreach and breach.true_hit > 0.0:
		hit = breach.true_hit
	var firewall: float = breach.max_firewall
	var breached := 0.0
	for volley: int in int(start):
		if firewall > 0.0:
			firewall = maxf(firewall - hit, 0.0)
		else:
			breached += hit
		breach.detected = true
		breach.time = start - 0.05 - volley
		breach.firewall = firewall
		# As measured: the last hit shows in full, it is not cut to what the bar had left.
		breach.breached = breached
		game.Signals.tick.emit()
		if breached >= breach.max_breach:
			breach.time -= 0.05
			game.Signals.breached.emit(breach)
			breach.detected = false
			breach.time = breach.max_time
			breach.firewall = breach.max_firewall
			breach.breached = 0.0
			await process_frame
			game.Signals.tick.emit()
			return
	breach.time = 0.05
	game.Signals.tick.emit()
	breach.detected = restart
	breach.time = breach.max_time - (0.05 if restart else 0.0)
	breach.firewall = breach.max_firewall - (hit if restart else 0.0)
	breach.breached = 0.0
	game.Signals.tick.emit()
	await process_frame


func _control_of(window: Node) -> Node:
	return window.find_child("SmartAutomationControl", true, false)


## Plays attacks and lets the game's timer pass, until a condition holds or the attempts run out.
func _play_until(game: Dictionary, observer: Observer, window: FakeBreach, done: Callable, attempts: int = 40) -> void:
	for attack: int in attempts:
		await _play_volleys(game, window)
		if done.call():
			return
		if not observer._actuator.is_verifying():
			observer._regulator_for(window.window).advance(61.0)
			observer._actuator.advance(61.0)


## The authorized trial from start to finish, on the fake game: only the build's lock is opened.
func _test_trial_in_observer() -> void:
	const MARKER_PATH := "user://smart_automation_test/observer_trial_used.json"
	DirAccess.remove_absolute(MARKER_PATH)
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var government := ActingBreach.new()
	government.window = "breach_government"
	government.fixed_time = 6.0
	var corps := ActingBreach.new()
	game.desktop.windows.add_child(government)
	game.desktop.windows.add_child(corps)
	for window: ActingBreach in [government, corps]:
		window.breach_damage.production = 30.0
		window.infection_damage.production = 0.0
	government.data.level = 0.0
	government._rearm()

	for old: Dictionary in [{"mode": "active"}, {"mode": "dry_run", "action_type": "breach_government"}, {"active_trial": "true"}, {"active_trial": 1}, {"active_trial": false}]:
		var forgotten := TrialObserver.new()
		forgotten.configure(SaLog.new("info"), 0.25, false, old)
		_check(forgotten.regulation_mode() != "active", "no active mode from an old or odd configuration: %s" % str(old))
		forgotten.free()

	var observer := TrialObserver.new()
	observer.configure(SaLog.new("info"), 0.25, false, {"active_trial": true, "profile": "aggressive", "action_limit": 99, "action_type": "breach_corps", "max_allowed_level": 40, "min_level": 3})
	_check(observer.regulation_mode() == "active", "the trial needs its own option")
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	_check(_count("regulation_mode=active profile=balanced") == 1, "the trial sets its own profile, whatever the options say")
	game.Signals.tick.emit()
	_check(_control_of(government).shown().text == "Auto : actif", "the trial's node says it is active: %s" % str(_control_of(government).shown()))
	_check(_control_of(corps).shown().text == "Auto : actif", "and so does the other one")

	# Up from 0 to 4, one verified step at a time, then a deliberate hold.
	var attacks_before := _count("event=success type=breach_government")
	await _play_until(game, observer, government, func() -> bool: return government.calls.size() >= 4)
	var climb_attacks := _count("event=success type=breach_government") - attacks_before
	_check(climb_attacks <= 6, "a certain climb takes one attack per level, after stabilizing: %d" % climb_attacks)
	_check(government.calls == ["up:1", "up:1", "up:1", "up:1"] and government.data.level == 4.0, "four raises to level 4: %s, %s" % [str(government.calls), _last("active type=breach_government")])
	await _play_until(game, observer, government, func() -> bool: return _count("from=3 to=4 outcome=verified") == 1, 8)
	_check(_count("outcome=verified") == 4, "each one is verified: %s" % _last("action_verification"))
	_check(_count("level_origin type=breach_government level=4 origin=mod") == 1 and _count("origin=player") == 0, "they are the mod's")
	_check(corps.data.level == 3.0 and corps.calls.is_empty(), "the other type is not touched")
	for attack: int in 8:
		await _play_volleys(game, government)
		observer._regulator_for("breach_government").advance(61.0)
		observer._actuator.advance(61.0)
	_check(government.calls.size() == 4 and government.data.level == 4.0, "level 5 fails, so it holds at 4")
	_check(_last("active type=breach_government").contains("forecast_too_risky"), "and says why: %s" % _last("active type=breach_government"))
	_check(observer._actuator.halt_reason.is_empty() and _control_of(government).shown().text == "Auto : actif", "holding is not stopping")

	# The player lowers by hand: pause, and no way back up.
	government.data.level = 3.0
	government._rearm()
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_government level=3 origin=player") == 1, "the player's change is told apart")
	_check(_count("automation_pause type=breach_government reason=player_level_change level=3") == 1, "and pauses the type")
	_check(_control_of(corps).shown().text == "Auto : actif", "the other type goes on")
	_check(_control_of(government).shown().text == "Pause manuelle" and _control_of(government).shown().button == "Reprendre l'automatisation", "the node shows it: %s" % str(_control_of(government).shown()))
	await _play_until(game, observer, government, func() -> bool: return false, 12)
	_check(government.calls.size() == 4 and government.data.level == 3.0, "nothing moves during a pause")
	_check(_last("active type=breach_government").contains("manual_pause"), "the log says why")

	# Ctrl+Z: a real change is the player's, and a second pause is not created.
	government.data.level = 4.0
	government._rearm()
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_government level=4 origin=player") == 1, "an undo that changes the level is the player's")
	_check(_count("automation_pause type=breach_government") == 1 and _control_of(government).shown().kind == "pause", "the pause simply goes on")
	game.Signals.tick.emit()
	_check(_count("origin=player") == 2, "no change, no event")
	government.data.level = 3.0
	government._rearm()
	game.Signals.tick.emit()

	# Pauses survive a load, and the node's interface is rebuilt.
	game.Signals.desktop_ready.emit()
	_check(_control_of(government).shown().kind == "pause", "a load does not lift the pause")

	# The resume button: nothing happens at once, the old limits stay, the last action comes later.
	var calls_before := government.calls.size()
	# The budget goes through pauses and resumes: one action is left.
	observer._actuator.actions_done = Observer.Policy.TRIAL_MAX_ACTIONS - 1
	_control_of(government).button().pressed.emit()
	_check(_count("automation_resume type=breach_government level=3") == 1, "the resume is logged")
	_check(government.calls.size() == calls_before and government.data.level == 3.0, "the resume changes nothing by itself")
	_check(observer._actuator.actions_done == Observer.Policy.TRIAL_MAX_ACTIONS - 1, "and gives no budget back")
	_check(_control_of(government).shown().text == "Auto : actif", "the node shows it")
	await _play_volleys(game, government)
	await _play_volleys(game, government)
	_check(government.calls.size() == calls_before, "nothing while it stabilizes")
	_check(_last("active type=breach_government").contains("stabilizing"), "it says so: %s" % _last("active type=breach_government"))
	await _play_until(game, observer, government, func() -> bool: return government.calls.size() >= calls_before + 1)
	_check(government.calls.size() == calls_before + 1 and government.data.level == 4.0, "the player gave control back, so it may go above the chosen level: %s" % str(government.calls))
	_check(_count("regulation_stopped reason=action_limit_reached actions=%d" % Observer.Policy.TRIAL_MAX_ACTIONS) == 1, "the budget is spent: %s" % _last("regulation_stopped"))
	_check(_control_of(government).shown().text == "Auto : bloqué" and _control_of(government).shown().button.is_empty(), "the node shows a block with no button")
	await _play_until(game, observer, government, func() -> bool: return false, 8)
	_check(government.calls.size() == calls_before + 1, "there is no action past the budget")
	_check(_count("from=3 to=4 outcome=verified") == 2, "the last one is verified too: %s" % _last("action_verification"))
	await _play_attack(game, corps, true)
	_check(_control_of(corps).shown().text == "Auto : bloqué" and corps.calls.is_empty(), "the budget is global: the other type stops too")
	_check(corps.calls.is_empty() and corps.data.level == 3.0, "the other node is untouched")
	_check(_count("event=level_changed_reset") == 0, "no attack is reset")
	var applied := _last("action_applied")
	_check(applied.contains("direction=raise level=3 target=4") and applied.contains("window_failures=0") and applied.contains("certain=true verify_attacks=1"), "the last action is traced: %s" % applied)
	observer.stop()
	_check(_control_of(government) == null and _control_of(corps) == null, "stopping removes the controls")
	observer.queue_free()
	await process_frame

	# The game restarts: the marker says no, even with the budget of a new session.
	government.calls.clear()
	government.data.level = 2.0
	government._rearm()
	var again := TrialObserver.new()
	again.configure(SaLog.new("info"), 0.25, false, {"active_trial": true})
	root.add_child(again)
	ModLoaderLog.messages.clear()
	again.start()
	game.Signals.tick.emit()
	await _play_until(game, again, government, func() -> bool: return false, 12)
	_check(government.calls.is_empty(), "a new session never acts")
	_check(_count("action_refused type=breach_government direction=raise reason=trial_already_used") == 1, "and says why: %s" % _last("action_"))
	again.stop()
	again.queue_free()
	await process_frame
	DirAccess.remove_absolute(MARKER_PATH)

	# The next attack starts on the tick of the reset: no free state, so the action waits.
	government.calls.clear()
	government.data.level = 4.0
	government._rearm()
	government.breach_damage.production = 20.0
	var tight := TrialObserver.new()
	tight.configure(SaLog.new("info"), 0.25, false, {"active_trial": true})
	root.add_child(tight)
	ModLoaderLog.messages.clear()
	tight.start()
	game.Signals.tick.emit()
	for attack: int in 8:
		await _play_volleys(game, government, true)
	_check(government.calls.is_empty(), "without a safe window nothing is forced: %s" % _last("active type=breach_government"))
	_check(_count("action_deferred_no_safe_window type=breach_government direction=lower") >= 1, "the missed windows are reported: %s" % _last("action_"))
	_check(_count("state=attack_in_progress") >= 1 and _count("moment=tick") >= 1, "with the state and the moment")
	_check(not FileAccess.file_exists(MARKER_PATH), "they do not use up the trial")
	# A click on the voluntary pause drops the waiting action.
	_control_of(government).button().pressed.emit()
	_check(_count("automation_pause type=breach_government reason=player_button") == 1, "the pause button works")
	_check(_count("action_cancelled type=breach_government direction=lower reason=player_button") == 1, "and it cancels the waiting action: %s" % _last("action_"))
	government.detected = false
	government.time = government.max_time
	government.firewall = government.max_firewall
	game.Signals.tick.emit()
	await _play_volleys(game, government)
	_check(government.calls.is_empty(), "nothing happens during the pause")
	_control_of(government).button().pressed.emit()
	_check(government.calls.is_empty(), "nor at the resume")
	tight.stop()
	tight.queue_free()
	await process_frame
	DirAccess.remove_absolute(MARKER_PATH)
	await _remove_fake_game(game)


## A critical node announces more damage than most hits deal: the level must be judged on the real hits.
func _test_announced_damage_in_observer() -> void:
	const MARKER_PATH := "user://smart_automation_test/observer_trial_used.json"
	DirAccess.remove_absolute(MARKER_PATH)
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var government := ActingBreach.new()
	government.window = "breach_government"
	government.fixed_time = 6.0
	game.desktop.windows.add_child(government)
	government.breach_damage.production = 87.0
	government.true_hit = 53.0
	government.infection_damage.production = 0.0
	government.data.level = 4.0
	government._rearm()
	var observer := TrialObserver.new()
	observer.configure(SaLog.new("info"), 0.25, false, {"active_trial": true})
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	game.Signals.tick.emit()
	await _play_until(game, observer, government, func() -> bool: return _count("action_verification") >= 1, 12)
	_check(_count("hit_spread type=breach_government announced=87.0 lowest=53.0 highest=53.0") == 1, "the gap is noticed: %s" % _last("hit_spread"))
	_check(government.data.level == 5.0, "a level that passes with the real hits goes up: %s" % _last("active type="))
	_check(_count("outcome=verified") == 1 and _count("regulation_stopped") == 0, "and it is verified against the real hits: %s" % _last("action_verification"))
	observer.stop()
	observer.queue_free()
	await process_frame
	DirAccess.remove_absolute(MARKER_PATH)
	await _remove_fake_game(game)


## Weak hits on a high level: every level near it fails too, so the mod must walk down until one works.
func _test_descent_in_observer() -> void:
	const MARKER_PATH := "user://smart_automation_test/observer_trial_used.json"
	DirAccess.remove_absolute(MARKER_PATH)
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var government := ActingBreach.new()
	government.window = "breach_government"
	government.fixed_time = 6.0
	game.desktop.windows.add_child(government)
	government.breach_damage.production = 12.0
	government.infection_damage.production = 0.0
	government.data.level = 4.0
	government._rearm()
	var observer := TrialObserver.new()
	observer.configure(SaLog.new("info"), 0.25, false, {"active_trial": true})
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	game.Signals.tick.emit()
	for attack: int in 16:
		await _play_volleys(game, government)
		observer._regulator_for("breach_government").advance(11.0)
	_check(government.calls == ["down:1", "down:1"] and government.data.level == 2.0, "it walks down until a level works: %s, %s" % [str(government.calls), _last("active type=breach_government")])
	_check(_count("action_refused") == 0, "without any refusal: %s" % _last("action_refused"))
	_check(_count("regulation_stopped") == 0, "a failing level is not an anomaly")
	_check(_count("outcome=verified") == 2, "each step is verified: %s" % _last("action_verification"))
	observer.stop()
	observer.queue_free()
	await process_frame
	DirAccess.remove_absolute(MARKER_PATH)
	await _remove_fake_game(game)


## The control itself, with the locks closed: it behaves the same in the dry run.
func _test_automation_control() -> void:
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var corps := ActingBreach.new()
	game.desktop.windows.add_child(corps)
	corps.breach_damage.production = 60.0
	corps.infection_damage.production = 0.0

	var off := Observer.new()
	off.configure(SaLog.new("info"), 0.25, false)
	root.add_child(off)
	off.start()
	_check(_control_of(corps).shown().text == "Auto : désactivé" and _control_of(corps).shown().button.is_empty(), "regulation off: the node says so, with no button")
	_control_of(corps).button().pressed.emit()
	off.stop()
	_check(_control_of(corps) == null, "stopping removes the control at once")
	off.free()

	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, false, {"mode": "dry_run", "profile": "aggressive"})
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	game.Signals.tick.emit()
	var control := _control_of(corps)
	_check(control.get_index() == control.get_parent().get_child_count() - 1 and control.get_parent().name == "MainContainer", "the row goes under the level buttons")
	_check(control.shown().text == "Auto : simulation" and control.shown().button == "Pause", "without the right to act, it does not claim to be active: %s" % str(control.shown()))
	_check(control.button().focus_mode == Control.FOCUS_NONE, "the button never takes the keyboard")
	_check(control.button().theme_type_variation == &"ButtonActionBlue", "it looks like the game's buttons")
	_check(control.button().pressed.get_connections().size() == 1, "one click, one call")

	# A second start or a load does not add anything.
	observer.start()
	game.Signals.desktop_ready.emit()
	game.Signals.window_initialized.emit(corps)
	_check(corps.find_children("SmartAutomationControl", "", true, false).size() == 1, "no duplicate")
	_check(_control_of(corps).button().pressed.get_connections().size() == 1, "no duplicate connection")

	# Restarting the observer twice leaves a single control, with a single connection.
	for round_index: int in 2:
		observer.stop()
		observer.start()
	_check(corps.find_children("SmartAutomationControl", "", true, false).size() == 1 and _control_of(corps).button().pressed.get_connections().size() == 1, "restarts leave one control")

	# The pause belongs to the type: it survives the node, and the observer.
	_control_of(corps).button().pressed.emit()
	_check(_control_of(corps).shown().kind == "pause", "the voluntary pause shows")
	observer.stop()
	observer.start()
	_check(_control_of(corps).shown().kind == "pause", "it survives a restart of the observer")
	game.Signals.window_deleted.emit(corps)
	corps.free()
	game.Signals.tick.emit()
	corps = ActingBreach.new()
	corps.breach_damage.production = 60.0
	corps.infection_damage.production = 0.0
	game.desktop.windows.add_child(corps)
	game.Signals.window_created.emit(corps)
	_check(_control_of(corps).shown().kind == "pause", "and the node being deleted and made again")
	_check(corps.find_children("SmartAutomationControl", "", true, false).size() == 1, "with one control")

	# A block is not a pause, and the resume button does not lift it.
	_control_of(corps).button().pressed.emit()
	_check(_control_of(corps).shown().kind == "active", "resume works")
	game.Attributes.tick_speed = 0.25
	game.Signals.tick.emit()
	_check(_control_of(corps).shown().text == "Auto : bloqué" and _control_of(corps).shown().tooltip.contains("vitesse"), "speed x5 blocks: %s" % str(_control_of(corps).shown()))
	_control_of(corps).button().pressed.emit()
	_check(_control_of(corps).shown().kind == "blocked", "a click does nothing to a block")
	game.Attributes.tick_speed = TICK
	game.Signals.tick.emit()
	_check(_control_of(corps).shown().kind == "active", "it ends with its cause")

	game.Data.auto_level_breach = true
	game.Signals.setting_set.emit("auto_level_breach")
	_check(_control_of(corps).shown().kind == "blocked" and _control_of(corps).shown().tooltip.contains("native"), "the native option blocks")
	corps.data.level = 4.0
	corps._rearm()
	game.Signals.tick.emit()
	_check(_count("level_origin type=breach_corps level=4 origin=native") == 1 and _control_of(corps).shown().kind == "blocked", "its changes are not the player's")
	game.Data.auto_level_breach = false
	game.Signals.setting_set.emit("auto_level_breach")

	# Paused and stopped together: the resume lifts the pause, not the stop.
	_control_of(corps).button().pressed.emit()
	observer.emergency_stop()
	_check(_control_of(corps).shown().kind == "pause" and _control_of(corps).shown().tooltip.contains("urgence"), "a pause can hide a block, the tooltip tells: %s" % str(_control_of(corps).shown()))
	_control_of(corps).button().pressed.emit()
	_check(_control_of(corps).shown().text == "Auto : bloqué", "after the resume the block shows")
	_check(corps.data.level == 4.0 and corps.calls.is_empty(), "the control never called the game")
	observer.stop()
	observer.queue_free()
	await process_frame
	await _remove_fake_game(game)


func _last(text: String) -> String:
	for index: int in range(ModLoaderLog.messages.size() - 1, -1, -1):
		if ModLoaderLog.messages[index].contains(text):
			return ModLoaderLog.messages[index]
	return "none"


func _test_gap_probe_in_observer() -> void:
	var game := _install_fake_game()
	game.Globals.desktop = game.desktop
	var corps := FakeBreach.new()
	var twin := FakeBreach.new()
	game.desktop.windows.add_child(corps)
	game.desktop.windows.add_child(twin)
	var off := Observer.new()
	off.configure(SaLog.new("info"), 0.25, false)
	root.add_child(off)
	ModLoaderLog.messages.clear()
	off.start()
	_check(off.get_child_count() == 0 and _count("gap_") == 0, "the gap probe does nothing unless enabled")
	off.stop()
	off.free()

	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, false, {}, true)
	root.add_child(observer)
	ModLoaderLog.messages.clear()
	observer.start()
	_check(observer.get_child_count() == 2, "the probe samples at both ends of the frame")
	_check(_count("gap_probe_bound type=breach_corps process_priority=0") == 2, "the windows' process priority is reported")
	for attack: int in 3:
		corps.detected = true
		corps.time = 9.0
		corps.firewall = 20.0
		game.Signals.tick.emit()
		await process_frame
		game.Signals.breached.emit(corps)
		await process_frame
		corps.detected = false
		corps.time = 10.0
		corps.firewall = 50.0
		game.Signals.tick.emit()
		await process_frame
		await process_frame
	corps.detected = true
	corps.firewall = 20.0
	game.Signals.tick.emit()
	await process_frame
	await process_frame
	corps.data.level = 4.0
	await process_frame
	await process_frame
	game.Signals.breached.emit(corps)
	await process_frame
	await process_frame
	_check(_count("gap_sequence type=breach_corps result=success") == 3, "attack ends are measured in the game's order")
	_check(_count("gap_level_change type=breach_corps") == 1, "a level change is measured")
	_check(corps.data.level == 4.0 and corps.forbidden_calls == 0 and twin.forbidden_calls == 0, "the probe never calls level_up or level_down")
	var lines := ModLoaderLog.messages.size()
	for frame: int in 30:
		await process_frame
	_check(ModLoaderLog.messages.size() == lines, "idle frames log nothing")
	twin.free()
	await process_frame
	observer.stop()
	_check(_count("gap_case type=breach_corps result=success") >= 1, "the totals are logged at stop")
	_check(_count("gap_common type=breach_corps nodes=2") == 1, "windows of one type are compared")
	_check(_count("gap_order type=breach_corps") == 1, "the order of changes is logged")
	_check(_count("gap_cost frames=") == 1 and _count("share_of_frame=") == 1, "the probe reports its own cost")
	await process_frame
	_check(observer.get_child_count() == 0, "stopping removes the hooks")
	observer.queue_free()
	await _remove_fake_game(game)


func _test_mod_main() -> void:
	var missing_main := ModMain.new()
	ModLoaderLog.messages.clear()
	root.add_child(missing_main)
	await process_frame
	await process_frame
	_check(_count("api_check result=failed") == 1, "missing API stops the mod without a crash")
	missing_main.queue_free()
	await process_frame

	var game := _install_fake_game()
	var main := ModMain.new()
	ModLoaderLog.messages.clear()
	root.add_child(main)
	await process_frame
	await process_frame
	_check(_count("api_check result=ok") == 1, "API check passes with the game present")
	_check(_count("observer state=started") == 1, "the observer starts")
	game.Globals.desktop = game.desktop
	var breach := FakeBreach.new()
	game.desktop.windows.add_child(breach)
	game.Signals.desktop_ready.emit()
	_check(_count("bind result=ok") == 1, "the window is bound when the desktop becomes ready")
	var stop_key := InputEventKey.new()
	stop_key.pressed = true
	stop_key.ctrl_pressed = true
	stop_key.alt_pressed = true
	stop_key.keycode = KEY_F10
	main._input(stop_key)
	_check(_count("emergency_stop actuator=none") == 1, "the emergency key always answers, even without an actuator")
	main.queue_free()
	await process_frame
	await _remove_fake_game(game)
