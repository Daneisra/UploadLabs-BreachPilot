extends RefCounted
## Which level brings the most for the objective chosen in the panel. Pure: it gets each level's chance,
## time from one attack to the next and rewards, and has no access to the game. Nothing here knows
## which levels are elite: a level pays what the game says it pays.

const XP := "xp"
const BALANCED := "balanced"
## Below this, a better level is noise from the random attacks, and not worth leaving the highest one.
const MIN_GAIN := 0.05


## What a level brings per minute: {"reward": ..., "xp": ...}. entry holds chance, cycle, reward and xp.
static func rates(entry: Dictionary) -> Dictionary:
	if entry.cycle <= 0.0:
		return {"reward": 0.0, "xp": 0.0}
	return {"reward": entry.chance * entry.reward / entry.cycle * 60.0, "xp": entry.chance * entry.xp / entry.cycle * 60.0}


## How good a level is for the objective. own_key is the objective that names this target's reward:
## an objective naming another target does not depend on this one, which then keeps a balance.
## Balanced is the worse of the two changes against the reference: a level only wins on both.
static func score(entry: Dictionary, objective: String, own_key: String, reference: Dictionary) -> float:
	var brought := rates(entry)
	if objective == XP:
		return brought.xp
	if objective == own_key:
		return brought.reward
	return minf(_ratio(brought.reward, reference.reward), _ratio(brought.xp, reference.xp))


## levels: level -> {chance, cycle, reward, xp}, only those that can be reached. Returns the level that
## brings the most among those holding with the required chance, or -1 when none does. The highest one
## stays unless another is really better.
static func profitable(levels: Dictionary, objective: String, own_key: String, required: float) -> int:
	var highest := -1
	for level: int in levels:
		if levels[level].chance >= required and level > highest:
			highest = level
	if highest < 0:
		return -1
	var reference := rates(levels[highest])
	var best := highest
	var best_score := score(levels[highest], objective, own_key, reference) * (1.0 + MIN_GAIN)
	for level: int in levels:
		var entry: Dictionary = levels[level]
		if entry.chance < required:
			continue
		var value := score(entry, objective, own_key, reference)
		if value > best_score:
			best = level
			best_score = value
	return best


## The highest level unlocked opens the next one once won. Worth a try when it may hold, else -1.
static func to_unlock(levels: Dictionary, current: int, max_level: int, trial: float) -> int:
	if max_level <= current or not levels.has(max_level) or levels[max_level].chance < trial:
		return -1
	return max_level


static func _ratio(value: float, reference: float) -> float:
	return value / reference if reference > 0.0 else 1.0
