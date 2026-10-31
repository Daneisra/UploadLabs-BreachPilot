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
## Returns {} when the measure does not allow it. model_volleys reproduces the current level:
## if it differs from the observed volleys, the next-level figures should not be trusted.
static func volley_model(success: Dictionary) -> Dictionary:
	if not success.complete or success.volleys < 2 or success.damage_rate <= 0.0:
		return {}
	var interval: float = success.used / (success.volleys - 1)
	var per_volley: float = success.damage_rate * interval * (1.0 + success.vulnerability)
	if per_volley <= 0.0:
		return {}
	var hp := hp_factor(success.level)
	var next_max_time: float = success.max_time * hp / ratio_factor(success.level)
	var next_volleys := volleys_needed(success.max_firewall * hp, success.max_breach * hp, per_volley)
	var next_used: float = (next_volleys - 1) * interval
	return {
		"model_volleys": volleys_needed(success.max_firewall, success.max_breach, per_volley),
		"next_volleys": next_volleys,
		"next_used": next_used,
		"next_max_time": next_max_time,
		"next_model_ratio": next_used / next_max_time,
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
