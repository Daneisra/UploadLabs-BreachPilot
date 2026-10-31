extends RefCounted
## Exact distribution of the volleys an attack needs. Pure calculations, results are only logged.
##
## Each hit is a whole number around base_hit: 40.865 gives 41 with probability 0.865, otherwise 40.
## A hit that finishes the firewall loses its excess. Damage over time (infection) is not modeled.
## The work is bounded: only volleys the timer allows are explored, at most MAX_VOLLEYS of them, with
## at most MAX_STATES distinct states per volley.

const MAX_VOLLEYS := 64
const MAX_STATES := 2048
const MIN_RELIABLE_HIT := 10.0
const EPSILON := 1e-9


## max_time and interval are in seconds of the window's timer. A tie with max_time counts as a
## failure, since only one such attack has been seen succeeding.
static func simulate(firewall: float, breach: float, max_time: float, interval: float, base_hit: float, bonus: float = 1.0, stealth: bool = false) -> Dictionary:
	if interval <= 0.0 or base_hit <= 0.0 or bonus <= 0.0:
		return {"ok": false, "reason": "no_damage"}
	var low := floorf(base_hit + EPSILON)
	var fraction := base_hit - low
	if fraction <= EPSILON:
		fraction = 0.0
	if low <= 0.0 and fraction <= 0.0:
		return {"ok": false, "reason": "no_damage"}

	var highest: float = (low + (1.0 if fraction > 0.0 else 0.0)) * bonus
	var lowest: float = low * bonus
	var best := _volleys_needed(firewall, breach, highest, stealth)
	var worst := _volleys_needed(firewall, breach, lowest, stealth) if lowest > 0.0 else -1
	var result := {
		"ok": true, "distribution": {}, "best": best, "worst": worst, "p_success": 0.0,
		"beyond_limit": 1.0, "truncated": false, "low_hit": base_hit < MIN_RELIABLE_HIT,
	}
	# Even with only the highest hits the target is out of reach: skip the work.
	if best > MAX_VOLLEYS:
		result.truncated = true
		result.worst = -1
		return result

	var outcomes: Array[Array] = [[lowest, 1.0 - fraction]]
	if fraction > 0.0:
		outcomes.append([highest, fraction])

	# The tie is kept in the distribution: it is a volley the game can still play.
	var time_limit := floori(max_time / interval + EPSILON) + 1
	var volley_limit := mini(MAX_VOLLEYS, time_limit)
	var distribution: Dictionary = {}
	var states: Dictionary = {_state_key(firewall, breach, stealth): [firewall, breach, 1.0]}
	for volley: int in range(1, volley_limit + 1):
		var next_states: Dictionary = {}
		for state: Array in states.values():
			for outcome: Array in outcomes:
				var probability: float = state[2] * outcome[1]
				if probability <= 0.0 or outcome[0] <= 0.0:
					continue
				var remaining := _apply_hit(state[0], state[1], outcome[0], stealth)
				if remaining[1] <= EPSILON:
					distribution[volley] = distribution.get(volley, 0.0) + probability
				else:
					var key := _state_key(remaining[0], remaining[1], stealth)
					if next_states.has(key):
						next_states[key][2] += probability
					else:
						next_states[key] = [remaining[0], remaining[1], probability]
		states = next_states
		if states.is_empty():
			break
		if states.size() > MAX_STATES:
			result.truncated = true
			break

	var beyond := 0.0
	for state: Array in states.values():
		beyond += state[2]
	if beyond > EPSILON and volley_limit == MAX_VOLLEYS and time_limit > MAX_VOLLEYS:
		result.truncated = true
	var p_success := 0.0
	for volley: int in distribution:
		if (volley - 1) * interval < max_time - EPSILON:
			p_success += distribution[volley]
	result.distribution = distribution
	result.p_success = p_success
	result.beyond_limit = beyond
	return result


static func format_distribution(distribution: Dictionary) -> String:
	var keys := distribution.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key: int in keys:
		parts.append("%d:%.4f" % [key, distribution[key]])
	return ",".join(parts)


static func _volleys_needed(firewall: float, breach: float, hit: float, stealth: bool) -> int:
	var on_firewall := 0 if stealth else ceili(firewall / hit - EPSILON)
	return on_firewall + ceili(breach / hit - EPSILON)


static func _apply_hit(firewall: float, breach: float, damage: float, stealth: bool) -> Array[float]:
	if stealth or firewall <= EPSILON:
		return [firewall, breach - damage]
	return [maxf(firewall - damage, 0.0), breach]


## One number is enough: the breach bar only moves once the firewall is down, unless hits ignore it.
static func _state_key(firewall: float, breach: float, stealth: bool) -> float:
	return breach if stealth or firewall <= EPSILON else -firewall
