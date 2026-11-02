extends RefCounted
## Turns the graph into plain values for HackingModel. It calls the game's value getters only:
## no connection, level or purchase is changed. Any chain is accepted; what cannot be told is left
## for the model to report as insufficient.

const HackingGraph := preload("hacking_graph.gd")
const HitLog := preload("hit_log.gd")

## Levels looked at beyond the highest unlocked one: enough to see what a scenario would open.
const LEVELS_AHEAD := 4
const CRITICAL_MULTIPLIER := "breach_critical_multiplier"


## error is empty when there is something to compare. intervals gives the attack interval seen by type.
## stealth_mask is the game's own bit for stealth damage: without it, stealth is one more unknown effect.
static func read(desktop: Variant, intervals: Dictionary, hit_log: Variant, attributes: Variant, data: Variant, stealth_mask: int = 0) -> Dictionary:
	if not is_instance_valid(desktop) or not is_instance_valid(desktop.get("windows")):
		return {"error": "no_desktop"}
	var graph := HackingGraph.snapshot(desktop)
	var chain := {
		"error": "", "targets": {}, "streams": {}, "sources": {},
		"current": {"payload": {}, "infection": {}, "vulnerability": false},
		"time_factor": 1.0, "interval_factor": 1.0, "power_factor": 1.0, "payload_factor": 1.0, "infection_factor": 1.0,
		"crit_multiplier": _attribute(attributes, CRITICAL_MULTIPLIER), "stealth_mask": stealth_mask,
	}
	var by_type := {}
	for entry: Dictionary in graph.windows:
		var window: Node = entry.node
		if not HackingGraph.is_target(window):
			continue
		var count: int = by_type.get(entry.type, 0) + 1
		by_type[entry.type] = count
		var key: String = entry.type if count == 1 else "%s#%d" % [entry.type, count]
		_read_target(chain, graph, key, entry.type, window, intervals, hit_log, attributes, data)
	if chain.targets.is_empty():
		return {"error": "no_target"}
	_shorten_labels(chain.targets)
	_read_spare_streams(chain, graph, data)
	for stream: Dictionary in chain.streams.values():
		_read_power(chain, graph, stream)
	return chain


## "Infiltrer Entreprises + Infiltrer Gouvernement" does not fit a table: a first word shared by all goes.
static func _shorten_labels(targets: Dictionary) -> void:
	if targets.size() < 2:
		return
	var first := ""
	for target: Dictionary in targets.values():
		var words: PackedStringArray = target.label.split(" ", false)
		if words.size() < 2 or (first != "" and words[0] != first):
			return
		first = words[0]
	for target: Dictionary in targets.values():
		target.label = target.label.trim_prefix(first).strip_edges()


static func _read_target(chain: Dictionary, graph: Dictionary, key: String, type: String, window: Node, intervals: Dictionary, hit_log: Variant, attributes: Variant, data: Variant) -> void:
	var max_level := _level_field(window, "max_level")
	var levels := {}
	for level: int in range(0, max_level + LEVELS_AHEAD + 1):
		var firewall: Variant = window.get_max_firewall(level)
		var breach: Variant = window.get_max_breach(level)
		var time: Variant = window.get_max_time(level)
		var reward: Variant = window.get_reward(level)
		var xp: Variant = window.get_experience_reward(level)
		if _all_numbers([firewall, breach, time, reward, xp]):
			levels[level] = {"firewall": float(firewall), "breach": float(breach), "time": float(time), "reward": float(reward), "xp": float(xp)}
	var payload_slot: Variant = window.get("breach_damage")
	var infection_slot: Variant = window.get("infection_damage")
	var vulnerability_slot: Variant = window.get("vulnerability")
	var key_for_hits := HackingGraph.chain_key(graph, window, attributes)
	var level_now := _level_field(window, "level")
	var announced_payload := _number(payload_slot, "production")
	var announced_infection := _number(infection_slot, "production")
	var vulnerability := _number(vulnerability_slot, "count")
	if hit_log != null and is_instance_valid(vulnerability_slot) and str(vulnerability_slot.get("input_id")) != "":
		vulnerability = maxf(vulnerability, hit_log.last_vulnerability(type))
	var power := HitLog.power_key(announced_payload, announced_infection)
	chain.targets[key] = {
		"type": type,
		"label": _label(data, "windows", type, type),
		"reward_name": _reward_name(window, data, type),
		"level": level_now,
		"max_level": max_level,
		"levels": levels,
		"interval": float(intervals.get(type, 0.0)),
		"vulnerability": vulnerability,
		"announced_payload": announced_payload,
		"announced_infection": announced_infection,
		"chain_key": key_for_hits,
		"real": hit_log.attack_stats(type, key_for_hits, level_now, power) if hit_log != null else {"attacks": 0, "successes": 0, "used": 0.0},
	}
	chain.current.payload[key] = _note_stream(chain, graph, key, payload_slot, "payload", data)
	chain.current.infection[key] = _note_stream(chain, graph, key, infection_slot, "infection", data)
	# A cable with nothing behind it brings nothing: there is no vulnerability to keep or to take off.
	if _note_stream(chain, graph, key, vulnerability_slot, "vulnerability", data) != "" and vulnerability > 0.0:
		chain.current.vulnerability = true
	if chain.current.payload[key] != "" and hit_log != null:
		var stream: Dictionary = chain.streams[chain.current.payload[key]]
		if stream.multipliers.is_empty():
			stream.multipliers = hit_log.multipliers(key_for_hits)
		stream.effects_seen |= hit_log.effects_seen(key_for_hits)
	if chain.current.infection[key] != "" and hit_log != null:
		var stream: Dictionary = chain.streams[chain.current.infection[key]]
		var infection_key := HackingGraph.chain_key(graph, window, attributes, HackingGraph.INFECTION_SLOT)
		stream.infection = hit_log.infection(infection_key)
		stream.effects_seen |= hit_log.effects_seen(infection_key)


## The output feeding this slot, seen as a stream that scenarios can send elsewhere.
static func _note_stream(chain: Dictionary, graph: Dictionary, target_key: String, slot: Variant, kind: String, data: Variant) -> String:
	if not is_instance_valid(slot):
		return ""
	var input: Variant = slot.get("input_id")
	if input == null or str(input) == "" or not graph.containers.has(str(input)):
		return ""
	var id := str(input)
	if not chain.streams.has(id):
		chain.streams[id] = _new_stream(graph.containers[id], kind, data)
	chain.streams[id].targets.append(target_key)
	chain.streams[id].variation |= int(_number(slot, "variation"))
	return id


## A powered node of the right kind connected to nothing could be sent to a target too.
static func _read_spare_streams(chain: Dictionary, graph: Dictionary, data: Variant) -> void:
	var kinds := {}
	for stream: Dictionary in chain.streams.values():
		if stream.kind != "vulnerability":
			kinds[stream.resource] = stream.kind
	for slot: Dictionary in graph.containers.values():
		if kinds.has(slot.resource) and slot.outputs_id.is_empty() and slot.input_id == "" and slot.production > 0.0 and not chain.streams.has(slot.id):
			chain.streams[slot.id] = _new_stream(slot, kinds[slot.resource], data)


static func _new_stream(slot: Dictionary, kind: String, data: Variant) -> Dictionary:
	return {
		"id": slot.id, "kind": kind, "resource": slot.resource, "label": _label(data, "windows", slot.window_type, slot.window_type),
		"production": slot.production, "outputs": slot.outputs_id.size(), "targets": [],
		"multipliers": PackedFloat32Array(), "source": "", "window_type": slot.window_type, "variation": slot.variation, "effects_seen": 0,
	}


static func _read_power(chain: Dictionary, graph: Dictionary, stream: Dictionary) -> void:
	var feed: Dictionary = HackingGraph.upstream(graph, stream.id).feed
	if feed.is_empty() or not graph.containers.has(feed.input_id):
		return
	var source: Dictionary = graph.containers[feed.input_id]
	stream.source = source.id
	chain.sources[source.id] = {"outputs": source.outputs_id.size()}


static func _reward_name(window: Node, data: Variant, fallback: String) -> String:
	var result: Variant = window.get("result")
	if is_instance_valid(result):
		var resource: Variant = result.get("resource")
		if resource != null:
			return _label(data, "resources", str(resource), fallback)
	return fallback


static func _label(data: Variant, table: String, key: String, fallback: String) -> String:
	if not is_instance_valid(data):
		return fallback
	var entries: Variant = data.get(table)
	if entries is Dictionary and entries.get(key) is Dictionary and entries[key].has("name"):
		return data.tr(str(entries[key].name))
	return fallback


static func _attribute(attributes: Variant, name: String) -> float:
	var table: Variant = attributes.get("attributes") if is_instance_valid(attributes) else null
	if table is Dictionary and table.get(name) is Object:
		var value: Variant = table[name].get("value")
		return float(value) if value is float or value is int else 0.0
	return 0.0


static func _level_field(window: Node, field: String) -> int:
	var data: Variant = window.get("data")
	return int(data.get(field, 0)) if data is Dictionary else 0


static func _number(object: Variant, property: String) -> float:
	if not is_instance_valid(object):
		return 0.0
	var value: Variant = object.get(property)
	return float(value) if value is float or value is int else 0.0


static func _all_numbers(values: Array) -> bool:
	for value: Variant in values:
		if not (value is float or value is int):
			return false
	return true
