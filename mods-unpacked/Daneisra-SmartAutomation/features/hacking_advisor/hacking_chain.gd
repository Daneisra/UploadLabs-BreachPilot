extends RefCounted
## Reads the hacking chain into plain values for HackingModel. Reads properties and calls the game's
## value getters only: no connection, level or purchase is changed.

const TARGET_LABELS := {
	"breach_corps": "Entreprises", "breach_government": "Gouvernement", "breach_bank": "Banque", "breach_anonymous": "Anonymous",
}
## Levels looked at beyond the highest unlocked one: enough to see what a scenario would open.
const LEVELS_AHEAD := 4


## error is empty when the chain can be compared. intervals gives the attack interval seen for each type.
static func read(desktop: Variant, intervals: Dictionary, attributes: Variant) -> Dictionary:
	if not is_instance_valid(desktop) or not is_instance_valid(desktop.get("windows")):
		return {"error": "no_desktop"}
	var by_type := {}
	for window: Node in desktop.windows.get_children():
		var type: Variant = window.get("window")
		if type is String or type is StringName:
			by_type.get_or_add(str(type), []).append(window)

	if by_type.get("hacker", []).size() != 1 or by_type.get("payload_launcher", []).size() != 1:
		return {"error": "chain_shape"}
	for type: String in ["build_infection", "critical_payload", "charged_attack", "execute_injection"]:
		if by_type.get(type, []).size() > 1:
			return {"error": "chain_shape"}
	var source: Node = by_type.hacker[0]
	var launcher: Node = by_type.payload_launcher[0]
	var infection: Variant = by_type.build_infection[0] if by_type.has("build_infection") else null
	var critical: Variant = by_type.critical_payload[0] if by_type.has("critical_payload") else null
	var charged: Variant = by_type.charged_attack[0] if by_type.has("charged_attack") else null
	var injection: Variant = by_type.execute_injection[0] if by_type.has("execute_injection") else null

	var problems := PackedStringArray()
	var outputs: Array = source.hack_power.outputs_id
	var fed := 0
	if launcher.hack_power.input_id == source.hack_power.id:
		fed += 1
	else:
		problems.append("launcher_not_fed")
	if infection != null and infection.hack_power.input_id == source.hack_power.id:
		fed += 1
	var injection_fed: bool = injection != null and injection.hack_power.input_id == source.hack_power.id
	if injection_fed:
		fed += 1

	var chain := {
		"error": "",
		"power": float(source.hack_power.count),
		"launcher_ratio": _ratio(launcher, problems),
		"has_infection": infection != null,
		"infection_ratio": _ratio(infection, problems) if infection != null else 0.0,
		"has_crit": critical != null,
		"crit_factor": 1.0,
		"charge_every": 0,
		"injection_fed": injection_fed,
		"other_consumers": maxi(outputs.size() - fed, 0),
		"crit_chance": 0.0,
		"crit_multiplier": 0.0,
		"time_factor": 1.0,
		"interval": 0.0,
		"targets": {},
		"current": {"payload": [], "infection": []},
		"problems": problems,
	}
	for node: Variant in [critical, charged]:
		if node != null:
			chain.crit_factor *= _announced_factor(node)
	var table: Variant = attributes.get("attributes") if is_instance_valid(attributes) else null
	if charged != null:
		if table is Dictionary and table.has("charged_attacks_requirement"):
			chain.charge_every = roundi(table.charged_attacks_requirement.value)
		else:
			problems.append("charge_unknown")
	if critical != null:
		if table is Dictionary and table.has("breach_critical_chance") and table.has("breach_critical_multiplier"):
			chain.crit_chance = float(table.breach_critical_chance.value)
			chain.crit_multiplier = float(table.breach_critical_multiplier.value)
		else:
			problems.append("crit_unknown")

	for type: String in TARGET_LABELS:
		for window: Node in by_type.get(type, []):
			if chain.targets.has(type):
				return {"error": "chain_shape"}
			chain.targets[type] = _read_target(window, type)
			if window.breach_damage.production > 0.0:
				chain.current.payload.append(type)
			if window.infection_damage.production > 0.0:
				chain.current.infection.append(type)
			chain.interval = maxf(chain.interval, intervals.get(type, 0.0))
	if chain.targets.is_empty():
		return {"error": "no_target"}
	if chain.current.payload.is_empty():
		return {"error": "no_payload"}
	if chain.interval <= 0.0:
		return {"error": "no_attack_seen"}
	return chain


## What one hack power gives. An idle node shows no production: its own multiplier is then all we know.
static func _ratio(node: Node, problems: PackedStringArray) -> float:
	var power: float = node.hack_power.count
	if power > 0.0 and node.damage.production > 0.0:
		return float(node.damage.production / power)
	problems.append("ratio_estimated:%s" % node.window)
	return float(node.multiplier)


## What a node placed on the payload's way adds to the damage announced, whatever its slots are called.
static func _announced_factor(node: Node) -> float:
	var incoming := 0.0
	var outgoing := 0.0
	for container: Variant in node.containers:
		if not is_instance_valid(container):
			continue
		if container.input_id != "":
			incoming = container.production
		else:
			outgoing = container.production
	return float(outgoing / incoming) if incoming > 0.0 else 1.0


static func _read_target(window: Node, type: String) -> Dictionary:
	var max_level := int(window.data.max_level)
	var levels := {}
	for level: int in range(0, max_level + LEVELS_AHEAD + 1):
		levels[level] = {
			"firewall": float(window.get_max_firewall(level)),
			"breach": float(window.get_max_breach(level)),
			"time": float(window.get_max_time(level)),
			"elite": window.is_elite(level),
			"reward": float(window.get_reward(level)),
			"xp": float(window.get_experience_reward(level)),
		}
	return {
		"label": TARGET_LABELS[type],
		"level": int(window.data.level),
		"max_level": max_level,
		"levels": levels,
		"announced_payload": float(window.breach_damage.production),
		"announced_infection": float(window.infection_damage.production),
		"vulnerability": float(window.vulnerability.count),
		"breach_variation": int(window.breach_damage.variation),
		"infection_variation": int(window.infection_damage.variation),
		"cur_reward": float(window.cur_reward),
		"cur_experience": float(window.cur_experience),
	}
