extends RefCounted
## Compares ways of connecting the hacking chain. Pure calculations on the values read by HackingChain:
## nothing here touches the game. Attacks are drawn at random with the game's critical hits, because
## at the limit a level often only works thanks to them, and XP doubles with each level.

const NORMAL_TICK := 0.05
## Time from the end of an attack to the start of the next: measured 0.65 and 0.77 s on the longest runs.
const ATTACK_GAP := 0.7
const SAMPLES := 150
const EARLY_SAMPLES := 30
## From this chance on, the regulation holds a level long enough for it to count. Two failures in a row lower it.
const MIN_HOLD := 0.8
## An elite level can fail between two that work, but not two levels in a row.
const FAILED_IN_ROW_STOP := 2
const SEED := 20261101
## How late the infection starts, in intervals. The lag is fitted on the logs: it gives 50 % for the 48 and 47 %
## measured over 40 attacks at the limit, and 4.59 s for the 4.59 s measured over 225 attacks. The logs show
## an extra 0.35 in about one attack in seven.
const INFECTION_LAG := 0.25
const LATE_INFECTION := 0.35
const LATE_INFECTION_CHANCE := 0.15
## How far from the announced value the chain can be before its rules are said not to apply.
const CHAIN_TOLERANCE := 0.05

var _chain: Dictionary
var _results := {}


func _init(chain: Dictionary) -> void:
	_chain = chain


## Every payload target set with at least one target, against every infection target set.
func scenarios() -> Array[Dictionary]:
	var types: Array = _chain.targets.keys()
	var payload_sets := _subsets(types, false)
	var infection_sets := _subsets(types, true) if _chain.has_infection else [[]]
	var list: Array[Dictionary] = []
	for payload: Array in payload_sets:
		for infection: Array in infection_sets:
			list.append({"payload": payload, "infection": infection})
	return list


func current_scenario() -> Dictionary:
	return {"payload": _chain.current.payload, "infection": _chain.current.infection}


func is_current(scenario: Dictionary) -> bool:
	return _same_set(scenario.payload, _chain.current.payload) and _same_set(scenario.infection, _chain.current.infection)


## The announced damage must come out of the rules, or comparing scenarios would mean nothing.
func chain_problems() -> PackedStringArray:
	var problems := PackedStringArray(_chain.get("problems", []))
	var share := power_share(_chain.current.infection)
	for type: String in _chain.current.payload:
		var expected: float = share * _chain.launcher_ratio * _chain.crit_factor / _chain.current.payload.size()
		if not _close(_chain.targets[type].announced_payload, expected):
			problems.append("payload_mismatch:%s" % type)
	for type: String in _chain.current.infection:
		var expected: float = share * _chain.infection_ratio / _chain.current.infection.size()
		if not _close(_chain.targets[type].announced_infection, expected):
			problems.append("infection_mismatch:%s" % type)
	return problems


## The source splits its power evenly: taking the infection off leaves it all to the launcher.
func power_share(infection: Array) -> float:
	var consumers: int = 1 + _chain.other_consumers + (0 if infection.is_empty() else 1)
	return _chain.power / consumers


func evaluate(scenario: Dictionary) -> Dictionary:
	var share := power_share(scenario.infection)
	var row := {"scenario": scenario, "current": is_current(scenario), "targets": {}, "xp_rate": 0.0}
	for type: String in _chain.targets:
		var hit: float = share * _chain.launcher_ratio / scenario.payload.size() if scenario.payload.has(type) else 0.0
		var stack: float = share * _chain.infection_ratio / scenario.infection.size() if scenario.infection.has(type) else 0.0
		var best := _best_level(type, hit, stack)
		row.targets[type] = best
		row.xp_rate += best.xp_rate
	return row


## The highest level likely to hold. Above the highest unlocked level, one only opens once the one before it works.
func _best_level(type: String, hit: float, stack: float) -> Dictionary:
	var key := "%s|%s|%s" % [type, hit, stack]
	if _results.has(key):
		return _results[key]
	var target: Dictionary = _chain.targets[type]
	var best := {"level": -1, "chance": 0.0, "used": -1.0, "reward_rate": 0.0, "xp_rate": 0.0, "hit": hit, "stack": stack, "invalid": false}
	if target.vulnerability > 0.0 or target.breach_variation != 0 or target.infection_variation != 0:
		# Stealth, growing infection and vulnerability have never been measured: no figure rather than a wrong one.
		best.invalid = true
	elif hit > 0.0 or stack > 0.0:
		var levels: Array = target.levels.keys()
		levels.sort()
		var failed_in_row := 0
		for level: int in levels:
			var values: Dictionary = target.levels[level]
			var outcome := attack_outcome(values, hit, stack)
			if outcome.chance >= MIN_HOLD:
				failed_in_row = 0
				var time: float = values.time * _chain.time_factor
				var cycle: float = outcome.chance * outcome.used + (1.0 - outcome.chance) * time + ATTACK_GAP
				best.level = level
				best.chance = outcome.chance
				best.used = outcome.used
				best.reward_rate = outcome.chance * values.reward / cycle * 60.0
				best.xp_rate = outcome.chance * values.xp / cycle * 60.0
			else:
				failed_in_row += 1
				if level > target.max_level or failed_in_row >= FAILED_IN_ROW_STOP:
					break
	_results[key] = best
	return best


## chance of success and average duration of the attacks that succeed. The same seed gives two
## scenarios the same luck, so that a small gap between them is not just noise.
func attack_outcome(values: Dictionary, hit: float, stack: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var time: float = values.time * _chain.time_factor
	var successes := 0
	var total_used := 0.0
	var samples := 0
	while samples < SAMPLES:
		samples += 1
		var used := _attack(rng, values.firewall, values.breach, time, hit, stack)
		if used >= 0.0:
			successes += 1
			total_used += used
		if samples == EARLY_SAMPLES and successes == 0:
			break
	return {"chance": float(successes) / samples, "used": total_used / successes if successes > 0 else -1.0}


## One attack, tick by tick, as BreachForecast.attack_time, with whole random hits and critical hits.
func _attack(rng: RandomNumberGenerator, firewall: float, breach: float, max_time: float, hit: float, stack_gain: float) -> float:
	var interval: float = _chain.interval
	var next_volley := 0.0
	var next_pulse: float = (INFECTION_LAG + (LATE_INFECTION if rng.randf() < LATE_INFECTION_CHANCE else 0.0)) * interval
	var stack := 0.0
	var time := 0.0
	while time < max_time:
		var volley := 0.0
		while time >= next_volley - 1e-9:
			if hit > 0.0:
				volley += _whole(rng, hit) * (1.0 + _chain.crit_multiplier if rng.randf() < _chain.crit_chance else 1.0)
			next_volley += interval
		while time >= next_pulse - 1e-9:
			if stack_gain > 0.0:
				stack += _whole(rng, stack_gain)
			next_pulse += interval
		var over_time := stack * NORMAL_TICK
		if firewall > 0.0:
			firewall = maxf(firewall - volley, 0.0)
			volley = 0.0
		if firewall > 0.0:
			firewall = maxf(firewall - over_time, 0.0)
			over_time = 0.0
		breach -= volley + over_time
		if breach <= 0.0:
			return time
		time += NORMAL_TICK
	return -1.0


func _whole(rng: RandomNumberGenerator, value: float) -> float:
	var low := floorf(value)
	return low + 1.0 if rng.randf() < value - low else low


func _subsets(types: Array, with_empty: bool) -> Array:
	var list := []
	for mask: int in range(0 if with_empty else 1, 1 << types.size()):
		var subset := []
		for index: int in types.size():
			if mask & (1 << index):
				subset.append(types[index])
		list.append(subset)
	return list


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for item: Variant in a:
		if not b.has(item):
			return false
	return true


func _close(value: float, expected: float) -> bool:
	return absf(value - expected) <= maxf(absf(expected) * CHAIN_TOLERANCE, 0.5)
