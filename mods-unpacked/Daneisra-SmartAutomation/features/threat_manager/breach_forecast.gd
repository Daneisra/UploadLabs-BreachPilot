extends RefCounted
## Forecasts an attack on given targets. Pure calculations, only used to explain simulated decisions.
##
## status is "reliable", "uncertain" or "invalid". Without infection the volley simulator gives an
## exact probability. With infection a deterministic envelope is used: passing in the worst case is
## reliable, failing in the nominal case is reliable, anything between is uncertain.

const BreachSimulator := preload("breach_simulator.gd")
const PowerProfile := preload("power_profile.gd")

const STEALTH_BIT := 1
const INFECTED_BIT := 2
const OFFSETS: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.95]
const NOMINAL_OFFSET := 0.5
const MAX_STEPS := 4000


## target holds firewall, breach and time. margin shortens the time the forecast may count on.
static func forecast(profile: Dictionary, target: Dictionary, margin: float = 0.0) -> Dictionary:
	var result := {
		"status": "invalid", "outcome": "unknown", "p_success": -1.0, "used_min": -1.0, "used_max": -1.0,
		"used_nominal": -1.0, "may_fail": true, "infected": PowerProfile.has_infection(profile), "reasons": PackedStringArray(),
	}
	if profile.interval <= 0.0:
		result.reasons.append("no_interval")
	if profile.damage_rate <= 0.0 and not result.infected:
		result.reasons.append("no_damage")
	if profile.breach_variation & STEALTH_BIT or profile.infection_variation & STEALTH_BIT:
		result.reasons.append("stealth_unmeasured")
	if profile.infection_variation & INFECTED_BIT or profile.breach_variation & INFECTED_BIT:
		result.reasons.append("infected_growth_unmeasured")
	if profile.vulnerability > 0.0:
		result.reasons.append("vulnerability_unmeasured")
	if not result.reasons.is_empty():
		return result
	var base_hit: float = profile.damage_rate * profile.interval
	if base_hit > 0.0 and base_hit < BreachSimulator.MIN_RELIABLE_HIT:
		result.reasons.append("low_hit")
		return result
	if result.infected:
		_forecast_infected(profile, target, margin, result)
	else:
		_forecast_volleys(profile, target, margin, base_hit, result)
	# With hits above the ones counted on, an attack can always end sooner, or pass despite a failure forecast.
	if profile.get("hit_spread", false) and result.status == "reliable":
		result.used_min = 0.0
		if result.outcome == "fail":
			result.outcome = "mixed"
	return result


static func _forecast_volleys(profile: Dictionary, target: Dictionary, margin: float, base_hit: float, result: Dictionary) -> void:
	var interval: float = profile.interval
	var usable_time: float = target.time * (1.0 - margin)
	var simulation := BreachSimulator.simulate(target.firewall, target.breach, usable_time, interval, base_hit)
	if not simulation.ok or simulation.truncated:
		result.reasons.append("truncated" if simulation.ok else simulation.reason)
		return
	result.status = "reliable"
	result.p_success = simulation.p_success
	result.used_min = (simulation.best - 1) * interval
	result.used_max = (simulation.worst - 1) * interval
	result.used_nominal = result.used_min
	result.may_fail = result.used_max >= target.time
	if simulation.p_success >= 1.0 - BreachSimulator.EPSILON:
		result.outcome = "pass"
	elif simulation.p_success <= BreachSimulator.EPSILON:
		result.outcome = "fail"
	else:
		result.outcome = "mixed"


static func _forecast_infected(profile: Dictionary, target: Dictionary, margin: float, result: Dictionary) -> void:
	var interval: float = profile.interval
	var low_hit := floorf(profile.damage_rate * interval)
	var high_hit := ceilf(profile.damage_rate * interval)
	var low_stack := floorf(profile.infection_rate * interval)
	var high_stack := ceilf(profile.infection_rate * interval)
	var usable_time: float = target.time * (1.0 - margin)

	var worst := -1.0
	var best := -1.0
	var worst_fails := false
	for offset: float in OFFSETS:
		for volley_first: bool in [true, false]:
			var slow := attack_time(target.firewall, target.breach, target.time, interval, low_hit, low_stack, offset * interval, volley_first, profile.tick_speed)
			var fast := attack_time(target.firewall, target.breach, target.time, interval, high_hit, high_stack, offset * interval, volley_first, profile.tick_speed)
			if slow < 0.0:
				worst_fails = true
			else:
				worst = maxf(worst, slow)
			if fast >= 0.0:
				best = fast if best < 0.0 else minf(best, fast)
	var nominal_offset: float = profile.infection_offset if profile.infection_offset >= 0.0 else NOMINAL_OFFSET * interval
	var nominal := attack_time(target.firewall, target.breach, target.time, interval, profile.damage_rate * interval, profile.infection_rate * interval, nominal_offset, true, profile.tick_speed)

	result.used_min = best
	result.used_max = worst
	result.used_nominal = nominal
	result.may_fail = worst_fails
	var worst_within := not worst_fails and worst < usable_time
	var nominal_beyond := nominal < 0.0 or nominal >= usable_time
	if worst_within:
		result.status = "reliable"
		result.outcome = "pass"
		result.p_success = 1.0
	elif nominal_beyond:
		result.status = "reliable"
		result.outcome = "fail"
		result.p_success = 0.0
	else:
		result.status = "uncertain"
		result.reasons.append("between_worst_and_nominal")


## Timer seconds used, or -1.0 on failure. Starts at the first damage. A volley that finishes the
## firewall loses its excess, and infection deals its stack per second on the firewall first.
static func attack_time(firewall: float, breach: float, max_time: float, interval: float, hit: float, stack_gain: float, offset: float, volley_first: bool = true, tick: float = 0.05) -> float:
	if tick <= 0.0:
		return -1.0
	var next_volley := 0.0 if volley_first else maxf(offset, 0.0)
	var next_pulse := offset if volley_first else 0.0
	var stack := 0.0
	var time := 0.0
	var steps := 0
	while time < max_time and steps < MAX_STEPS:
		var volley := 0.0
		while time >= next_volley - 1e-9:
			volley += hit
			next_volley += interval
		while stack_gain > 0.0 and time >= next_pulse - 1e-9:
			stack += stack_gain
			next_pulse += interval
		var over_time := stack * tick
		if firewall > 0.0:
			firewall = maxf(firewall - volley, 0.0)
			volley = 0.0
		if firewall > 0.0:
			firewall = maxf(firewall - over_time, 0.0)
			over_time = 0.0
		breach -= volley + over_time
		if breach <= 0.0:
			return time
		time += tick
		steps += 1
	return -1.0
