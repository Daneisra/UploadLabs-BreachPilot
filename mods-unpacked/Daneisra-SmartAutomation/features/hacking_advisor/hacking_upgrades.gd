extends RefCounted
## Which purchases touch the chain, and what each one would change. Reads the game's own tables:
## nothing is bought. The effects are triples of an added value, an added multiplier and a factor.

const UPGRADES := {
	"hack_breach_damage": "Dégâts Payload",
	"hack_breach_speed": "Vitesse d'intrusion",
	"hack_breach_critical_chance": "Chance de critique",
	"hack_breach_critical_multiplier": "Multiplicateur de critique",
	"hack_infection_damage": "Dégâts d'infection",
	"hack_infection_specialist": "Spécialiste d'infection",
	"hack_sneak_attack": "Attaque furtive",
	"optimization_critical_payload": "Payload critique (optimisation)",
}
const PERKS := {"hack_specialization": "Spécialisation de hack"}
const COST_NAMES := {
	"hack_points": ["point de piratage", "points de piratage"],
	"optimization": ["point d'optimisation", "points d'optimisation"],
	"token": ["jeton", "jetons"],
}


## factors are the ratios of new to old values, by attribute name. Those already at their limit,
## or not unlocked, are left out.
static func read(root: Node) -> Array[Dictionary]:
	var data: Node = root.get_node_or_null("Data")
	var globals: Node = root.get_node_or_null("Globals")
	var attributes: Node = root.get_node_or_null("Attributes")
	var list: Array[Dictionary] = []
	if not is_instance_valid(data) or not is_instance_valid(globals) or not is_instance_valid(attributes):
		return list
	for key: String in UPGRADES:
		var entry: Variant = data.upgrades.get(key)
		if entry is Dictionary and _available(entry, globals.upgrades.get(key, 0), globals):
			var cost: float = entry.cost
			var attribute: String = entry.get("attribute_cost", "")
			var held: float = _value(attributes, attribute)
			list.append({
				"name": UPGRADES[key], "cost": cost, "resource": attribute, "held": held, "affordable": held >= cost,
				"cost_text": cost_text(cost, attribute), "changes": _changes(entry, attributes),
			})
	for key: String in PERKS:
		var entry: Variant = data.perks.get(key)
		if entry is Dictionary and _available(entry, globals.perks.get(key, 0), globals):
			var cost: float = entry.cost * pow(10.0, entry.cost_e) * pow(entry.cost_inc, globals.perks.get(key, 0))
			# A perk's currency is read like the game's others. Without it, a perk is shown but never advised.
			var currency: String = entry.get("currency", "token")
			var held: Variant = globals.currencies.get(currency)
			var known: bool = held is float or held is int
			list.append({
				"name": PERKS[key], "cost": cost, "resource": currency, "held": float(held) if known else -1.0,
				"affordable": known and float(held) >= cost, "cost_text": cost_text(cost, currency), "changes": _changes(entry, attributes),
			})
	return list


static func cost_text(cost: float, resource: String) -> String:
	var names: Array = COST_NAMES.get(resource, [resource, resource])
	return "%d %s" % [roundi(cost), names[0] if roundi(cost) <= 1 else names[1]]


## A copy of the chain with this purchase made.
static func apply(chain: Dictionary, changes: Dictionary) -> Dictionary:
	var changed := chain.duplicate()
	changed.launcher_ratio *= changes.get("breach_damage_multiplier", {"ratio": 1.0}).ratio
	changed.infection_ratio *= changes.get("infection_damage_multiplier", {"ratio": 1.0}).ratio
	changed.interval /= changes.get("breach_speed_multiplier", {"ratio": 1.0}).ratio
	changed.time_factor *= changes.get("breach_time_multiplier", {"ratio": 1.0}).ratio
	changed.power *= changes.get("hack_specialization_multiplier", {"ratio": 1.0}).ratio
	changed.crit_chance += changes.get("breach_critical_chance", {"added": 0.0}).added
	changed.crit_multiplier *= changes.get("breach_critical_multiplier", {"ratio": 1.0}).ratio
	return changed


static func _available(entry: Dictionary, level: Variant, globals: Node) -> bool:
	if entry.limit > 0.0 and level >= entry.limit:
		return false
	for requirement: String in entry.get("requirement", []):
		if not globals.unlocks.get(requirement, true):
			return false
	return true


static func _changes(entry: Dictionary, attributes: Node) -> Dictionary:
	var changes := {}
	for name: String in entry.attributes:
		var attribute: Variant = attributes.attributes.get(name)
		var effect: Array = entry.attributes[name]
		if attribute == null or effect.size() < 3:
			continue
		var old: float = (attribute.default + attribute.added) * attribute.multiplier
		var new: float = (attribute.default + attribute.added + effect[0]) * (attribute.multiplier + effect[1])
		if effect[2] > 0.0:
			new *= effect[2]
		changes[name] = {"ratio": new / old if old != 0.0 else 1.0, "added": new - old}
	return changes


static func _value(attributes: Node, name: String) -> float:
	var attribute: Variant = attributes.attributes.get(name)
	return float(attribute.value) if attribute != null else 0.0
