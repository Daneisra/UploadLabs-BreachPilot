extends RefCounted
## Reads any chain as a graph of connected slots, by what the game exposes and never by node names.
## Whatever is missing or unusual is skipped: nothing here may fail on a node it has never seen.

## What makes a window an attack target. The level getters are checked as well before use.
const TARGET_PROPERTIES: Array[String] = ["breach_damage", "infection_damage", "vulnerability", "max_firewall", "max_breach", "data"]
const POWER_RESOURCE := "hack_power"
## Names of the attributes a chain's measures depend on, as they change the hits without moving the links.
const HIT_ATTRIBUTE := "(?i)critical|charged"
## A chain longer than this is not a real one.
const MAX_WALK := 256


## containers: slots by id, each with the node holding it. windows: every node with its slots.
static func snapshot(desktop: Variant) -> Dictionary:
	var graph := {"containers": {}, "windows": []}
	if not is_instance_valid(desktop):
		return graph
	var windows: Variant = desktop.get("windows")
	if not is_instance_valid(windows):
		return graph
	for window: Node in windows.get_children():
		var slots: Array[Dictionary] = []
		var containers: Variant = window.get("containers")
		if containers is Array:
			for container: Variant in containers:
				var slot := _read_slot(container, window)
				if not slot.is_empty():
					slots.append(slot)
					graph.containers[slot.id] = slot
		graph.windows.append({"node": window, "type": str(window.get("window")), "slots": slots})
	return graph


static func is_target(window: Node) -> bool:
	for property: String in TARGET_PROPERTIES:
		if not property in window:
			return false
	# A getter that would not take a level cannot be called safely.
	var wanted := {"get_max_firewall": false, "get_max_breach": false, "get_max_time": false, "get_reward": false, "get_experience_reward": false}
	for method: Dictionary in window.get_method_list():
		if wanted.has(method.name) and method.args.size() == 1:
			wanted[method.name] = true
	return not wanted.values().has(false)


## Everything upstream of a slot: the node types in order, and where the power comes in.
## feed is the power input when there is exactly one on the way, the only case where unplugging
## a node surely frees its power.
static func upstream(graph: Dictionary, output_id: String) -> Dictionary:
	var seen := {}
	var path := PackedStringArray()
	var feeds: Array[Dictionary] = []
	var pending: Array[String] = [output_id]
	while not pending.is_empty() and seen.size() < MAX_WALK:
		var id: String = pending.pop_back()
		if seen.has(id) or not graph.containers.has(id):
			continue
		seen[id] = true
		var slot: Dictionary = graph.containers[id]
		path.append("%s:%s" % [slot.window_type, id])
		for sibling: Dictionary in _slots_of(graph, slot.window):
			if sibling.input_id == "" or seen.has(sibling.id):
				continue
			seen[sibling.id] = true
			if sibling.resource == POWER_RESOURCE:
				feeds.append(sibling)
			else:
				pending.append(sibling.input_id)
	return {"path": path, "feed": feeds[0] if feeds.size() == 1 else {}}


## What identifies the measures of a target's hits: the chain feeding it, and what changes hits.
static func chain_key(graph: Dictionary, window: Node, attributes: Variant) -> String:
	var slot: Variant = window.get("breach_damage")
	if not is_instance_valid(slot):
		return "none"
	var input: String = str(slot.get("input_id"))
	var parts: PackedStringArray = upstream(graph, input).path
	parts.sort()
	var table: Variant = attributes.get("attributes") if is_instance_valid(attributes) else null
	if table is Dictionary:
		var regex := RegEx.create_from_string(HIT_ATTRIBUTE)
		var names: Array = table.keys()
		names.sort()
		for name: Variant in names:
			if regex.search(str(name)) != null and table[name] is Object:
				parts.append("%s=%s" % [name, table[name].get("value")])
	return ",".join(parts)


static func _slots_of(graph: Dictionary, window: Node) -> Array[Dictionary]:
	for entry: Dictionary in graph.windows:
		if entry.node == window:
			return entry.slots
	return []


static func _read_slot(container: Variant, window: Node) -> Dictionary:
	if not is_instance_valid(container):
		return {}
	var id: Variant = container.get("id")
	if id == null or str(id) == "":
		return {}
	var outputs: Variant = container.get("outputs_id")
	var production: Variant = container.get("production")
	var count: Variant = container.get("count")
	return {
		"id": str(id),
		"window": window,
		"window_type": str(window.get("window")),
		"resource": str(container.get("resource")),
		"input_id": str(container.get("input_id")) if container.get("input_id") != null else "",
		"outputs_id": outputs if outputs is Array else [],
		"production": float(production) if production is float or production is int else 0.0,
		"count": float(count) if count is float or count is int else 0.0,
	}
