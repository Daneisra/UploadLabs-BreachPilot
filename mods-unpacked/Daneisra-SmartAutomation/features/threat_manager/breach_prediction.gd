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
