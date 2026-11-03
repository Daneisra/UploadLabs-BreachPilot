extends RefCounted
## What attacks really did, by chain. Hits are kept relative to the damage announced, without
## vulnerability: whatever a node on the way does to them, known or not, is in the measure, and it
## stays valid when the power changes. A changed chain starts a new measure; the old ones stay, in
## case the player comes back to that chain and for diagnosis.

## A payload and an infection measure for each chain.
const MAX_CHAINS := 32
const MAX_HITS := 400
## Past this, gains spread too much to come from a fixed amount: they follow the hits.
const FOLLOWS_HITS_SPREAD := 0.15

var _hits := {}
var _attacks := {}
var _order: Array[String] = []
var _vulnerability := {}
var _infection := {}
var _effects := {}


## event is a complete attack from the classifier.
func add(type: String, chain_key: String, event: Dictionary, infection_key: String = "") -> void:
	if not event.get("complete", false):
		return
	_touch(chain_key)
	_effects[chain_key] = effects_seen(chain_key) | int(event.get("breach_variation", 0))
	if infection_key != "":
		_add_infection(infection_key, event)
	_vulnerability[type] = event.get("vulnerability", 0.0)
	var power := power_key(event.get("damage_rate", 0.0), event.get("infection_rate", 0.0))
	var stats: Dictionary = _attacks[chain_key].get_or_add("%s|%d|%s" % [type, event.level, power], {"attacks": 0, "successes": 0, "used": 0.0})
	stats.attacks += 1
	if event.event == "success":
		stats.successes += 1
		stats.used += event.get("used", 0.0)
	# The game announces a rate: what one shot brings is that rate over the time between two shots.
	var announced: float = event.get("damage_rate", 0.0) * event.get("interval", 0.0)
	if announced <= 0.0:
		return
	var bonus: float = 1.0 + event.get("vulnerability", 0.0)
	var hits: PackedFloat32Array = _hits[chain_key]
	for hit: float in event.get("hits", PackedFloat32Array()):
		hits.append(hit / bonus / announced)
	if hits.size() > MAX_HITS:
		hits = hits.slice(hits.size() - MAX_HITS)
	_hits[chain_key] = hits


func multipliers(chain_key: String) -> PackedFloat32Array:
	return _hits.get(chain_key, PackedFloat32Array())


## The effects the game had on this chain's flow during attacks measured: they are in the measures.
func effects_seen(key: String) -> int:
	return _effects.get(key, 0)


## How the infection behaves. pulses: gains measured. growth: per second, by itself. level: what a shot adds, relative
## to the rate announced. follow: when gains follow the hits, the gain for a hit at 1 of the payload announced.
func infection(key: String) -> Dictionary:
	var measure: Dictionary = _infection.get(key, {})
	if measure.is_empty() or measure.gains.is_empty():
		return {"pulses": 0, "growth": 0.0, "level": 1.0, "follow": 0.0}
	var growth := Array(measure.growth)
	growth.sort()
	var level := _mean(measure.gains)
	var deviation := 0.0
	for gain: float in measure.gains:
		deviation += (gain - level) * (gain - level)
	deviation = sqrt(deviation / measure.gains.size())
	var hits := _mean(measure.hits)
	var follows: bool = hits > 0.0 and level > 0.0 and deviation / level > FOLLOWS_HITS_SPREAD
	return {"pulses": measure.gains.size(), "growth": growth[growth.size() / 2], "level": level, "follow": level / hits if follows else 0.0}


func _add_infection(key: String, event: Dictionary) -> void:
	var announced: float = event.get("infection_rate", 0.0) * event.get("interval", 0.0)
	if announced <= 0.0 or not event.has("infection_gains"):
		return
	_touch(key)
	_effects[key] = effects_seen(key) | int(event.get("infection_variation", 0))
	var measure: Dictionary = _infection.get_or_add(key, {"gains": PackedFloat32Array(), "hits": PackedFloat32Array(), "growth": PackedFloat32Array()})
	for gain: float in event.infection_gains:
		measure.gains.append(gain / announced)
	var shot: float = event.get("damage_rate", 0.0) * event.get("interval", 0.0) * (1.0 + event.get("vulnerability", 0.0))
	if shot > 0.0:
		for hit: float in event.get("hits", PackedFloat32Array()):
			measure.hits.append(hit / shot)
	measure.growth.append(event.infection_growth)
	for name: String in measure:
		if measure[name].size() > MAX_HITS:
			measure[name] = measure[name].slice(measure[name].size() - MAX_HITS)


static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / values.size()


## Unlike hits, attack results only compare at the same power.
static func power_key(damage: float, infection: float) -> String:
	return "%.2f|%.2f" % [damage, infection]


## attacks, successes and total time used, at this level with this chain and power.
func attack_stats(type: String, chain_key: String, level: int, power: String) -> Dictionary:
	return _attacks.get(chain_key, {}).get("%s|%d|%s" % [type, level, power], {"attacks": 0, "successes": 0, "used": 0.0})


## What the last attack had. The slot itself falls back to nothing for an instant between two attacks.
func last_vulnerability(type: String) -> float:
	return _vulnerability.get(type, 0.0)


func _touch(chain_key: String) -> void:
	if not _hits.has(chain_key):
		_hits[chain_key] = PackedFloat32Array()
		_attacks[chain_key] = {}
	_order.erase(chain_key)
	_order.append(chain_key)
	while _order.size() > MAX_CHAINS:
		var oldest: String = _order.pop_front()
		_hits.erase(oldest)
		_attacks.erase(oldest)
		_infection.erase(oldest)
		_effects.erase(oldest)
