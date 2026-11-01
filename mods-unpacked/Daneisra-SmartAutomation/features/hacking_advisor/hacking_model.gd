extends RefCounted
## Compares ways of connecting the hacking chain. Pure calculations on the values read by HackingChain:
## nothing here touches the game. Damage counts on normal hits, like the regulation: critical hits
## can only do better than what is shown.

const BreachForecast := preload("../threat_manager/breach_forecast.gd")

## Time from the end of an attack to the start of the next, as measured on most attacks.
const ATTACK_GAP := 1.0
const NORMAL_TICK := 0.05
const EPSILON := 1e-6
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


## Above the highest unlocked level, a level only opens once the one before it works.
func _best_level(type: String, hit: float, stack: float) -> Dictionary:
	var key := "%s|%s|%s" % [type, hit, stack]
	if _results.has(key):
		return _results[key]
	var target: Dictionary = _chain.targets[type]
	var best := {"level": -1, "used": -1.0, "reward_rate": 0.0, "xp_rate": 0.0, "hit": hit, "stack": stack, "invalid": false}
	if hit > 0.0 or stack > 0.0:
		var profile := {
			"damage_rate": hit / _chain.interval,
			"infection_rate": stack / _chain.interval,
			"vulnerability": target.vulnerability,
			"breach_variation": target.breach_variation,
			"infection_variation": target.infection_variation,
			"interval": _chain.interval,
			"tick_speed": NORMAL_TICK,
			"infection_offset": -1.0,
			"hit_spread": _chain.has_crit,
		}
		var levels: Array = target.levels.keys()
		levels.sort()
		for level: int in levels:
			var values: Dictionary = target.levels[level]
			var forecast := BreachForecast.forecast(profile, values, _chain.margin)
			if forecast.status == "invalid":
				best.invalid = true
				break
			if _passes(forecast):
				var used: float = forecast.used_max if forecast.used_max >= 0.0 else forecast.used_nominal
				var cycle: float = used + ATTACK_GAP
				best.level = level
				best.used = used
				best.reward_rate = values.reward / cycle * 60.0
				best.xp_rate = values.xp / cycle * 60.0
			elif level > target.max_level:
				break
	_results[key] = best
	return best


func _passes(forecast: Dictionary) -> bool:
	if forecast.status != "reliable" or forecast.outcome != "pass" and forecast.outcome != "mixed":
		return false
	return forecast.p_success >= _chain.required_success - EPSILON


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
