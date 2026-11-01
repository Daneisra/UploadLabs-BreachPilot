extends RefCounted
## Forecast, regulator and pauses, tested without the game. Random sequences use fixed seeds.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/features/threat_manager/"
const Forecast := preload(MOD + "breach_forecast.gd")
const PowerProfile := preload(MOD + "power_profile.gd")
const Regulator := preload(MOD + "threat_regulator.gd")
const RegulationState := preload(MOD + "regulation_state.gd")

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
	_test_certain_raises()
	_test_observed_hits()
	_test_failures_in_row()
	_test_probes()
	_test_game_load()
	_test_pauses()


## The regulator's rules for raises it is not sure of.
func _reg(profile: String = "balanced", max_allowed: int = -1, min_level: int = 0) -> Regulator:
	return Regulator.new(profile, max_allowed, min_level, false)


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
	var regulator := _reg("balanced")
	var decisions := _feed(regulator, 20, "success", 4, _good_next())
	_check(_kinds(decisions, "raise") == 1, "a good level proposes a raise once")
	var raise_index := decisions.map(func(d: Dictionary) -> String: return d.decision).find("raise")
	_check(raise_index == 1 + 3 - 1, "after 1 stabilizing attack and 3 successes, got %d" % raise_index)
	var second := _reg("balanced")
	_feed(second, 5, "success", 4, _good_next())
	second.on_level_changed(5)
	_check(_feed(second, 3, "success", 5, _good_next(), {}, "s", 4.0).back().reason == "raise_delay", "a second raise waits for the delay")
	var raised: Dictionary = decisions[raise_index]
	_check(raised.real_level == 4 and raised.assumed_level == 5, "the decision separates the real and assumed levels")
	_check(raised.hypothetical, "the decision is hypothetical")

	for next: Dictionary in [{"status": "invalid"}, {"status": "uncertain"}, _reliable(0.5)]:
		var refused := _feed(_reg("balanced"), 30, "success", 4, next)
		_check(_kinds(refused, "raise") == 0, "no raise on %s" % str(next))
	_check(_feed(_reg("balanced"), 30, "success", 4, _good_next(), {}, "s", 4.0, 4).back().reason == "at_game_maximum", "no raise above the game's maximum")
	_check(_kinds(_feed(_reg("balanced", 4), 30, "success", 4, _good_next()), "raise") == 0, "no raise above the allowed maximum")

	var paused := _reg("balanced")
	paused.set_paused(true)
	var paused_decisions := _feed(paused, 30, "success", 4, _good_next())
	_check(_kinds(paused_decisions, "raise") == 0, "a pause stops raises")
	_check(paused_decisions.back().reason == "manual_pause", "the log says the pause is what stops it")
	_check(_kinds(_feed(paused, 30, "failure_power", 4, _reliable(1.0), {}), "lower") == 0, "and lowers")

	var native := _reg("balanced")
	native.set_native(true)
	var native_decisions := _feed(native, 30, "success", 4, _good_next())
	_check(_kinds(native_decisions, "raise") == 0 and native_decisions.back().reason == "blocked_native", "the native option blocks the regulator")


func _test_lower_rules() -> void:
	var regulator := _reg("balanced")
	_feed(regulator, 2, "success", 5, {})
	var one := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	_check(one[0].decision == "hold", "one failure is not enough")
	var two := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	_check(two[0].decision == "lower" and two[0].assumed_level == 4, "two failures against no expected risk propose a lower")

	var risky := _reg("aggressive")
	_feed(risky, 2, "success", 5, {})
	var mixed: Array[Dictionary] = []
	for i: int in 3:
		mixed.append_array(_feed(risky, 5, "success", 5, {}, _reliable(0.95)))
		mixed.append_array(_feed(risky, 1, "failure_power", 5, {}, _reliable(0.95)))
	_check(_kinds(mixed, "lower") == 0, "3 failures in 18 are expected at 5% risk")

	# Seen in the game: Government failed 223 times in a row and no lower was proposed, because a
	# forecast of certain failure made those failures look expected.
	for profile: String in ["conservative", "balanced", "aggressive"]:
		var hopeless := _reg(profile)
		_feed(hopeless, 1, "failure_power", 4, {}, _reliable(0.0))
		var lowered: Array[Dictionary] = _feed(hopeless, 25, "failure_power", 4, {}, _reliable(0.0)).filter(func(d: Dictionary) -> bool: return d.decision == "lower")
		_check(lowered.size() == 1, "%s lowers a level that always fails, once" % profile)
		if not lowered.is_empty():
			_check(not lowered[0].forecast_refuted, "%s: a level expected to fail does not refute the forecast" % profile)
			_check(lowered[0].assumed_level == 3, "%s proposes one level down" % profile)
	var lowered_fast: Array[Dictionary] = _feed(_reg("balanced"), 6, "failure_power", 4, {}, _reliable(0.0))
	_check(_kinds(lowered_fast, "lower") == 1, "balanced lowers a hopeless level within a few attacks")
	var tolerated := _reg("aggressive")
	_feed(tolerated, 2, "success", 5, {})
	var within: Array[Dictionary] = []
	for i: int in 3:
		within.append_array(_feed(tolerated, 6, "success", 5, {}, _reliable(0.96)))
		within.append_array(_feed(tolerated, 1, "failure_power", 5, {}, _reliable(0.96)))
	_check(_kinds(within, "lower") == 0, "a level inside the accepted risk still tolerates chance")
	var outside := _reg("balanced")
	_feed(outside, 2, "success", 5, {})
	var over: Array[Dictionary] = []
	for i: int in 4:
		over.append_array(_feed(outside, 4, "success", 5, {}, _reliable(0.96)))
		over.append_array(_feed(outside, 1, "failure_power", 5, {}, _reliable(0.96)))
	_check(_kinds(over, "lower") == 1, "the same 4% risk is not excused by a profile asking 99%")

	for event: String in ["failure_starved", "failure_paused", "reset_unknown", "level_changed_reset"]:
		var calm := _reg("balanced")
		_feed(calm, 2, "success", 5, {})
		_check(_kinds(_feed(calm, 40, event, 5, {}), "lower") == 0, "%s never lowers" % event)

	var incomplete := _reg("balanced")
	_feed(incomplete, 2, "success", 5, {})
	for i: int in 40:
		incomplete.advance(4.0)
		var decision := incomplete.on_attack({"event": "failure_power", "complete": false, "level": 5, "max_level": 9, "signature": "s"}, _reliable(1.0), {})
		_check(decision.decision == "hold", "an incomplete failure never lowers")

	var bottom := _reg("balanced", -1, 5)
	_feed(bottom, 2, "success", 5, {})
	_check(_feed(bottom, 5, "failure_power", 5, {}, _reliable(1.0)).back().reason == "at_min_level", "never below the minimum level")


func _test_power_changes() -> void:
	var regulator := _reg("balanced")
	_feed(regulator, 2, "success", 5, {})
	_feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0))
	var changed := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0), "other")
	_check(changed[0].reason == "power_changed", "a power change is noticed")
	var settling := _feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0), "other")
	_check(settling[0].reason == "stabilizing", "failures while stabilizing do not count")
	_check(_feed(regulator, 1, "failure_power", 5, {}, _reliable(1.0), "other")[0].decision == "hold", "old failures were forgotten")

	var blocked := _reg("balanced")
	_feed(blocked, 2, "success", 6, {})
	var lowered: Dictionary = _feed(blocked, 2, "failure_power", 6, {}, _reliable(1.0)).back()
	_check(lowered.decision == "lower", "the level is proposed for a lower")
	blocked.on_level_changed(5)
	_check(_feed(blocked, 20, "success", 5, _good_next()).back().reason == "level_blocked", "the failed level is blocked")
	var after := _feed(blocked, 30, "success", 5, _good_next(), {}, "stronger")
	_check(_kinds(after, "raise") == 1, "more power lifts the block")


func _test_dedup_and_budget() -> void:
	var regulator := _reg("aggressive")
	var decisions := _feed(regulator, 200, "success", 4, _good_next())
	_check(_kinds(decisions, "raise") == 1, "a raise is not repeated while the real level stays the same")
	_check(regulator.suppressed_repeats > 100, "the repeats are counted")
	regulator.on_level_changed(4)
	_check(_kinds(_feed(regulator, 10, "success", 4, _good_next()), "raise") == 1, "the level moving allows a new proposal")

	var busy := _reg("aggressive")
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

	var swinging := _reg("aggressive")
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
		swinging._raises_suspended = false
	_check(frozen, "repeated reversals freeze the regulator")


func _test_units_at_speed_5() -> void:
	var normal := _reg("conservative")
	var fast := _reg("conservative")
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
		var decisions := _feed(_reg(profile), 60, "success", 4, _good_next())
		order.append(decisions.map(func(d: Dictionary) -> String: return d.decision).find("raise"))
	_check(order[0] > order[1] and order[1] > order[2], "the more cautious the profile, the later the raise: %s" % str(order))
	var risk_98 := _reliable(0.98)
	_check(_kinds(_feed(_reg("conservative"), 60, "success", 4, risk_98), "raise") == 0, "conservative refuses 98%")
	_check(_kinds(_feed(_reg("balanced"), 60, "success", 4, risk_98), "raise") == 0, "balanced refuses 98%")
	_check(_kinds(_feed(_reg("aggressive"), 60, "success", 4, risk_98), "raise") == 1, "aggressive accepts 98%")
	_check(_kinds(_feed(_reg("aggressive"), 60, "success", 4, _reliable(0.94)), "raise") == 0, "aggressive refuses 94%")
	_check(_reg("unknown").profile_name == "balanced", "an unknown profile falls back on balanced")
	_check(_reg("conservative").margin() == 0.2 and _reg("aggressive").margin() == 0.0, "margins come from the profile")


func _test_trust_and_safety() -> void:
	var infected := {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 3.0, "infected": true}
	var fresh := _reg("aggressive")
	_check(_feed(fresh, 30, "success", 4, infected).back().reason == "forecast_uncertain", "an unverified infection model cannot propose a raise")
	var verified := _reg("aggressive")
	_feed(verified, 1, "success", 4, infected)
	for i: int in 10:
		verified.note_forecast_check(true)
	_check(verified.model_trust() == "verified", "enough in-range checks verify the model")
	_check(_kinds(_feed(verified, 30, "success", 4, infected), "raise") == 1, "a verified model can propose a raise")
	var broken := _reg("aggressive")
	_feed(broken, 1, "success", 4, infected)
	for i: int in 10:
		broken.note_forecast_check(true)
	broken.note_forecast_check(false)
	broken.note_forecast_check(false)
	_check(broken.model_trust() == "invalid", "out-of-range checks invalidate the model")
	_check(_feed(broken, 30, "success", 4, infected).back().reason == "forecast_invalid", "an invalid model cannot propose a raise")
	var changed := _feed(broken, 1, "success", 4, infected, {}, "new power")
	_check(changed[0].reason == "power_changed" and broken.model_trust() == "unverified", "new power means the model must prove itself again")

	var unsafe := _reg("balanced")
	for i: int in 20:
		unsafe.note_event("reset_unknown", "time_not_expired")
	_check(unsafe.is_unsafe(), "unexplained resets make the classifier unsafe")
	_check(_feed(unsafe, 10, "failure_power", 5, {}, _reliable(1.0)).back().reason == "classifier_unsafe", "an unsafe classifier decides nothing")
	var explained := _reg("balanced")
	for i: int in 20:
		explained.note_event("reset_unknown", "damage_changed")
	_check(not explained.is_unsafe(), "resets with a known cause do not count against the classifier")


## A simulated game: each level has a true success chance, and decisions are applied as if real.
func _run_sequence(profile: String, seed_value: int, attacks: int, true_chance: Callable, forecast_chance: Callable) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var regulator := _reg(profile)
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


func _test_certain_raises() -> void:
	var regulator := Regulator.new("conservative")
	var decisions := _feed(regulator, 3, "success", 4, _good_next(), {}, "s", 2.0)
	_check(decisions[0].reason == "stabilizing", "a new power still stabilizes")
	_check(decisions[1].decision == "raise" and decisions[1].certain, "then one success is enough when the next level is certain")
	_check(decisions[1].verify_attacks == 1, "and one attack verifies it")
	regulator.on_level_changed(5)
	_check(_feed(regulator, 1, "success", 5, _good_next(), {}, "s", 2.0)[0].decision == "raise", "and it does not wait for the profile's delay")
	regulator.on_level_changed(6)
	var climb := 0
	for level: int in range(6, 30):
		var step := _feed(regulator, 1, "success", level, _good_next(), {}, "s", 2.0)[0]
		climb += 1 if step.decision == "raise" else 0
		regulator.on_level_changed(level + 1)
	_check(climb == 24, "the budget of actions does not stop a certain climb: %d" % climb)

	for doubt: Dictionary in [_reliable(0.999), {"status": "uncertain", "p_success": 1.0}, {"status": "reliable", "p_success": 1.0, "used_nominal": 3.0, "infected": true}]:
		var slow := Regulator.new("aggressive")
		_check(_kinds(_feed(slow, 2, "success", 4, doubt, {}, "s", 2.0), "raise") == 0, "doubts keep the profile's rules: %s" % str(doubt))
	var verified := Regulator.new("conservative")
	var infected := {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 3.0, "infected": true}
	_feed(verified, 3, "success", 4, infected, {}, "s", 2.0)
	for i: int in 10:
		verified.note_forecast_check(true)
	var proven: Dictionary = _feed(verified, 1, "success", 4, infected, {}, "s", 2.0)[0]
	_check(proven.certain, "an infection model proven at this power is certain too")
	_check(proven.verify_attacks == 1, "and one attack verifies it")
	var moved := Regulator.new("balanced")
	_feed(moved, 3, "success", 4, _good_next(), {}, "old", 2.0)
	moved.on_level_changed(5)
	var fresh := _feed(moved, 3, "success", 5, _good_next(), {}, "new", 2.0)
	_check(fresh[0].reason == "power_changed" and fresh[1].reason == "stabilizing", "new power stabilizes first")
	_check(fresh[2].certain, "for one attack")
	var doubtful: Dictionary = _feed(_reg("balanced"), 8, "success", 4, _reliable(0.995)).filter(func(d: Dictionary) -> bool: return d.decision == "raise")[0]
	_check(doubtful.verify_attacks == 3 and not doubtful.certain, "a raise on doubts is still watched longer")

	# Straight to the best level, when it is certain.
	var jumping := Regulator.new("balanced")
	var far := {"status": "reliable", "outcome": "pass", "p_success": 1.0, "used_nominal": 5.0, "infected": false}
	jumping.advance(2.0)
	jumping.on_attack({"event": "success", "complete": true, "level": 1, "max_level": 9, "signature": "s"}, {}, _good_next())
	jumping.advance(2.0)
	var jump := jumping.on_attack({"event": "success", "complete": true, "level": 1, "max_level": 9, "signature": "s", "best_level": 5, "best_forecast": far}, {}, _good_next())
	_check(jump.decision == "raise" and jump.assumed_level == 5, "a certain level is reached at once: %s" % str(jump))
	var unsure_far := Regulator.new("balanced")
	unsure_far.advance(2.0)
	unsure_far.on_attack({"event": "success", "complete": true, "level": 1, "max_level": 9, "signature": "s"}, {}, _good_next())
	unsure_far.advance(2.0)
	var one_step := unsure_far.on_attack({"event": "success", "complete": true, "level": 1, "max_level": 9, "signature": "s", "best_level": 5, "best_forecast": {"status": "uncertain"}}, {}, _good_next())
	_check(one_step.decision == "raise" and one_step.assumed_level == 2, "an unsure far level is not jumped to")
	var no_jump := Regulator.new("balanced", 4)
	_check(not no_jump.can_reach(5) and no_jump.can_reach(4), "the allowed maximum limits the search")
	var blocked_jump := Regulator.new("balanced")
	blocked_jump._blocked[5] = INF
	_check(not blocked_jump.can_reach(5), "and so do blocked levels")
	_check(_kinds(_feed(_reg("balanced"), 8, "success", 4, _reliable(0.995)), "raise") == 1 and _feed(Regulator.new("balanced"), 3, "success", 4, _reliable(0.995)).filter(func(d: Dictionary) -> bool: return d.decision == "raise").is_empty(), "a likely level keeps the profile's rules")

	# One failure against a sure forecast: raises stop and it is logged, and only the normal conditions lower.
	var isolated := Regulator.new("balanced")
	_feed(isolated, 1, "success", 5, _good_next(), _reliable(1.0))
	var failed := _feed(isolated, 1, "failure_power", 5, _good_next(), _reliable(1.0))[0]
	_check(failed.decision == "hold" and failed.forecast_contradicted, "one failure is reported and does not lower")
	_check(isolated._raises_suspended and _feed(isolated, 1, "success", 5, _good_next(), _reliable(1.0))[0].reason == "raises_suspended", "raises are suspended at once")
	var calm_down := _feed(isolated, 40, "success", 5, _good_next(), _reliable(1.0))
	_check(_kinds(calm_down, "lower") == 0, "an isolated failure never lowers")
	_check(_kinds(calm_down, "raise") == 1 and calm_down.filter(func(d: Dictionary) -> bool: return d.decision == "raise")[0].verify_attacks == 3 and not calm_down.filter(func(d: Dictionary) -> bool: return d.decision == "raise")[0].certain, "after 20 clean attacks, raises come back with the profile's rules")
	var twice := Regulator.new("balanced")
	_feed(twice, 2, "success", 5, _good_next(), _reliable(1.0))
	_check(_feed(twice, 1, "failure_power", 5, {}, _reliable(1.0))[0].decision == "hold", "a first failure holds")
	var second: Dictionary = _feed(twice, 1, "failure_power", 5, {}, _reliable(1.0))[0]
	_check(second.decision == "lower" and not second.has("forecast_contradicted"), "the normal conditions then lower, with one report")

	# A refuted forecast brings the doubts back, until the power changes.
	var refuted := Regulator.new("conservative")
	_feed(refuted, 3, "success", 5, _good_next(), {}, "s", 2.0)
	refuted.on_level_changed(6)
	var lowered: Dictionary = _feed(refuted, 2, "failure_power", 6, {}, _reliable(1.0)).back()
	_check(lowered.decision == "lower" and lowered.forecast_refuted, "a certain level that fails is refuted")
	refuted.on_level_changed(5)
	_check(_kinds(_feed(refuted, 1, "success", 5, _good_next()), "raise") == 0, "after that, a raise is not certain any more")
	_check(_feed(refuted, 30, "success", 5, _good_next()).back().reason == "level_blocked", "and the refuted level stays blocked")
	var stronger := _feed(refuted, 3, "success", 5, _good_next(), {}, "stronger", 2.0)
	_check(stronger[2].decision == "raise" and stronger[2].certain, "more power makes it certain again, after stabilizing")

	var capped := Regulator.new("conservative", 4)
	_check(_kinds(_feed(capped, 5, "success", 4, _good_next()), "raise") == 0, "certainty does not cross the allowed maximum")
	var top := _feed(Regulator.new("conservative"), 5, "success", 4, _good_next(), {}, "s", 4.0, 4)
	_check(_kinds(top, "raise") == 0, "nor the game's maximum")
	var stopped := Regulator.new("conservative")
	stopped.set_paused(true)
	_check(_kinds(_feed(stopped, 5, "success", 4, _good_next()), "raise") == 0, "nor a pause")
	var native := Regulator.new("conservative")
	native.set_native(true)
	_check(_kinds(_feed(native, 5, "success", 4, _good_next()), "raise") == 0, "nor the native option")


## Seen in the game with a critical node: 87.39 announced, but hits of 53, and 132 one time in ten.
func _test_observed_hits() -> void:
	var profile := _profile({"damage_rate": 87.3867, "infection_rate": 48.1469, "infection_offset": 0.35})
	var signature_before: String = profile.signature
	PowerProfile.apply_observed_hits(profile, 52.0, 133.0)
	_check(is_equal_approx(profile.damage_rate, 52.0) and profile.hit_spread, "a forecast counts on the lowest hit seen")
	_check(profile.signature == signature_before, "and the power stays the same power")
	var level_8 := Forecast.forecast(profile, _target(205.0, 820.0, 6.0), 0.0)
	print("level 8 with critical hits: status %s used %s to %s" % [level_8.status, level_8.used_min, level_8.used_max])
	_check(level_8.used_min == 0.0 and (level_8.used_max < 0.0 or level_8.used_max + 0.15 >= 5.3), "the durations seen in the game fit the forecast: %s" % str(level_8))

	var plain := _profile({"damage_rate": 52.9616})
	PowerProfile.apply_observed_hits(plain, 52.0, 53.0)
	_check(is_equal_approx(plain.damage_rate, 52.9616) and not plain.has("hit_spread"), "hits as announced change nothing")
	var nothing := _profile({"damage_rate": 52.9616})
	PowerProfile.apply_observed_hits(nothing, -1.0, 0.0)
	_check(not nothing.has("hit_spread"), "and so do no hits at all")
	var high_only := _profile({"damage_rate": 52.9616})
	PowerProfile.apply_observed_hits(high_only, 52.0, 132.0)
	_check(is_equal_approx(high_only.damage_rate, 52.9616) and high_only.hit_spread, "hits above the announced figure only widen the durations")

	var spread := _profile({"damage_rate": 87.3867})
	PowerProfile.apply_observed_hits(spread, 53.0, 132.0)
	var sure := Forecast.forecast(spread, _target(101.0, 101.0, 6.0), 0.1)
	_check(sure.status == "reliable" and is_equal_approx(sure.p_success, 1.0) and sure.used_min == 0.0, "a level that passes with low hits alone stays certain: %s" % str(sure))
	var hopeless := Forecast.forecast(spread, _target(757.5, 757.5, 12.0), 0.1)
	_check(hopeless.outcome == "mixed" and hopeless.p_success == 0.0 and hopeless.status == "reliable", "a level needing lucky hits is never certain, but can pass: %s" % str(hopeless))
	var announced_only := _profile({"damage_rate": 87.3867})
	_check(Forecast.forecast(announced_only, _target(170.0, 170.0, 4.0), 0.0).p_success > Forecast.forecast(spread, _target(170.0, 170.0, 4.0), 0.0).p_success, "low hits make a level look harder than the announced figure")


## Seen in the game: 31 failures in a row at level 8, because level 7 was not safe either.
func _test_failures_in_row() -> void:
	var regulator := Regulator.new("balanced")
	_feed(regulator, 2, "success", 8, {}, _reliable(1.0))
	for failure_forecast: Dictionary in [{"status": "reliable", "outcome": "mixed", "p_success": 0.0}]:
		var first := _feed(regulator, 1, "failure_power", 8, {}, failure_forecast)[0]
		_check(first.decision == "hold", "one failure does not lower")
		var second := _feed(regulator, 1, "failure_power", 8, {}, failure_forecast)[0]
		_check(second.decision == "lower" and second.failures_in_row == 2, "two in a row do: %s" % str(second))
		_check(second.verify_attacks == 1, "and one attack verifies it")
	regulator.on_level_changed(7)
	regulator.advance(20.0)
	var hopeless := {"status": "reliable", "outcome": "mixed", "p_success": 0.0}
	_check(_feed(regulator, 1, "failure_power", 7, {}, hopeless)[0].decision == "lower", "a failure the forecast expected, with no success at this level, goes down at once")
	regulator.on_level_changed(6)
	regulator.advance(20.0)
	var unsure := {"status": "uncertain"}
	_check(_feed(regulator, 1, "failure_power", 6, {}, unsure)[0].decision == "hold", "an unsure forecast waits for a second failure")
	_check(_feed(regulator, 1, "failure_power", 6, {}, unsure)[0].decision == "lower", "and then goes down")
	var lucky := Regulator.new("balanced")
	_feed(lucky, 2, "success", 8, {}, hopeless)
	_check(_feed(lucky, 1, "failure_power", 8, {}, hopeless)[0].decision == "hold", "a success seen here keeps it from going down on one failure")
	var aimed := Regulator.new("balanced")
	aimed.advance(1.0)
	aimed.on_attack({"event": "success", "complete": false, "level": 8, "max_level": 9, "signature": "s"}, {}, {})
	aimed.advance(1.0)
	aimed.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s"}, hopeless, {})
	aimed.advance(1.0)
	var deep := aimed.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s", "target_down": 4}, hopeless, {})
	_check(deep.decision == "lower" and deep.assumed_level == 4, "it goes straight to the level that should work: %s" % str(deep))
	var floor_level := Regulator.new("balanced", -1, 6)
	floor_level.advance(1.0)
	floor_level.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s"}, hopeless, {})
	floor_level.advance(1.0)
	_check(floor_level.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s", "target_down": 4}, hopeless, {}).assumed_level == 6, "never below the minimum level")

	var interrupted := Regulator.new("balanced")
	_feed(interrupted, 2, "success", 8, {}, _reliable(0.5))
	_feed(interrupted, 1, "failure_power", 8, {}, _reliable(0.5))
	_feed(interrupted, 1, "success", 8, {}, _reliable(0.5))
	_feed(interrupted, 1, "failure_power", 8, {}, _reliable(0.5))
	_check(interrupted._failures_in_row == 1, "a success in between starts the count again")

	var accepted := Regulator.new("aggressive")
	_feed(accepted, 2, "success", 7, {}, _reliable(0.97))
	_check(_kinds(_feed(accepted, 2, "failure_power", 7, {}, _reliable(0.97)), "lower") == 0, "chance within the accepted risk can still fail twice")

	for event: String in ["failure_starved", "failure_paused", "reset_unknown", "level_changed_reset"]:
		var other := Regulator.new("balanced")
		_feed(other, 2, "success", 8, {}, _reliable(1.0))
		_check(_kinds(_feed(other, 10, event, 8, {}, _reliable(0.0)), "lower") == 0, "%s never counts" % event)
	var cut := Regulator.new("balanced")
	_feed(cut, 2, "success", 8, {}, _reliable(1.0))
	for i: int in 5:
		cut.advance(4.0)
		_check(cut.on_attack({"event": "failure_power", "complete": false, "level": 8, "max_level": 9, "signature": "s"}, _reliable(0.0), {}).decision == "hold", "nor does an incomplete failure")


func _test_probes() -> void:
	var trying := Regulator.new("balanced")
	var doubtful := {"status": "uncertain"}
	var attack := {"event": "success", "complete": true, "level": 7, "max_level": 9, "signature": "s", "probe_possible": true}
	var first := trying.on_attack(attack, {}, doubtful)
	_check(first.reason == "stabilizing", "a try waits for the stabilization")
	trying.advance(5.0)
	_check(trying.on_attack(attack, {}, doubtful).decision == "hold", "and for two successes")
	trying.advance(5.0)
	var tried := trying.on_attack(attack, {}, doubtful)
	_check(tried.decision == "raise" and tried.probe and tried.assumed_level == 8 and not tried.certain, "then it tries a level that may work: %s" % str(tried))
	trying.on_level_changed(8)
	trying.advance(5.0)
	var fails := trying.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s"}, doubtful, {})
	_check(fails.decision == "hold", "one failure does not end it")
	trying.advance(5.0)
	var back := trying.on_attack({"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s"}, doubtful, {})
	_check(back.decision == "lower" and back.assumed_level == 7, "two do")
	trying.on_level_changed(7)
	var later := {"event": "success", "complete": true, "level": 7, "max_level": 9, "signature": "s", "probe_possible": true}
	for i: int in 3:
		trying.advance(5.0)
		trying.on_attack(later, {}, doubtful)
	trying.advance(5.0)
	_check(trying.on_attack(later, {}, doubtful).reason == "level_blocked", "it waits before trying that level again")
	trying.advance(400.0)
	_check(trying.on_attack(later, {}, doubtful).probe, "and then tries again")

	var repeat := Regulator.new("balanced")
	var frozen := false
	var up := {"event": "success", "complete": true, "level": 7, "max_level": 9, "signature": "s", "probe_possible": true}
	var down := {"event": "failure_power", "complete": true, "level": 8, "max_level": 9, "signature": "s"}
	for round_index: int in 12:
		repeat.on_level_changed(7)
		for i: int in 4:
			repeat.advance(4000.0 if i == 0 else 5.0)
			frozen = frozen or repeat.on_attack(up, {}, doubtful).reason.begins_with("frozen")
		repeat.on_level_changed(8)
		for i: int in 2:
			repeat.advance(5.0)
			frozen = frozen or repeat.on_attack(down, doubtful, {}).reason.begins_with("frozen")
	_check(not frozen, "repeated tries do not freeze the regulator")

	var careful := Regulator.new("conservative")
	var none: Array[Dictionary] = []
	for i: int in 30:
		careful.advance(70.0)
		none.append(careful.on_attack(attack, {}, doubtful))
	_check(_kinds(none, "raise") == 0, "the conservative profile never tries")
	var no_hope := Regulator.new("balanced")
	var none_either: Array[Dictionary] = []
	for i: int in 30:
		no_hope.advance(70.0)
		none_either.append(no_hope.on_attack({"event": "success", "complete": true, "level": 7, "max_level": 9, "signature": "s", "probe_possible": false}, {}, _reliable(0.0)))
	_check(_kinds(none_either, "raise") == 0, "a level with no chance is not tried")
	var at_top := Regulator.new("balanced")
	var top_list: Array[Dictionary] = []
	for i: int in 10:
		at_top.advance(70.0)
		top_list.append(at_top.on_attack({"event": "success", "complete": true, "level": 9, "max_level": 9, "signature": "s", "probe_possible": true}, {}, doubtful))
	_check(_kinds(top_list, "raise") == 0, "nor above the game's maximum")

	# The unseen hit: nothing to count on, so the announced figure stands, and it says so.
	var unseen := _profile({"damage_rate": 87.3867})
	PowerProfile.apply_observed_hits(unseen, -1.0, 20.0)
	_check(unseen.hits_unseen and is_equal_approx(unseen.damage_rate, 87.3867), "without an uncut hit, the announced figure stands")


func _test_game_load() -> void:
	var regulator := Regulator.new("balanced")
	_feed(regulator, 3, "success", 4, _good_next(), {}, "s", 2.0)
	regulator.on_level_changed(5)
	regulator.on_game_loaded()
	var after := _feed(regulator, 2, "success", 3, _good_next(), {}, "s", 2.0)
	_check(after[0].reason == "stabilizing", "a load starts observing again: %s" % after[0].reason)
	_check(after[1].decision == "raise" and after[1].real_level == 3, "and judges the level it finds")
	var paused := Regulator.new("balanced")
	paused.set_paused(true)
	paused.on_game_loaded()
	_check(_feed(paused, 5, "success", 4, _good_next()).back().reason == "manual_pause", "a load does not lift a pause")

	var busy := Regulator.new("balanced")
	busy.set_action_busy(true)
	var waiting := _feed(busy, 5, "success", 4, _good_next())
	_check(_kinds(waiting, "raise") == 0 and waiting.back().reason == "previous_action_unverified", "nothing is proposed while another action is being verified")
	_check(busy._actions.is_empty(), "and it costs nothing")
	busy.set_action_busy(false)
	_check(_feed(busy, 1, "success", 4, _good_next())[0].decision == "raise", "it goes on after")


func _test_pauses() -> void:
	var state := RegulationState.new()
	_check(not state.is_paused("breach_corps"), "nothing is paused at first")
	_check(state.pause("breach_corps", "player_button") and state.is_paused("breach_corps"), "a type can be paused")
	_check(not state.pause("breach_corps", "player_level_change") and state.reason("breach_corps") == "player_button", "a second pause changes nothing")
	_check(not state.is_paused("breach_government"), "each type has its own")
	_check(state.resume("breach_corps") and not state.is_paused("breach_corps"), "a resume lifts it")
	_check(not state.resume("breach_corps"), "once")

	# The resume keeps what must not be forgotten: delays, blocks and the budget.
	var regulator := _reg("balanced")
	_feed(regulator, 2, "success", 6, {})
	var lowered: Dictionary = _feed(regulator, 2, "failure_power", 6, {}, _reliable(1.0)).back()
	_check(lowered.decision == "lower" and lowered.forecast_refuted, "a refuted level is proposed for a lower")
	regulator.on_level_changed(5)
	regulator.set_paused(true)
	_feed(regulator, 10, "success", 5, _good_next())
	var actions_before: int = regulator._actions.size()
	regulator.on_resume(5)
	_check(regulator._blocked.has(6) and regulator._blocked[6] == INF, "a refuted level stays blocked")
	_check(regulator._actions.size() == actions_before, "the budget stays spent")
	var after := _feed(regulator, 1, "success", 5, _good_next())
	_check(after[0].reason == "stabilizing", "observations start again: %s" % after[0].reason)
	_check(_feed(regulator, 30, "success", 5, _good_next()).back().reason == "level_blocked", "and the block still holds")

	var delayed := _reg("conservative")
	var first: Array[Dictionary] = _feed(delayed, 7, "success", 4, _good_next(), {}, "s", 20.0)
	_check(_kinds(first, "raise") == 1, "a raise is proposed")
	delayed.on_level_changed(5)
	delayed.set_paused(true)
	delayed.on_resume(5)
	var soon := _feed(delayed, 7, "success", 5, _good_next(), {}, "s", 1.0)
	_check(_kinds(soon, "raise") == 0 and soon.back().reason == "raise_delay", "a resume does not skip the delay: %s" % soon.back().reason)
