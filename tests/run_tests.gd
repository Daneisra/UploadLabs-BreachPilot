extends SceneTree
## Simulated tests. Run with:
## Godot_console.exe --headless --path . --script res://tests/run_tests.gd
## These scenarios are built from our reading of the game: they do not replace the in-game tests.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/"
const Classifier := preload(MOD + "features/threat_manager/breach_classifier.gd")
const Prediction := preload(MOD + "features/threat_manager/breach_prediction.gd")
const Observer := preload(MOD + "features/threat_manager/threat_observer.gd")
const ApiGuard := preload(MOD + "core/api_guard.gd")
const SaLog := preload(MOD + "core/sa_log.gd")
const ModMain := preload(MOD + "mod_main.gd")

const TICK := 0.05

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
	var vulnerability := FakeResource.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for script: GDScript in [Classifier, Prediction, Observer, ApiGuard, SaLog, ModMain]:
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
	_test_guard()
	await _test_observer()
	await _test_mod_main()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _sample(overrides: Dictionary = {}) -> Dictionary:
	var sample := {
		"instance_id": 1, "level": 3, "max_level": 5, "time": 10.0, "max_time": 10.0,
		"detected": false, "paused": false, "firewall": 50.0, "max_firewall": 50.0,
		"breached": 0.0, "max_breach": 50.0, "damage_rate": 100.0, "vulnerability": 0.0,
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
	_check(_count("api_dump") == 2, "api dump logs properties and signals")

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
	main.queue_free()
	await process_frame
	await _remove_fake_game(game)
