extends RefCounted
## What attacks really did, by chain. Hits are kept relative to the damage announced, without
## vulnerability: whatever a node on the way does to them, known or not, is in the measure, and it
## stays valid when the power changes. A changed chain starts a new measure; the old ones stay, in
## case the player comes back to that chain and for diagnosis.

const MAX_CHAINS := 16
const MAX_HITS := 400

var _hits := {}
var _attacks := {}
var _order: Array[String] = []
var _vulnerability := {}


## event is a complete attack from the classifier.
func add(type: String, chain_key: String, event: Dictionary) -> void:
	if not event.get("complete", false):
		return
	_touch(chain_key)
	_vulnerability[type] = event.get("vulnerability", 0.0)
	var power := power_key(event.get("damage_rate", 0.0), event.get("infection_rate", 0.0))
	var stats: Dictionary = _attacks[chain_key].get_or_add("%s|%d|%s" % [type, event.level, power], {"attacks": 0, "successes": 0, "used": 0.0})
	stats.attacks += 1
	if event.event == "success":
		stats.successes += 1
		stats.used += event.get("used", 0.0)
	var announced: float = event.get("damage_rate", 0.0)
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
