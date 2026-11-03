extends RefCounted
## What could be tried on the chain, without a figure: nodes idle or without power, inputs left empty that
## another node could fill, and nodes not placed yet. Read-only, from what the game exposes: no node is named
## in the code. A node only gets figures once it has attacked, like any other.

const HackingGraph := preload("hacking_graph.gd")
const HackingChain := preload("hacking_chain.gd")

const HACKING_CATEGORY := "hacking"
const TARGET_INPUTS: Array[String] = ["breach_damage", "infection_damage", "vulnerability"]
## What can be fixed with the nodes already there comes first, then what needs a new node.
const IDLE := 1
const EMPTY_INPUT := 2
## A purchase worth saving for comes from the advisor, which has its figure.
const SAVING := 3
const NOT_PLACED := 4
## How many suggestions the card shows; the others wait in the details.
const SHOWN := 3


## Each suggestion: {"key", "priority", "text"}, the text saying what it is for, then what to do.
static func read(graph: Dictionary, data: Variant, globals: Variant) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not is_instance_valid(data) or not data.get("windows") is Dictionary:
		return list
	var windows: Dictionary = data.windows
	var placed := {}
	for entry: Dictionary in graph.windows:
		placed[entry.type] = true
		if _is_hacking(windows, entry.type):
			_idle(list, graph, entry, data)
	_empty_inputs(list, graph, data)
	_not_placed(list, placed, windows, data, globals)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority < b.priority if a.priority != b.priority else a.key < b.key)
	return list


static func _is_hacking(windows: Dictionary, type: String) -> bool:
	return windows.get(type) is Dictionary and windows[type].get("category") == HACKING_CATEGORY


## A node without power makes nothing, a target without damage never attacks, and an output plugged
## into nothing is lost.
static func _idle(list: Array[Dictionary], graph: Dictionary, entry: Dictionary, data: Variant) -> void:
	var name: String = HackingChain._label(data, "windows", entry.type, entry.type)
	if entry.node is Node and HackingGraph.is_target(entry.node):
		if _connected(entry.node.get("breach_damage")) or _connected(entry.node.get("infection_damage")):
			return
		list.append({"key": "no_damage|%s" % entry.type, "priority": IDLE, "text": "%s ne reçoit aucun dégât, il n'attaque donc jamais. Branchez-y une sortie de dégâts ; une sortie déjà utilisée sera partagée." % name})
		return
	if _lacks_power(entry):
		list.append({"key": "no_power|%s" % entry.type, "priority": IDLE, "text": "%s n'a pas de puissance de hack, il ne produit rien. Branchez-y une sortie de puissance ; elle sera partagée avec ce qu'elle alimente déjà." % name})
		return
	for slot: Dictionary in entry.slots:
		if slot.resource != HackingGraph.POWER_RESOURCE and slot.production > 0.0 and slot.input_id == "" and slot.outputs_id.is_empty():
			list.append({"key": "unused|%s" % entry.type, "priority": IDLE, "text": "%s produit %s, mais sa sortie n'est branchée nulle part. Branchez-la vers une cible ou la suite de la chaîne." % [name, _resource(data, slot.resource)]})
			return


## An input of a target left empty while another node makes what it takes. Grouped by resource.
static func _empty_inputs(list: Array[Dictionary], graph: Dictionary, data: Variant) -> void:
	var empty := {}
	for entry: Dictionary in graph.windows:
		if not entry.node is Node or not HackingGraph.is_target(entry.node):
			continue
		var name: String = HackingChain._label(data, "windows", entry.type, entry.type)
		# A target without any damage is told on its own: its empty damage inputs say nothing more.
		var fed := _connected(entry.node.get("breach_damage")) or _connected(entry.node.get("infection_damage"))
		for slot_name: String in TARGET_INPUTS:
			var slot: Variant = entry.node.get(slot_name)
			if not fed or not is_instance_valid(slot) or _connected(slot):
				continue
			var resource := str(slot.get("resource"))
			if resource != "":
				if not empty.has(resource):
					empty[resource] = PackedStringArray()
				empty[resource].append(name)
	for resource: String in empty:
		var makers := PackedStringArray()
		var powered := false
		for entry: Dictionary in graph.windows:
			if entry.node is Node and HackingGraph.is_target(entry.node):
				continue
			# An output that makes something, or one waiting for power; an empty input of a node in the middle is neither.
			var waiting := _lacks_power(entry)
			for slot: Dictionary in entry.slots:
				if slot.resource == resource and slot.input_id == "" and (slot.production > 0.0 or waiting):
					var maker: String = HackingChain._label(data, "windows", entry.type, entry.type)
					if not makers.has(maker):
						makers.append(maker)
					powered = powered or slot.production > 0.0
		if makers.is_empty():
			continue
		var todo := "Branchez-y sa sortie" if powered else "Alimentez-le, puis branchez-y sa sortie"
		list.append({"key": "empty|%s" % resource, "priority": EMPTY_INPUT, "text": "%s est vide sur %s, alors que %s en produit. %s ; le conseiller mesurera ce qu'elle apporte." % [_resource(data, resource), ", ".join(empty[resource]), " et ".join(makers), todo]})


## A hacking node the player can place but has not, with what the game says it does.
static func _not_placed(list: Array[Dictionary], placed: Dictionary, windows: Dictionary, data: Variant, globals: Variant) -> void:
	var unlocks: Variant = globals.get("unlocks") if is_instance_valid(globals) else null
	for type: String in windows:
		if placed.has(type) or not _is_hacking(windows, type):
			continue
		var requirements: Variant = windows[type].get("requirement", [])
		if not unlocks is Dictionary or not requirements is Array:
			continue
		if not requirements.all(func(requirement: Variant) -> bool: return unlocks.get(requirement, false) == true):
			continue
		var name: String = HackingChain._label(data, "windows", type, type)
		var description := str(windows[type].get("description", ""))
		var what := " : %s" % data.tr(description).strip_edges().trim_suffix(".") if description != "" else ""
		list.append({"key": "new|%s" % type, "priority": NOT_PLACED, "text": "%s n'est pas encore posé%s. Ajoutez-le depuis Add Node et branchez-le : il sera chiffré après quelques attaques." % [name, what]})


static func _lacks_power(entry: Dictionary) -> bool:
	for slot: Dictionary in entry.slots:
		if slot.resource == HackingGraph.POWER_RESOURCE and slot.input_id == "" and slot.outputs_id.is_empty() and slot.production <= 0.0:
			return true
	return false


static func _connected(slot: Variant) -> bool:
	return is_instance_valid(slot) and slot.get("input_id") != null and str(slot.get("input_id")) != ""


static func _resource(data: Variant, resource: String) -> String:
	return HackingChain._label(data, "resources", resource, resource)
