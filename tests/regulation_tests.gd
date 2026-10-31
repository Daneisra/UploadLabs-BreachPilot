extends RefCounted
## Forecast, regulator and ceilings, tested without the game. Random sequences use fixed seeds.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/features/threat_manager/"
const Forecast := preload(MOD + "breach_forecast.gd")
const PowerProfile := preload(MOD + "power_profile.gd")
const Regulator := preload(MOD + "threat_regulator.gd")
const RegulationState := preload(MOD + "regulation_state.gd")

const STATE_PATH := "user://smart_automation_test/threat_state.json"

var _check_call: Callable


func run(check: Callable) -> void:
	_check_call = check
	_test_profile()
	_test_infection_model()
	_test_forecast_status()
	_test_forecast_cost()
	_test_failures_needed()
	_test_raise_rules()
	_test_lower_rules()
	_test_power_changes()
	_test_dedup_and_budget()
	_test_units_at_speed_5()
	_test_profiles()
	_test_trust_and_safety()
	_test_long_sequences()
	_test_ceilings()


func _check(condition: bool, label: String) -> void:
	_check_call.call(condition, label)


func _profile(overrides: Dictionary = {}) -> Dictionary:
	var profile := {
		"damage_rate": 40.8655, "infection_rate": 0.0, "vulnerability": 0.0, "breach_variation": 0,
		"infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0,
	}
	profile.merge(overrides, true)
	profile.signature = PowerProfile.signature(profile)
	return profile


func _target(firewall: float, breach: float, time: float) -> Dictionary:
	return {"firewall": firewall, "breach": breach, "time": time}


func _test_profile() -> void:
	var event := {"damage_rate": 24.5, "infection_rate": 22.3, "interval": 1.02, "vulnerability": 0.0}
	var profile := PowerProfile.from_event(event)
	_check(is_equal_approx(profile.interval, 1.0), "the measured interval is rounded to the timer's step")
	_check(PowerProfile.has_infection(profile), "infection is recognized")
	_check(PowerProfile.from_event({"damage_rate": 24.5}, 1.0).interval == 1.0, "the last interval is reused when an attack has none")
	_check(profile.signature != PowerProfile.from_event({"damage_rate": 49.0, "infection_rate": 22.3}).signature, "a change of damage changes the signature")
	_check(profile.signature != PowerProfile.from_event({"damage_rate": 24.5}).signature, "infection appearing changes the signature")
	_check(profile.signature == PowerProfile.from_event({"damage_rate": 24.5, "infection_rate": 22.3, "tick_speed": 0.25}).signature, "the game speed is not part of the signature")


## Figures measured in the game on 2026-10-31.
func _test_infection_model() -> void:
	var usual := Forecast.attack_time(40.4, 161.6, 6.0, 1.0, 24.5, 22.3, 0.1)
	_check(absf(usual - 2.93) < 0.25, "level 4 with infection takes about 2.93 s, got %.2f" % usual)
	var seen_34 := Forecast.attack_time(40.4, 161.6, 6.0, 1.0, 24.5, 22.3, 0.55)
	_check(absf(seen_34 - 3.4) < 0.25, "the attack seen at 3.4 s with its first stack at 0.55 s, got %.2f" % seen_34)
	# The atypical attack: its first stack only came 2.55 s after the start.
	var atypical := Forecast.attack_time(40.4, 161.6, 6.0, 1.0, 24.5, 22.3, 2.55)
	_check(absf(atypical - 4.9) < 0.25, "the attack seen at 4.90 s fits a first stack at 2.55 s, got %.2f" % atypical)
	var elite := Forecast.attack_time(303.0, 1212.0, 12.0, 1.0, 24.5, 22.3, 0.1)
	_check(elite > 10.0 and elite < 10.8, "elite level 5 with infection takes about 10.5 s, got %.2f" % elite)
	_check(Forecast.attack_time(303.0, 1212.0, 12.0, 1.0, 40.87, 0.0, 0.0) < 0.0, "elite level 5 without infection fails")
	var coarse := Forecast.attack_time(303.0, 1212.0, 12.0, 1.0, 24.5, 22.3, 0.1, true, 0.25)
	_check(absf(coarse - elite) < 0.5, "the model holds at speed x5, got %.2f" % coarse)
	var firewall_first := Forecast.attack_time(100.0, 10.0, 12.0, 1.0, 0.0, 20.0, 0.0)
	_check(firewall_first > 2.5, "infection has to go through the firewall first, got %.2f" % firewall_first)


func _test_forecast_status() -> void:
	var measured := Forecast.forecast(_profile(), _target(40.4, 161.6, 6.0))
	_check(measured.status == "reliable" and absf(measured.p_success - 0.9988) < 0.001, "without infection the probability is exact")
	_check(measured.outcome == "mixed", "a small risk is reported as mixed")
	var impossible := Forecast.forecast(_profile(), _target(303.0, 1212.0, 12.0))
	_check(impossible.status == "reliable" and impossible.outcome == "fail", "a hopeless level is a reliable failure")
	var margin := Forecast.forecast(_profile(), _target(40.4, 161.6, 6.0), 0.2)
	_check(margin.p_success < measured.p_success, "a margin lowers the probability")

	var infected := _profile({"damage_rate": 24.5193, "infection_rate": 22.29})
	var easy := Forecast.forecast(infected, _target(18.0, 72.0, 6.0))
	_check(easy.status == "reliable" and easy.outcome == "pass", "infection passing in the worst case is reliable")
	_check(easy.infected, "the forecast says it relies on infection")
	var hard := Forecast.forecast(infected, _target(1000.0, 9000.0, 6.0))
	_check(hard.status == "reliable" and hard.outcome == "fail", "infection failing in the nominal case is reliable")
	var bounds := Forecast.forecast(infected, _target(303.0, 1212.0, 12.0))
	print("level 5 with infection: best %.2f, nominal %.2f, worst %.2f" % [bounds.used_min, bounds.used_nominal, bounds.used_max])
	_check(bounds.used_min < 10.6 and bounds.used_max > 10.6, "the envelope brackets the 10.55 s measured on elite level 5")
	var between: float = 1.0 - (bounds.used_nominal + bounds.used_max) / 2.0 / 12.0
	var borderline := Forecast.forecast(infected, _target(303.0, 1212.0, 12.0), between)
	_check(borderline.status == "uncertain", "between the worst and nominal cases is uncertain, got %s" % borderline.status)
	_check(borderline.p_success < 0.0, "an uncertain forecast gives no probability")

	for overrides: Dictionary in [{"vulnerability": 0.5}, {"breach_variation": 1}, {"infection_variation": 2}, {"infection_rate": 5.0, "infection_variation": 1}, {"interval": 0.0}, {"damage_rate": 5.0}]:
		_check(Forecast.forecast(_profile(overrides), _target(10.0, 10.0, 6.0)).status == "invalid", "unmeasured or unusable conditions are invalid: %s" % str(overrides))


func _test_forecast_cost() -> void:
	var started := Time.get_ticks_usec()
	for i: int in 50:
		Forecast.forecast(_profile({"damage_rate": 24.5 + i * 0.01, "infection_rate": 22.3}), _target(303.0, 1212.0, 12.0))
	var cost := (Time.get_ticks_usec() - started) / 50.0
	print("forecast with infection: %.0f us" % cost)
	_check(cost < 16000.0, "a forecast with infection stays under one frame")
	var huge := Forecast.forecast(_profile({"damage_rate": 24.5, "infection_rate": 22.3}), _target(1e12, 1e12, 1e9))
	_check(huge.status == "reliable" and huge.outcome == "fail", "an absurd target stays bounded")


func _test_failures_needed() -> void:
	print("failures needed over 20 attacks: 1%% %d, 3%% %d, 5%% %d" % [Regulator.failures_needed(20, 0.01), Regulator.failures_needed(20, 0.03), Regulator.failures_needed(20, 0.05)])
	_check(Regulator.failures_needed(20, 0.0) == 2, "no expected risk: 2 failures")
	_check(Regulator.failures_needed(20, 0.05) == 6, "5% risk over 20: 6 failures")
	_check(Regulator.failures_needed(20, 0.01) < Regulator.failures_needed(20, 0.05), "more expected risk needs more failures")
	_check(Regulator.failures_needed(10, 0.05) < Regulator.failures_needed(20, 0.05), "fewer attacks need fewer failures")
	_check(Regulator.failures_needed(2, 0.5) == 3, "a very high risk cannot be told from chance")


## Feeds attacks and returns the decisions.
func _feed(regulator: Regulator, count: int, event: String, level: int, next: Dictionary, current: Dictionary = {}, signature: String = "s", seconds: float = 4.0, max_level: int = 99) -> Array[Dictionary]:
	var decisions: Array[Dictionary] = []
	for i: int in count:
		regulator.advance(seconds)
		decisions.append(regulator.on_attack({"event": event, "complete": true, "level": level, "max_level": max_level, "signature": signature}, current, next))
	return decisions


func _good_next() -> Dictionary:
	return {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 3.0, "infected": false}


func _reliable(p: float) -> Dictionary:
	return {"status": "reliable", "outcome": "mixed", "p_success": p, "used_nominal": 3.0, "infected": false}


func _kinds(decisions: Array[Dictionary], kind: String) -> int:
	return decisions.filter(func(d: Dictionary) -> bool: return d.decision == kind).size()


func _test_raise_rules() -> void:
	var regulator := Regulator.new("balanced")
	var decisions := _feed(regulator, 20, "success", 4, _good_next())
	_check(_kinds(decisions, "raise") == 1, "a good level proposes a raise once")
	var raise_index := decisions.map(func(d: Dictionary) -> String: return d.decision).find("raise")
	_check(raise_index == 2 + 3 - 1, "after 2 stabilizing attacks and 3 successes, got %d" % raise_index)
	var second := Regulator.new("balanced")
	_feed(second, 5, "success", 4, _good_next())
	second.on_level_changed(5)
	_check(_feed(second, 3, "success", 5, _good_next(), {}, "s", 4.0).back().reason == "raise_delay", "a second raise waits for the delay")
	var raised: Dictionary = decisions[raise_index]
	_check(raised.real_level == 4 and raised.assumed_level == 5, "the decision separates the real and assumed levels")
	_check(raised.hypothetical, "the decision is hypothetical")

	for next: Dictionary in [{"status": "invalid"}, {"status": "uncertain"}, _reliable(0.5)]:
		var refused := _feed(Regulator.new("balanced"), 30, "success", 4, next)
		_check(_kinds(refused, "raise") == 0, "no raise on %s" % str(next))
	_check(_feed(Regulator.new("balanced"), 30, "success", 4, _good_next(), {}, "s", 4.0, 4).back().reason == "at_game_maximum", "no raise above the game's maximum")
	_check(_kinds(_feed(Regulator.new("balanced", 4), 30, "success", 4, _good_next()), "raise") == 0, "no raise above the allowed maximum")

	var capped := Regulator.new("balanced")
	capped.set_ceiling(4)
	var ceiling_decisions := _feed(capped, 30, "success", 4, _good_next())
	_check(_kinds(ceiling_decisions, "raise") == 0, "the manual ceiling is never exceeded")
	_check(ceiling_decisions.back().reason == "at_manual_ceiling", "the log says the ceiling is what stops it")

	var native := Regulator.new("balanced")
	native.set_native(true)
	var native_decisions := _feed(native, 30, "success", 4, _good_next())
	_check(_kinds(native_decisions, "raise") == 0 and native_decisions.back().reason == "blocked_native", "the native option blocks the regulator")


func _test_lower_rules() -> void:
	var regulator := Regulator.new("balanced")
	_feed(regulator, 2, "success", 5, {})
	var one := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	_check(one[0].decision == "hold", "one failure is not enough")
	var two := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	_check(two[0].decision == "lower" and two[0].assumed_level == 4, "two failures against no expected risk propose a lower")

	var risky := Regulator.new("aggressive")
	_feed(risky, 2, "success", 5, {})
	var mixed: Array[Dictionary] = []
	for i: int in 3:
		mixed.append_array(_feed(risky, 5, "success", 5, {}, _reliable(0.95)))
		mixed.append_array(_feed(risky, 1, "failure_power", 5, {}, _reliable(0.95)))
	_check(_kinds(mixed, "lower") == 0, "3 failures in 18 are expected at 5% risk")

	# Seen in the game: Government failed 223 times in a row and no lower was proposed, because a
	# forecast of certain failure made those failures look expected.
	for profile: String in ["conservative", "balanced", "aggressive"]:
		var hopeless := Regulator.new(profile)
		_feed(hopeless, 2, "failure_power", 4, {}, _reliable(0.0))
		var lowered: Array[Dictionary] = _feed(hopeless, 25, "failure_power", 4, {}, _reliable(0.0)).filter(func(d: Dictionary) -> bool: return d.decision == "lower")
		_check(lowered.size() == 1, "%s lowers a level that always fails, once" % profile)
		if not lowered.is_empty():
			_check(not lowered[0].forecast_refuted, "%s: a level expected to fail does not refute the forecast" % profile)
			_check(lowered[0].assumed_level == 3, "%s proposes one level down" % profile)
	var lowered_fast: Array[Dictionary] = _feed(Regulator.new("balanced"), 6, "failure_power", 4, {}, _reliable(0.0))
	_check(_kinds(lowered_fast, "lower") == 1, "balanced lowers a hopeless level within a few attacks")
	var tolerated := Regulator.new("aggressive")
	_feed(tolerated, 2, "success", 5, {})
	var within: Array[Dictionary] = []
	for i: int in 3:
		within.append_array(_feed(tolerated, 6, "success", 5, {}, _reliable(0.96)))
		within.append_array(_feed(tolerated, 1, "failure_power", 5, {}, _reliable(0.96)))
	_check(_kinds(within, "lower") == 0, "a level inside the accepted risk still tolerates chance")
	var outside := Regulator.new("balanced")
	_feed(outside, 2, "success", 5, {})
	var over: Array[Dictionary] = []
	for i: int in 4:
		over.append_array(_feed(outside, 4, "success", 5, {}, _reliable(0.96)))
		over.append_array(_feed(outside, 1, "failure_power", 5, {}, _reliable(0.96)))
	_check(_kinds(over, "lower") == 1, "the same 4% risk is not excused by a profile asking 99%")

	for event: String in ["failure_starved", "failure_paused", "reset_unknown", "level_changed_reset"]:
		var calm := Regulator.new("balanced")
		_feed(calm, 2, "success", 5, {})
		_check(_kinds(_feed(calm, 40, event, 5, {}), "lower") == 0, "%s never lowers" % event)

	var incomplete := Regulator.new("balanced")
	_feed(incomplete, 2, "success", 5, {})
	for i: int in 40:
		incomplete.advance(4.0)
		var decision := incomplete.on_attack({"event": "failure_power", "complete": false, "level": 5, "max_level": 9, "signature": "s"}, _reliable(1.0), {})
		_check(decision.decision == "hold", "an incomplete failure never lowers")

	var bottom := Regulator.new("balanced", -1, 5)
	_feed(bottom, 2, "success", 5, {})
	_check(_feed(bottom, 5, "failure_power", 5, {}, _reliable(1.0)).back().reason == "at_min_level", "never below the minimum level")


func _test_power_changes() -> void:
	var regulator := Regulator.new("balanced")
	_feed(regulator, 2, "success", 5, {})
	_feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	var changed := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0), "other")
	_check(changed[0].reason == "power_changed", "a power change is noticed")
	var settling := _feed(regulator, 2, "failure_power", 5, {}, _reliable(1.0), "other")
	_check(settling[0].reason == "stabilizing" and settling[1].reason == "stabilizing", "failures while stabilizing do not count")
	_check(_feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0), "other")[0].decision == "hold", "old failures were forgotten")

	var blocked := Regulator.new("balanced")
	_feed(blocked, 2, "success", 6, {})
	var lowered: Dictionary = _feed(blocked, 2, "failure_power", 6, {}, _reliable(1.0)).back()
	_check(lowered.decision == "lower", "the level is proposed for a lower")
	blocked.on_level_changed(5)
	_check(_feed(blocked, 20, "success", 5, _good_next()).back().reason == "level_blocked", "the failed level is blocked")
	var after := _feed(blocked, 30, "success", 5, _good_next(), {}, "stronger")
	_check(_kinds(after, "raise") == 1, "more power lifts the block")


func _test_dedup_and_budget() -> void:
	var regulator := Regulator.new("aggressive")
	var decisions := _feed(regulator, 200, "success", 4, _good_next())
	_check(_kinds(decisions, "raise") == 1, "a raise is not repeated while the real level stays the same")
	_check(regulator.suppressed_repeats > 100, "the repeats are counted")
	regulator.on_level_changed(4)
	_check(_kinds(_feed(regulator, 10, "success", 4, _good_next()), "raise") == 1, "the level moving allows a new proposal")

	var busy := Regulator.new("aggressive")
	var raises: Array[float] = []
	var clock := 0.0
	for attack: int in 40:
		for decision: Dictionary in _feed(busy, 4, "success", attack, _good_next(), {}, "s", 5.0):
			clock += 5.0
			if decision.decision == "raise":
				raises.append(clock)
	var fullest := 0
	for start: float in raises:
		fullest = maxi(fullest, raises.filter(func(t: float) -> bool: return t >= start and t < start + Regulator.BUDGET_WINDOW).size())
	_check(fullest == Regulator.BUDGET, "at most %d actions per window of 600 s, got %d" % [Regulator.BUDGET, fullest])

	var swinging := Regulator.new("aggressive")
	var moves := 0
	var frozen := false
	for round_index: int in 12:
		for decision: Dictionary in _feed(swinging, 6, "success", 4, _good_next(), {}, "s", 20.0):
			if decision.decision == "raise":
				moves += 1
			frozen = frozen or decision.reason.begins_with("frozen")
		swinging.on_level_changed(5)
		swinging.advance(200.0)
		for decision: Dictionary in _feed(swinging, 8, "failure_power", 5, {}, _reliable(1.0)):
			if decision.decision == "lower":
				moves += 1
			frozen = frozen or decision.reason.begins_with("frozen")
		swinging.on_level_changed(4)
		swinging._blocked.clear()
	_check(frozen, "repeated reversals freeze the regulator")


func _test_units_at_speed_5() -> void:
	var normal := Regulator.new("conservative")
	var fast := Regulator.new("conservative")
	var normal_decisions := _feed(normal, 40, "success", 4, _good_next(), {}, "s", 4.0)
	var fast_decisions: Array[Dictionary] = []
	for attack: int in 40:
		# The same 4 timer seconds, in 16 ticks of 0.25 s instead of 80 of 0.05 s.
		for tick: int in 16:
			fast.advance(0.25)
		fast_decisions.append(fast.on_attack({"event": "success", "complete": true, "level": 4, "max_level": 99, "signature": "s"}, {}, _good_next()))
	var first_raise := func(list: Array[Dictionary]) -> int: return list.map(func(d: Dictionary) -> String: return d.decision).find("raise")
	_check(first_raise.call(normal_decisions) == first_raise.call(fast_decisions), "delays are the same in timer seconds at speed x5")


func _test_profiles() -> void:
	var order: Array[int] = []
	for profile: String in ["conservative", "balanced", "aggressive"]:
		var decisions := _feed(Regulator.new(profile), 60, "success", 4, _good_next())
		order.append(decisions.map(func(d: Dictionary) -> String: return d.decision).find("raise"))
	_check(order[0] > order[1] and order[1] > order[2], "the more cautious the profile, the later the raise: %s" % str(order))
	var risk_98 := _reliable(0.98)
	_check(_kinds(_feed(Regulator.new("conservative"), 60, "success", 4, risk_98), "raise") == 0, "conservative refuses 98%")
	_check(_kinds(_feed(Regulator.new("balanced"), 60, "success", 4, risk_98), "raise") == 0, "balanced refuses 98%")
	_check(_kinds(_feed(Regulator.new("aggressive"), 60, "success", 4, risk_98), "raise") == 1, "aggressive accepts 98%")
	_check(_kinds(_feed(Regulator.new("aggressive"), 60, "success", 4, _reliable(0.94)), "raise") == 0, "aggressive refuses 94%")
	_check(Regulator.new("unknown").profile_name == "balanced", "an unknown profile falls back on balanced")
	_check(Regulator.new("conservative").margin() == 0.2 and Regulator.new("aggressive").margin() == 0.0, "margins come from the profile")


func _test_trust_and_safety() -> void:
	var infected := {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 3.0, "infected": true}
	var fresh := Regulator.new("aggressive")
	_check(_feed(fresh, 30, "success", 4, infected).back().reason == "forecast_uncertain", "an unverified infection model cannot propose a raise")
	var verified := Regulator.new("aggressive")
	_feed(verified, 1, "success", 4, infected)
	for i: int in 10:
		verified.note_forecast_check(true)
	_check(verified.model_trust() == "verified", "enough in-range checks verify the model")
	_check(_kinds(_feed(verified, 30, "success", 4, infected), "raise") == 1, "a verified model can propose a raise")
	var broken := Regulator.new("aggressive")
	_feed(broken, 1, "success", 4, infected)
	for i: int in 10:
		broken.note_forecast_check(true)
	broken.note_forecast_check(false)
	broken.note_forecast_check(false)
	_check(broken.model_trust() == "invalid", "out-of-range checks invalidate the model")
	_check(_feed(broken, 30, "success", 4, infected).back().reason == "forecast_invalid", "an invalid model cannot propose a raise")
	var changed := _feed(broken, 1, "success", 4, infected, {}, "new power")
	_check(changed[0].reason == "power_changed" and broken.model_trust() == "unverified", "new power means the model must prove itself again")

	var unsafe := Regulator.new("balanced")
	for i: int in 20:
		unsafe.note_event("reset_unknown", "time_not_expired")
	_check(unsafe.is_unsafe(), "unexplained resets make the classifier unsafe")
	_check(_feed(unsafe, 10, "failure_power", 5, {}, _reliable(1.0)).back().reason == "classifier_unsafe", "an unsafe classifier decides nothing")
	var explained := Regulator.new("balanced")
	for i: int in 20:
		explained.note_event("reset_unknown", "damage_changed")
	_check(not explained.is_unsafe(), "resets with a known cause do not count against the classifier")


## A simulated game: each level has a true success chance, and decisions are applied as if real.
func _run_sequence(profile: String, seed_value: int, attacks: int, true_chance: Callable, forecast_chance: Callable) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var regulator := Regulator.new(profile)
	var level := 0
	var reversals := 0
	var moves := 0
	var last_direction := ""
	var failures := 0
	var signature_of := func(index: int) -> String: return "power%d" % floori(float(index) / attacks * 3.0)
	for attack: int in attacks:
		regulator.advance(4.0)
		var progress := float(attack) / attacks
		var success: bool = random.randf() < true_chance.call(level, progress)
		failures += 0 if success else 1
		var p_current: float = forecast_chance.call(level, progress)
		var p_next: float = forecast_chance.call(level + 1, progress)
		var decision := regulator.on_attack(
			{"event": "success" if success else "failure_power", "complete": true, "level": level, "max_level": 40, "signature": signature_of.call(attack)},
			_reliable(p_current), _reliable(p_next))
		if decision.decision != "hold":
			moves += 1
			if not last_direction.is_empty() and decision.decision != last_direction:
				reversals += 1
			last_direction = decision.decision
			level = decision.assumed_level
			regulator.on_level_changed(level)
	return {"level": level, "reversals": reversals, "moves": moves, "failures": failures}


func _test_long_sequences() -> void:
	var step_chance := func(best: int) -> Callable:
		return func(level: int, _progress: float) -> float:
			if level <= best:
				return 1.0
			return 0.0

	for profile: String in ["conservative", "balanced", "aggressive"]:
		for seed_value: int in [1, 2, 3]:
			var calm := _run_sequence(profile, seed_value, 5000, step_chance.call(8), step_chance.call(8))
			_check(calm.level == 8, "%s reaches the best stable level, got %d" % [profile, calm.level])
			_check(calm.reversals == 0 and calm.failures == 0, "%s neither fails nor swings with a right forecast" % profile)

	# Chance alone: the current level fails 3% of the time, as the forecast knows.
	var random_chance := func(level: int, _progress: float) -> float:
		if level <= 6:
			return 1.0
		if level == 7:
			return 0.97
		return 0.0
	var noisy := _run_sequence("aggressive", 11, 20000, random_chance, random_chance)
	_check(noisy.level == 7, "aggressive holds a 97%% level despite its failures, got %d" % noisy.level)
	_check(noisy.reversals <= 2, "chance does not make it swing, got %d reversals" % noisy.reversals)

	# A wrong forecast: it promises level 9, which always fails. One hour is about 900 attacks.
	var wrong := _run_sequence("balanced", 12, 9000, step_chance.call(8), step_chance.call(9))
	_check(wrong.level <= 9, "a wrong forecast does not run away, got %d" % wrong.level)
	# This sequence goes through 3 powers: one raise and one lower each, so 5 reversals at most.
	_check(wrong.reversals <= 5, "a refuted forecast is only tried again when the power changes, got %d reversals" % wrong.reversals)
	_check(wrong.level == 8, "it settles on the level that really works, got %d" % wrong.level)

	# Growing power: the best level rises through three signatures.
	var growing_chance := func(level: int, progress: float) -> float:
		var best := 4 + floori(progress * 3.0) * 3
		return 1.0 if level <= best else 0.0
	var growing := _run_sequence("balanced", 13, 6000, growing_chance, growing_chance)
	_check(growing.level == 10, "the regulator follows growing power, got %d" % growing.level)

	# Falling power, with a forecast that sees it: the level follows it down.
	var falling_chance := func(level: int, progress: float) -> float:
		var best := 10 - floori(progress * 3.0) * 3
		return 1.0 if level <= best else 0.0
	var falling := _run_sequence("balanced", 14, 6000, falling_chance, falling_chance)
	_check(falling.level == 4, "the regulator follows falling power, got %d" % falling.level)

	var first := _run_sequence("balanced", 21, 3000, random_chance, random_chance)
	var again := _run_sequence("balanced", 21, 3000, random_chance, random_chance)
	_check(first == again, "a fixed seed gives the same sequence")


func _test_ceilings() -> void:
	if FileAccess.file_exists(STATE_PATH):
		DirAccess.remove_absolute(STATE_PATH)

	var session := RegulationState.new(STATE_PATH)
	session.set_slot("")
	session.apply_manual("breach_corps", 6)
	_check(session.ceiling("breach_corps") == 6, "lowering by hand sets the ceiling")
	session.apply_manual("breach_corps", 7)
	_check(session.ceiling("breach_corps") == 7, "raising by hand moves the ceiling, it does not remove it")
	_check(session.ceiling("breach_government") == -1, "each type has its own ceiling")
	_check(not session.is_persistent(), "without a slot identifier nothing is persistent")
	_check(not FileAccess.file_exists(STATE_PATH), "without a slot identifier nothing is written")
	session.set_slot("")
	_check(session.ceiling("breach_corps") == -1, "loading a game forgets session ceilings")
	_check(not session.apply_clear_token(5), "a clear token does nothing without a slot")

	var first_run := RegulationState.new(STATE_PATH)
	first_run.set_slot("slot_a")
	first_run.apply_manual("breach_corps", 6)
	first_run.set_slot("slot_b")
	_check(first_run.ceiling("breach_corps") == -1, "another slot is not affected")
	first_run.apply_manual("breach_corps", 3)
	first_run.set_slot("slot_a")
	_check(first_run.ceiling("breach_corps") == 6, "each slot keeps its ceiling")

	var restarted := RegulationState.new(STATE_PATH)
	restarted.set_slot("slot_a")
	_check(restarted.ceiling("breach_corps") == 6, "a ceiling survives a restart")
	restarted.set_slot("slot_b")
	_check(restarted.ceiling("breach_corps") == 3, "so does the other slot's")
	restarted.set_slot("slot_a")
	_check(not restarted.apply_clear_token(0), "an unchanged token removes nothing")
	_check(restarted.ceiling("breach_corps") == 6, "the ceiling is still there")
	_check(restarted.apply_clear_token(1), "changing the token is the explicit removal")
	_check(restarted.ceiling("breach_corps") == -1, "the ceiling is gone")
	_check(not restarted.apply_clear_token(1), "the token only acts once")
	restarted.set_slot("slot_b")
	_check(restarted.ceiling("breach_corps") == 3, "removal only affects the current slot")

	var again := RegulationState.new(STATE_PATH)
	again.set_slot("slot_a")
	_check(again.ceiling("breach_corps") == -1, "the removal survives a restart")
	DirAccess.remove_absolute(STATE_PATH)
	DirAccess.remove_absolute(STATE_PATH.get_base_dir())
