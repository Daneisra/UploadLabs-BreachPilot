extends RefCounted
## Which purchases touch hacking, and what each one would change. Reads the game's own tables: nothing
## is bought, and a new purchase appears by itself. Effects are triples of an added value, an added
## multiplier and a factor. A purchase whose whole effect cannot be followed is listed without a figure.

const COST_NAMES := {
	"hack_points": ["point de piratage", "points de piratage"],
	"optimization": ["point d'optimisation", "points d'optimisation"],
	"token": ["jeton", "jetons"],
}
## How the comparison follows an effect, by attribute, and how to name a loss on it.
const FOLLOWED := {
	"breach_damage_multiplier": "Dégâts Payload",
	"infection_damage_multiplier": "Dégâts d'infection",
	"breach_speed_multiplier": "Vitesse d'intrusion",
	"breach_time_multiplier": "Temps d'attaque",
	"breach_critical_chance": "Chance de critique",
	"breach_critical_multiplier": "Multiplicateur de critique",
	"hack_specialization_multiplier": "Puissance de hack",
}
## An attribute with one of these names concerns hacking, even outside the game's hacking category.
const HACKING_ATTRIBUTE := "(?i)^(breach|hack|infection|charged|government|corps)"
const HACKING_CATEGORY := "hacking"
## A hit this close to a critical one counts as critical, as hits are whole numbers.
const CRITICAL_TOLERANCE := 0.93


## Those at their limit or not unlocked are left out. followed tells whether a figure can be given.
static func read(root: Node) -> Array[Dictionary]:
	var data: Node = root.get_node_or_null("Data")
	var globals: Node = root.get_node_or_null("Globals")
	var attributes: Node = root.get_node_or_null("Attributes")
	var list: Array[Dictionary] = []
	if not is_instance_valid(data) or not is_instance_valid(globals) or not is_instance_valid(attributes):
		return list
	for section: String in ["upgrades", "perks"]:
		var entries: Variant = data.get(section)
		var levels: Variant = globals.get(section)
		if not entries is Dictionary or not levels is Dictionary:
			continue
		for key: String in entries:
			var entry: Variant = entries[key]
			if entry is Dictionary and _concerns_hacking(entry) and _available(entry, levels.get(key, 0), globals):
				list.append(_item(key, entry, levels.get(key, 0), data, globals, attributes))
	return list


static func cost_text(cost: float, resource: String) -> String:
	var names: Array = COST_NAMES.get(resource, [resource, resource])
	return "%d %s" % [roundi(cost), names[0] if roundi(cost) <= 1 else names[1]]


## A copy of the chain with this purchase made.
static func apply(chain: Dictionary, changes: Dictionary) -> Dictionary:
	var changed := chain.duplicate()
	changed.payload_factor *= _ratio(changes, "breach_damage_multiplier")
	changed.infection_factor *= _ratio(changes, "infection_damage_multiplier")
	changed.interval_factor *= _ratio(changes, "breach_speed_multiplier")
	changed.time_factor *= _ratio(changes, "breach_time_multiplier")
	changed.power_factor *= _ratio(changes, "hack_specialization_multiplier")
	if changes.has("breach_critical_chance") or changes.has("breach_critical_multiplier"):
		changed.streams = {}
		for id: String in chain.streams:
			var stream: Dictionary = chain.streams[id].duplicate()
			if stream.kind == "payload":
				stream.multipliers = _with_critical_changes(stream.multipliers, chain.crit_multiplier, changes)
			changed.streams[id] = stream
	return changed


## Can the critical hits be told apart in these measures? Without them, no figure for such a purchase.
static func can_follow_critical(multipliers: PackedFloat32Array, critical_multiplier: float) -> bool:
	return critical_multiplier > 0.0 and _critical_count(multipliers, critical_multiplier) > 0


## What the game says a purchase costs, even when the end result is a gain: -40 % payload stays a drawback.
static func downsides(changes: Dictionary) -> PackedStringArray:
	var list := PackedStringArray()
	for name: String in changes:
		var label: String = FOLLOWED.get(name, "")
		if label != "" and changes[name].ratio < 1.0:
			list.append("%s %+d %%" % [label, roundi((changes[name].ratio - 1.0) * 100.0)])
	return list


static func _item(key: String, entry: Dictionary, level: Variant, data: Node, globals: Node, attributes: Node) -> Dictionary:
	var cost: float = _as_number(entry.get("cost", 0.0))
	var resource: String = str(entry.get("attribute_cost", ""))
	var held := -1.0
	if resource == "":
		# Paid in a currency, in a scientific form: 5 and 2 make 500.
		resource = str(entry.get("currency", ""))
		cost *= pow(10.0, _as_number(entry.get("cost_e", 0.0))) * pow(_as_number(entry.get("cost_inc", 1.0)), level)
		var currencies: Variant = globals.get("currencies")
		var balance: Variant = currencies.get(resource) if currencies is Dictionary else null
		held = float(balance) if balance is float or balance is int else -1.0
	else:
		held = _value(attributes, resource)
	var changes := _changes(entry, attributes)
	return {
		"name": data.tr(str(entry.get("name", key))), "cost": cost, "resource": resource, "held": held, "affordable": held >= cost,
		"cost_text": cost_text(cost, resource), "changes": changes, "followed": _is_followed(entry, changes),
	}


static func _concerns_hacking(entry: Dictionary) -> bool:
	var effects: Variant = entry.get("attributes")
	if not effects is Dictionary or effects.is_empty():
		return false
	if entry.get("category", "") == HACKING_CATEGORY:
		return true
	var regex := RegEx.create_from_string(HACKING_ATTRIBUTE)
	return effects.keys().any(func(name: Variant) -> bool: return regex.search(str(name)) != null)


static func _is_followed(entry: Dictionary, changes: Dictionary) -> bool:
	return entry.attributes.size() == changes.size() and changes.keys().all(func(name: String) -> bool: return FOLLOWED.has(name))


static func _available(entry: Dictionary, level: Variant, globals: Node) -> bool:
	var limit: float = _as_number(entry.get("limit", 0.0))
	if limit > 0.0 and level >= limit:
		return false
	var unlocks: Variant = globals.get("unlocks")
	var requirements: Variant = entry.get("requirement", [])
	if unlocks is Dictionary and requirements is Array:
		for requirement: Variant in requirements:
			if not unlocks.get(requirement, true):
				return false
	return true


## Ratios of new to old values, by attribute. An attribute that cannot be read gives no ratio.
static func _changes(entry: Dictionary, attributes: Node) -> Dictionary:
	var changes := {}
	var table: Variant = attributes.get("attributes")
	if not table is Dictionary:
		return changes
	for name: String in entry.attributes:
		var attribute: Variant = table.get(name)
		var effect: Variant = entry.attributes[name]
		if not attribute is Object or not effect is Array or effect.size() < 3:
			continue
		var start: Variant = attribute.get("default")
		var added: Variant = attribute.get("added")
		var multiplier: Variant = attribute.get("multiplier")
		if not _all_numbers([start, added, multiplier, effect[0], effect[1], effect[2]]):
			continue
		var old: float = (start + added) * multiplier
		var new: float = (start + added + effect[0]) * (multiplier + effect[1])
		if effect[2] > 0.0:
			new *= effect[2]
		changes[name] = {"ratio": new / old if old != 0.0 else 1.0, "added": new - old}
	return changes


static func _ratio(changes: Dictionary, name: String) -> float:
	return changes[name].ratio if changes.has(name) else 1.0


static func _value(attributes: Node, name: String) -> float:
	var table: Variant = attributes.get("attributes")
	if table is Dictionary and table.get(name) is Object:
		return _as_number(table[name].get("value"), -1.0)
	return -1.0


static func _as_number(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if value is float or value is int else fallback


static func _all_numbers(values: Array) -> bool:
	return values.all(func(value: Variant) -> bool: return value is float or value is int)


static func _critical_count(multipliers: PackedFloat32Array, critical_multiplier: float) -> int:
	if multipliers.is_empty():
		return 0
	var base: float = Array(multipliers).min()
	var count := 0
	for value: float in multipliers:
		if value >= base * (1.0 + critical_multiplier) * CRITICAL_TOLERANCE:
			count += 1
	return count


## Critical hits grow with their multiplier, and more of them appear with more chance.
static func _with_critical_changes(multipliers: PackedFloat32Array, critical_multiplier: float, changes: Dictionary) -> PackedFloat32Array:
	if not can_follow_critical(multipliers, critical_multiplier):
		return multipliers
	var base: float = Array(multipliers).min()
	var threshold: float = base * (1.0 + critical_multiplier) * CRITICAL_TOLERANCE
	var new_multiplier: float = critical_multiplier * _ratio(changes, "breach_critical_multiplier")
	var result := PackedFloat32Array()
	var criticals := 0
	for value: float in multipliers:
		if value >= threshold:
			criticals += 1
			result.append(value * (1.0 + new_multiplier) / (1.0 + critical_multiplier))
		else:
			result.append(value)
	if changes.has("breach_critical_chance"):
		var total: int = multipliers.size()
		var wanted: float = float(criticals) / total + changes.breach_critical_chance.added
		var extra: int = roundi((wanted * total - criticals) / maxf(1.0 - wanted, 0.01))
		for _i: int in maxi(extra, 0):
			result.append(base * (1.0 + new_multiplier))
	return result
