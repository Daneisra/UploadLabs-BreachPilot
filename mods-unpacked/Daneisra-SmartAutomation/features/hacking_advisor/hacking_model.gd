extends RefCounted
## Compares ways of connecting the chain. Pure calculations on the values read by HackingChain:
## nothing here touches the game. Attacks are drawn from the hits really seen on the chain, so a node
## never seen before counts as soon as it has acted. What cannot be told stays insufficient, never a figure.

const LevelChoice := preload("../threat_manager/level_choice.gd")

const NORMAL_TICK := 0.05
const SAMPLES := 100
const EARLY_SAMPLES := 30
## From this chance on, the regulation holds a level long enough for it to count. Two failures in a row lower it.
const MIN_HOLD := 0.8
## An elite level can fail between two that work, but not two levels in a row.
const FAILED_IN_ROW_STOP := 2
const SEED := 20261101
## How late the infection starts, in intervals. The lag is fitted on the logs: it gives 50 % for the 48 and 47 %
## measured over 40 attacks at the limit, and 4.59 s for the 4.59 s measured over 225 attacks. The logs show
## a later start, 0.35, in about one attack in seven.
const INFECTION_LAG := 0.25
const LATE_INFECTION := 0.35
const LATE_INFECTION_CHANCE := 0.15
## Hits needed before trusting the measure: about 8 attacks, enough to meet a 10 % critical hit a few times.
const MIN_HITS := 30
## Gains needed before trusting how the infection behaves: about as many attacks as for the hits.
const MIN_PULSES := 20
const MAX_SCENARIOS := 64
## Rounds of the search through a chain too large to try whole: each one keeps the best change and tries
## every change from there. Most chains settle in two or three.
const MAX_SEARCH_ROUNDS := 4
## From this many attacks, what really happened can refute the calculation.
const MIN_ATTACKS_TO_CHECK := 10
const CHANCE_TOLERANCE := 0.35
const USED_TOLERANCE := 1.0
const REASON_HITS := "hits"
const REASON_INTERVAL := "interval"
const REASON_UNMEASURED := "unmeasured"

var _chain: Dictionary
var _results := {}


func _init(chain: Dictionary) -> void:
	_chain = chain


func current_scenario() -> Dictionary:
	return _chain.current


## Every way of sending the streams to the targets. Too many of them: only one change at a time, from which
## the search goes on with neighbors().
func scenarios() -> Array[Dictionary]:
	var keys: Array = _chain.targets.keys()
	var payload := _stream_choices("payload")
	var infection := _stream_choices("infection")
	var vulnerabilities: Array = [true, false] if _chain.current.vulnerability else [false]
	if searches():
		return neighbors(_chain.current)
	var list: Array[Dictionary] = []
	for payload_set: Dictionary in _assignments(keys, payload):
		if payload_set.values().all(func(id: String) -> bool: return id == ""):
			continue
		for infection_set: Dictionary in _assignments(keys, infection):
			for vulnerability: bool in vulnerabilities:
				list.append({"payload": payload_set, "infection": infection_set, "vulnerability": vulnerability})
	return list


## Whether the chain is too large to try every way, so that the best one is searched change by change.
func searches() -> bool:
	var keys: Array = _chain.targets.keys()
	var vulnerabilities := 2.0 if _chain.current.vulnerability else 1.0
	return pow(_stream_choices("payload").size() + 1.0, keys.size()) * pow(_stream_choices("infection").size() + 1.0, keys.size()) * vulnerabilities > MAX_SCENARIOS


## base, then every chain one cable away from it. A chain sending no payload anywhere is left out.
func neighbors(base: Dictionary) -> Array[Dictionary]:
	var keys: Array = _chain.targets.keys()
	var list: Array[Dictionary] = [base]
	for kind: String in ["payload", "infection"]:
		var choices := _stream_choices(kind)
		for key: String in keys:
			for choice: String in [""] + choices:
				if choice == base[kind][key]:
					continue
				var changed: Dictionary = base.duplicate(true)
				changed[kind][key] = choice
				if kind == "payload" and changed.payload.values().all(func(id: String) -> bool: return id == ""):
					continue
				list.append(changed)
	if _chain.current.vulnerability:
		var toggled: Dictionary = base.duplicate(true)
		toggled.vulnerability = not base.vulnerability
		list.append(toggled)
	return list


func is_current(scenario: Dictionary) -> bool:
	return scenario == _chain.current


func evaluate(scenario: Dictionary) -> Dictionary:
	var row := {"scenario": scenario, "current": is_current(scenario), "targets": {}, "xp_rate": 0.0, "insufficient": PackedStringArray()}
	for key: String in _chain.targets:
		var best := _best_level(key, scenario)
		row.targets[key] = best
		row.xp_rate += best.xp_rate
		if best.insufficient != "" and not row.insufficient.has(best.insufficient):
			row.insufficient.append(best.insufficient)
	return row


## Targets whose real attacks refute the calculation, at the level they really hold.
func contradictions(row: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for key: String in _chain.targets:
		var target: Dictionary = _chain.targets[key]
		var real: Dictionary = target.real
		if real.attacks < MIN_ATTACKS_TO_CHECK or not target.levels.has(target.level):
			continue
		var scales := _scales(key, row.scenario)
		var interval := _interval(key)
		if (scales.hit <= 0.0 and scales.stack <= 0.0) or interval <= 0.0 or not _measured(key, row.scenario) or _is_unmeasured(key, row.scenario):
			continue
		var outcome := attack_outcome(target.levels[target.level], scales.hit * _shot_time(key), scales.stack * _shot_time(key), scales.bonus, _multipliers_for(key, row.scenario), interval, scales.hit_stealth, scales.stack_stealth, _infection_of(row.scenario.infection[key]))
		var real_chance: float = float(real.successes) / real.attacks
		var real_used: float = real.used / real.successes if real.successes > 0 else -1.0
		var used_off: bool = real_used >= 0.0 and outcome.used >= 0.0 and absf(real_used - outcome.used) > USED_TOLERANCE
		if absf(real_chance - outcome.chance) > CHANCE_TOLERANCE or used_off:
			found.append({"key": key, "label": target.label, "level": target.level, "expected": outcome.chance, "real": real_chance, "attacks": real.attacks, "expected_used": outcome.used, "real_used": real_used, "duration": used_off})
	return found


func _stream_choices(kind: String) -> Array[String]:
	var ids: Array[String] = []
	for stream: Dictionary in _chain.streams.values():
		if stream.kind == kind:
			ids.append(stream.id)
	return ids


func _assignments(keys: Array, choices: Array[String]) -> Array[Dictionary]:
	var list: Array[Dictionary] = [{}]
	for key: String in keys:
		var grown: Array[Dictionary] = []
		for partial: Dictionary in list:
			for choice: String in [""] + choices:
				var next := partial.duplicate()
				next[key] = choice
				grown.append(next)
		list = grown
	return list


## A stream with no target left is taken off its source, whose power goes to the others.
func _power_ratio(stream: Dictionary, scenario: Dictionary) -> float:
	if stream.source == "" or not _chain.sources.has(stream.source):
		return 1.0
	var outputs: int = _chain.sources[stream.source].outputs
	var removed := 0
	for other: Dictionary in _chain.streams.values():
		if other.source == stream.source and _is_unplugged(other, scenario):
			removed += 1
	if removed >= outputs:
		return 1.0
	return float(outputs) / (outputs - removed)


## A stream feeding nothing today takes its share of power today: it only counts once it is sent somewhere.
func _is_unplugged(stream: Dictionary, scenario: Dictionary) -> bool:
	if stream.targets.is_empty() or stream.outputs > stream.targets.size():
		return false
	if stream.kind == "vulnerability":
		return not scenario.vulnerability
	return not scenario[stream.kind].values().has(stream.id)


## What a stream gives one target: what it makes now, by the power it would have and the outputs it would feed.
func _share(stream_id: String, kind: String, scenario: Dictionary) -> float:
	if stream_id == "" or not _chain.streams.has(stream_id):
		return 0.0
	var stream: Dictionary = _chain.streams[stream_id]
	var fed: int = scenario[kind].values().count(stream_id)
	var outputs: int = stream.outputs - stream.targets.size() + fed
	return stream.production * _power_ratio(stream, scenario) * _chain.power_factor / maxi(outputs, 1)


## hit and stack as rates, before vulnerability, and what vulnerability adds.
func _scales(key: String, scenario: Dictionary) -> Dictionary:
	# Infection that follows the hits grows with what the payload gains as well.
	var follows: bool = _infection_of(scenario.infection[key]).get("follow", 0.0) > 0.0
	return {
		"hit": _share(scenario.payload[key], "payload", scenario) * _chain.payload_factor,
		"stack": _share(scenario.infection[key], "infection", scenario) * _chain.infection_factor * (_chain.payload_factor if follows else 1.0),
		"bonus": 1.0 + (_chain.targets[key].vulnerability if scenario.vulnerability else 0.0),
		"hit_stealth": _is_stealth(scenario.payload[key]),
		"stack_stealth": _is_stealth(scenario.infection[key]),
	}


func _is_stealth(stream_id: String) -> bool:
	return _chain.streams.has(stream_id) and (_chain.streams[stream_id].get("variation", 0) & _chain.get("stealth_mask", 0)) != 0


func _infection_of(stream_id: String) -> Dictionary:
	return _chain.streams.get(stream_id, {}).get("infection", {})


## An effect is known once attacks have run with it: what it does is in what they measured. Before that, or for
## infection that follows hits with no hits to follow, there is nothing to count on.
func _is_unmeasured(key: String, scenario: Dictionary) -> bool:
	var stealth: int = _chain.get("stealth_mask", 0)
	for stream_id: String in [scenario.payload[key], scenario.infection[key]]:
		if _chain.streams.has(stream_id):
			var stream: Dictionary = _chain.streams[stream_id]
			if (stream.get("variation", 0) & ~stealth & ~int(stream.get("effects_seen", 0))) != 0:
				return true
	return scenario.payload[key] == "" and _infection_of(scenario.infection[key]).get("follow", 0.0) > 0.0


func _multipliers_for(key: String, scenario: Dictionary) -> PackedFloat32Array:
	var stream_id: String = scenario.payload[key]
	return _chain.streams[stream_id].multipliers if stream_id != "" else PackedFloat32Array()


func _interval(key: String) -> float:
	return _shot_time(key) / _chain.interval_factor


## The time between two shots today. More speed makes shots come sooner without changing what each one brings.
func _shot_time(key: String) -> float:
	var interval: float = _chain.targets[key].interval
	if interval <= 0.0:
		for target: Dictionary in _chain.targets.values():
			interval = maxf(interval, target.interval)
	return interval


func _measured(key: String, scenario: Dictionary) -> bool:
	var infection := _infection_of(scenario.infection[key])
	if not infection.is_empty() and infection.pulses < MIN_PULSES:
		return false
	return scenario.payload[key] == "" or _multipliers_for(key, scenario).size() >= MIN_HITS


## The level likely to hold that brings the most for the objective, as the regulation picks it. Above the
## highest unlocked level, one only opens once the one before it works.
func _best_level(key: String, scenario: Dictionary) -> Dictionary:
	var scales := _scales(key, scenario)
	var memo := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [key, scales.hit, scales.stack, scales.bonus, scenario.payload[key], scales.hit_stealth, scales.stack_stealth, scenario.infection[key], _chain.get("objective", LevelChoice.BALANCED)]
	if _results.has(memo):
		return _results[memo]
	var target: Dictionary = _chain.targets[key]
	var best := {"level": -1, "chance": 0.0, "used": -1.0, "cycle": 0.0, "reward_rate": 0.0, "xp_rate": 0.0, "insufficient": ""}
	if _is_unmeasured(key, scenario):
		# An effect no attack has shown yet: no figure rather than a wrong one.
		best.insufficient = REASON_UNMEASURED
	elif scales.hit > 0.0 or scales.stack > 0.0:
		var interval := _interval(key)
		if interval <= 0.0:
			best.insufficient = REASON_INTERVAL
		elif not _measured(key, scenario):
			best.insufficient = REASON_HITS
		else:
			var shots := {"hit": scales.hit * _shot_time(key), "stack": scales.stack * _shot_time(key), "bonus": scales.bonus, "hit_stealth": scales.hit_stealth, "stack_stealth": scales.stack_stealth, "infection": _infection_of(scenario.infection[key])}
			_scan_levels(best, key, target, shots, _multipliers_for(key, scenario), interval)
	_results[memo] = best
	return best


func _scan_levels(best: Dictionary, key: String, target: Dictionary, scales: Dictionary, multipliers: PackedFloat32Array, interval: float) -> void:
	var levels: Array = target.levels.keys()
	levels.sort()
	var failed_in_row := 0
	var holding := {}
	var outcomes := {}
	for level: int in levels:
		var values: Dictionary = target.levels[level]
		var outcome := attack_outcome(values, scales.hit, scales.stack, scales.bonus, multipliers, interval, scales.hit_stealth, scales.stack_stealth, scales.infection)
		if outcome.chance >= MIN_HOLD:
			failed_in_row = 0
			holding[level] = {"chance": outcome.chance, "cycle": outcome.cycle, "reward": values.reward, "xp": values.xp}
			outcomes[level] = outcome
		else:
			failed_in_row += 1
			if level > target.max_level or failed_in_row >= FAILED_IN_ROW_STOP:
				break
	var chosen := LevelChoice.profitable(holding, _chain.get("objective", LevelChoice.BALANCED), key, MIN_HOLD, target.level)
	if chosen < 0:
		return
	var brought := LevelChoice.rates(holding[chosen])
	best.level = chosen
	best.chance = outcomes[chosen].chance
	best.used = outcomes[chosen].used
	best.cycle = outcomes[chosen].cycle
	best.reward_rate = brought.reward
	best.xp_rate = brought.xp


## chance of success, average duration of the attacks that succeed, and average time from one attack
## to the next. The same seed gives two scenarios the same luck, so that a small gap between them is
## not just noise.
func attack_outcome(values: Dictionary, hit: float, stack: float, bonus: float, multipliers: PackedFloat32Array, interval: float, hit_stealth: bool = false, stack_stealth: bool = false, infection: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var time: float = values.time * _chain.time_factor
	var successes := 0
	var total_used := 0.0
	var total_cycle := 0.0
	var samples := 0
	while samples < SAMPLES:
		samples += 1
		var used := _attack(rng, values.firewall, values.breach, time, hit, stack, bonus, multipliers, interval, hit_stealth, stack_stealth, infection)
		if used >= 0.0:
			successes += 1
			total_used += used
		total_cycle += _next_shot(used if used >= 0.0 else time, interval)
		if samples == EARLY_SAMPLES and successes == 0:
			break
	return {"chance": float(successes) / samples, "used": total_used / successes if successes > 0 else -1.0, "cycle": total_cycle / samples}


## The next attack starts on the next shot: over 8 long runs this is 0.15 s off on average, and it
## fits the gaps measured between attacks (3.95 s leaves 1 tick, 4.00 s leaves 20).
func _next_shot(time: float, interval: float) -> float:
	return (floorf(time / interval + 1e-9) + 1.0) * interval


## One attack, tick by tick, as BreachForecast.attack_time, with hits drawn from those really seen.
## Measured: vulnerability multiplies the hits (59.3 became 72.8 at 0.234). Assumed: its effect on infection.
## Measured over 808 attacks: stealth damage goes straight to the breach bar and leaves the firewall whole.
## infection is what HitLog measured: how the infection grows by itself and what each shot adds to it.
func _attack(rng: RandomNumberGenerator, firewall: float, breach: float, max_time: float, hit: float, stack_gain: float, bonus: float, multipliers: PackedFloat32Array, interval: float, hit_stealth: bool = false, stack_stealth: bool = false, infection: Dictionary = {}) -> float:
	var growth: float = exp(infection.get("growth", 0.0) * NORMAL_TICK)
	var follow: float = infection.get("follow", 0.0)
	var gain: float = stack_gain * infection.get("level", 1.0)
	var next_volley := 0.0
	var next_pulse: float = (LATE_INFECTION if rng.randf() < LATE_INFECTION_CHANCE else INFECTION_LAG) * interval
	if follow > 0.0:
		next_pulse = INF
	var stack := 0.0
	var time := 0.0
	var drawn: int = multipliers.size()
	while time < max_time:
		var volley := 0.0
		stack *= growth
		while time >= next_volley - 1e-9:
			if (hit > 0.0 or follow > 0.0) and drawn > 0:
				var multiplier: float = multipliers[rng.randi() % drawn]
				volley += hit * multiplier * bonus
				stack += stack_gain * follow * multiplier
			next_volley += interval
		while time >= next_pulse - 1e-9:
			if stack_gain > 0.0:
				stack += _whole(rng, gain)
			next_pulse += interval
		var over_time := stack * bonus * NORMAL_TICK
		if hit_stealth:
			breach -= volley
			volley = 0.0
		if stack_stealth:
			breach -= over_time
			over_time = 0.0
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
