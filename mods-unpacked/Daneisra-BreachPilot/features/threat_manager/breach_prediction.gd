extends RefCounted
## Pure calculations for the difficulty of the next level. Experimental: results are only logged.

const HP_STEP := 1.5
const ELITE_HP := 5.0
const ELITE_TIME := 2.0
const DAMAGE_TOLERANCE := 0.05
const HP_TOLERANCE := 0.01


static func is_elite(level: int) -> bool:
	return level > 0 and level % 5 == 0


## How much the hit points grow from one level to the next.
static func hp_factor(level: int) -> float:
	var factor := HP_STEP
	if is_elite(level + 1):
		factor *= ELITE_HP
	if is_elite(level):
		factor /= ELITE_HP
	return factor


## How much the time ratio (used / max) grows from one level to the next.
static func ratio_factor(level: int) -> float:
	var factor := hp_factor(level)
	if is_elite(level + 1):
		factor /= ELITE_TIME
	if is_elite(level):
		factor *= ELITE_TIME
	return factor


static func next_ratio(ratio: float, level: int) -> float:
	return ratio * ratio_factor(level)


## Damage lands in volleys, and a volley that finishes the firewall loses its excess.
static func volleys_needed(firewall: float, breach: float, per_volley: float) -> int:
	return ceili(firewall / per_volley) + ceili(breach / per_volley)


## Predicts the next level from a complete success, volley by volley.
## Returns {} when the measure does not allow it.
##
## Measured hits look like whole numbers drawn around the displayed rate (40 or 41 for 40.865), so
## each figure comes as a lucky case and a _worst case. model_volleys and model_volleys_worst replay
## the current level: observed volleys outside that range mean the figures should not be trusted.
static func volley_model(success: Dictionary) -> Dictionary:
	if not success.complete or success.volleys < 2 or success.damage_rate <= 0.0:
		return {}
	var interval: float = success.used / (success.volleys - 1)
	var base_hit: float = success.damage_rate * interval
	var bonus: float = 1.0 + success.vulnerability
	var best_hit: float = ceilf(base_hit) * bonus
	var worst_hit: float = floorf(base_hit) * bonus
	if worst_hit <= 0.0:
		return {}
	var hp := hp_factor(success.level)
	var next_firewall: float = success.max_firewall * hp
	var next_breach: float = success.max_breach * hp
	var next_max_time: float = success.max_time * hp / ratio_factor(success.level)
	var next_volleys := volleys_needed(next_firewall, next_breach, best_hit)
	var next_volleys_worst := volleys_needed(next_firewall, next_breach, worst_hit)
	return {
		"model_volleys": volleys_needed(success.max_firewall, success.max_breach, best_hit),
		"model_volleys_worst": volleys_needed(success.max_firewall, success.max_breach, worst_hit),
		"next_volleys": next_volleys,
		"next_volleys_worst": next_volleys_worst,
		"next_used": (next_volleys - 1) * interval,
		"next_max_time": next_max_time,
		"next_model_ratio": (next_volleys - 1) * interval / next_max_time,
		"next_model_ratio_worst": (next_volleys_worst - 1) * interval / next_max_time,
	}


## Returns "" when two successes can be compared, otherwise the reason they cannot.
static func incomparable_reason(previous: Dictionary, current: Dictionary) -> String:
	if not previous.complete or not current.complete:
		return "incomplete"
	if current.level != previous.level + 1:
		return "not_consecutive"
	if previous.damage_rate <= 0.0 or current.damage_rate <= 0.0:
		return "no_damage_rate"
	if absf(current.damage_rate / previous.damage_rate - 1.0) > DAMAGE_TOLERANCE:
		return "damage_changed"
	var previous_hp: float = previous.max_firewall + previous.max_breach
	var current_hp: float = current.max_firewall + current.max_breach
	if previous_hp <= 0.0:
		return "no_hp"
	if absf(current_hp / previous_hp / hp_factor(previous.level) - 1.0) > HP_TOLERANCE:
		return "difficulty_changed"
	return ""
