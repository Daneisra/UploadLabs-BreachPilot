extends RefCounted
## The advisor on chains it has never seen, and on values measured in game: 231.1 hack power split
## between the launcher and the infection gave 127.11 and 57.78, Government level 7 took 4.59 s with
## half the infection, and critical hits were 2.5 normal hits.

const ADVISOR := "res://mods-unpacked/Daneisra-SmartAutomation/features/hacking_advisor/"
const HackingModel := preload(ADVISOR + "hacking_model.gd")
const HackingChain := preload(ADVISOR + "hacking_chain.gd")
const HackingGraph := preload(ADVISOR + "hacking_graph.gd")
const HackingUpgrades := preload(ADVISOR + "hacking_upgrades.gd")
const HackingAdvice := preload(ADVISOR + "hacking_advice.gd")
const HitLog := preload(ADVISOR + "hit_log.gd")
const Observer := preload("res://mods-unpacked/Daneisra-SmartAutomation/features/threat_manager/threat_observer.gd")

var _check: Callable


class Slot extends Node:
	var id := ""
	var input_id := ""
	var outputs_id: Array = []
	var resource := ""
	var count := 0.0
	var production := 0.0
	var variation := 0


## Any node: its slots are all it is known by.
class FakeNode extends Node:
	var window := ""
	var containers: Array = []


class FakeBreach extends FakeNode:
	var data := {"level": 7.0, "max_level": 8.0}
	var max_firewall := 0.0
	var max_breach := 0.0
	var breach_damage: Slot
	var infection_damage: Slot
	var vulnerability: Slot
	var result: Slot

	func get_max_firewall(level: int) -> float: return 100.0 * level
	func get_max_breach(level: int) -> float: return 100.0 * level
	func get_max_time(_level: int) -> float: return 6.0
	func is_elite(_level: int) -> bool: return false
	func get_reward(level: int) -> float: return 4.0 * pow(1.5, level)
	func get_experience_reward(level: int) -> float: return pow(2.0, level)


class TrialWindow extends FakeBreach:
	func get_max_firewall(_level: int) -> float: return 300.0
	func get_max_breach(_level: int) -> float: return 300.0


class FakeDesktop extends Node:
	var windows := Node.new()


class FakeAttribute extends RefCounted:
	var default := 1.0
	var added := 0.0
	var multiplier := 1.0
	var value := 1.0

	func _init(start: float, extra: float = 0.0) -> void:
		default = start
		added = extra
		value = start + extra


class FakeTable extends Node:
	var currencies := {}
	var upgrades := {}
	var perks := {}
	var unlocks := {}
	var attributes := {}


func run(check: Callable) -> void:
	_check = check
	_test_hit_log()
	_test_graph_any_chain()
	_test_scenarios_and_power()
	_test_measured_rates()
	_test_abstention()
	_test_upgrade_table()
	_test_critical_changes()
	_test_advice()
	_test_trial_without_forecast()


## 10 % of hits at 2.5 times the others, as measured, with the announcement of the critical node.
func _measured_multipliers() -> PackedFloat32Array:
	var list := PackedFloat32Array()
	for index: int in 100:
		list.append(0.606 * (2.5 if index % 10 == 0 else 1.0))
	return list


func _levels(firewall: float, breach: float, count: int = 12) -> Dictionary:
	var levels := {}
	for level: int in count:
		var scale: float = pow(1.5, level - 7)
		levels[level] = {"firewall": firewall * scale, "breach": breach * scale, "time": 6.0, "reward": 4.0 * pow(1.5, level), "xp": pow(2.0, level)}
	return levels


func _target(label: String, reward: String, firewall: float, breach: float) -> Dictionary:
	return {
		"type": label, "label": label, "reward_name": reward, "level": 7, "max_level": 8, "levels": _levels(firewall, breach),
		"interval": 1.0, "vulnerability": 0.0, "announced_payload": 104.86, "announced_infection": 28.89, "variation": 0,
		"chain_key": "k", "real": {"attacks": 0, "successes": 0, "used": 0.0},
	}


## The measured chain, as HackingChain gives it.
func _chain() -> Dictionary:
	return {
		"error": "",
		"targets": {
			"corps": _target("Infiltrer Entreprises", "Données", 136.6, 546.5),
			"gov": _target("Infiltrer Gouvernement", "Renseignements", 341.5, 341.5),
		},
		"streams": {
			"P": {"id": "P", "kind": "payload", "resource": "payload_damage", "label": "Payload critique", "production": 209.73, "outputs": 2, "targets": ["corps", "gov"], "multipliers": _measured_multipliers(), "source": "S", "window_type": "any"},
			"I": {"id": "I", "kind": "infection", "resource": "infection_damage", "label": "Produit d'infection", "production": 57.78, "outputs": 2, "targets": ["corps", "gov"], "multipliers": PackedFloat32Array(), "source": "S", "window_type": "any"},
		},
		"sources": {"S": {"outputs": 2}},
		"current": {"payload": {"corps": "P", "gov": "P"}, "infection": {"corps": "I", "gov": "I"}, "vulnerability": false},
		"time_factor": 1.0, "interval_factor": 1.0, "power_factor": 1.0, "payload_factor": 1.0, "infection_factor": 1.0, "crit_multiplier": 1.5,
	}


func _test_hit_log() -> void:
	var log := HitLog.new()
	log.add("corps", "a", {"event": "success", "level": 8, "complete": true, "used": 5.0, "damage_rate": 100.0, "vulnerability": 0.25, "hits": PackedFloat32Array([125.0, 250.0])})
	log.add("corps", "a", {"event": "failure_power", "level": 8, "complete": true, "damage_rate": 100.0, "vulnerability": 0.25})
	log.add("corps", "a", {"event": "success", "level": 8, "complete": false, "used": 9.0, "damage_rate": 100.0, "hits": PackedFloat32Array([999.0])})
	var kept := log.multipliers("a")
	_check.call(kept.size() == 2 and is_equal_approx(kept[0], 1.0) and is_equal_approx(kept[1], 2.0), "hits are kept relative to the announcement, without vulnerability")
	var stats := log.attack_stats("corps", "a", 8, HitLog.power_key(100.0, 0.0))
	_check.call(stats.attacks == 2 and stats.successes == 1 and is_equal_approx(stats.used, 5.0), "only complete attacks count")
	_check.call(log.attack_stats("corps", "a", 8, HitLog.power_key(130.0, 0.0)).attacks == 0, "attacks at another power do not compare")
	_check.call(is_equal_approx(log.last_vulnerability("corps"), 0.25) and log.last_vulnerability("other") == 0.0, "the last attack's vulnerability is kept")
	_check.call(log.multipliers("b").is_empty(), "another chain starts a new measure")
	_check.call(log.multipliers("a").size() == 2, "the old chain's measures stay")
	for index: int in HitLog.MAX_CHAINS + 2:
		log.add("corps", "other%d" % index, {"event": "success", "level": 1, "complete": true, "damage_rate": 1.0})
	_check.call(log.multipliers("a").is_empty(), "the oldest chains make room")
	var many := HitLog.new()
	var big := PackedFloat32Array()
	big.resize(HitLog.MAX_HITS + 50)
	big.fill(10.0)
	many.add("corps", "x", {"event": "success", "level": 1, "complete": true, "damage_rate": 10.0, "hits": big})
	_check.call(many.multipliers("x").size() == HitLog.MAX_HITS, "the measure stays bounded")


func _slot(id: String, resource: String, production: float, input_id: String = "", outputs: Array = []) -> Slot:
	var slot := Slot.new()
	slot.id = id
	slot.resource = resource
	slot.production = production
	slot.count = production
	slot.input_id = input_id
	slot.outputs_id = outputs
	return slot


func _node(type: String, slots: Array) -> FakeNode:
	var node := FakeNode.new()
	node.window = type
	for slot: Slot in slots:
		node.add_child(slot)
	node.containers = slots
	return node


func _breach(type: String, payload_input: String, infection_input: String) -> FakeBreach:
	var node := FakeBreach.new()
	node.window = type
	node.breach_damage = _slot(type + "_p", "payload_damage", 50.0 if payload_input != "" else 0.0, payload_input)
	node.infection_damage = _slot(type + "_i", "infection_damage", 10.0 if infection_input != "" else 0.0, infection_input)
	node.vulnerability = _slot(type + "_v", "vulnerability", 0.0)
	node.result = _slot(type + "_r", "reward", 0.0)
	var slots := [node.breach_damage, node.infection_damage, node.vulnerability, node.result]
	for slot: Slot in slots:
		node.add_child(slot)
	node.containers = slots
	return node


## Names never met in the game: nothing may depend on them.
func _strange_desktop() -> FakeDesktop:
	var desktop := FakeDesktop.new()
	var nodes: Array[Node] = [
		_node("xx_source", [_slot("S", "hack_power", 300.0, "", ["F1", "F2", "F3"])]),
		_node("xx_launcher", [_slot("F1", "hack_power", 100.0, "S"), _slot("L", "payload_damage", 110.0, "", ["Q"])]),
		_node("xx_unknown_step", [_slot("Q", "payload_damage", 110.0, "L"), _slot("R", "payload_damage", 220.0, "", ["zz_alpha_p", "zz_beta_p", "elsewhere"])]),
		_node("xx_virus", [_slot("F2", "hack_power", 100.0, "S"), _slot("V", "infection_damage", 20.0, "", ["zz_alpha_i"])]),
		_node("xx_other_consumer", [_slot("F3", "hack_power", 100.0, "S")]),
		_node("xx_no_slots", []),
		_breach("zz_alpha", "R", "V"),
		_breach("zz_beta", "R", ""),
	]
	var odd := Node.new()
	odd.name = "NotAWindowAtAll"
	nodes.append(odd)
	for node: Node in nodes:
		desktop.windows.add_child(node)
	return desktop


func _free_desktop(desktop: FakeDesktop) -> void:
	desktop.windows.free()
	desktop.free()


func _test_graph_any_chain() -> void:
	_check.call(HackingChain.read(null, {}, null, null, null).error == "no_desktop", "no desktop is said plainly")
	var empty := FakeDesktop.new()
	_check.call(HackingChain.read(empty, {}, null, null, null).error == "no_target", "no target is said plainly")
	_free_desktop(empty)

	var desktop := _strange_desktop()
	var log := HitLog.new()
	var graph := HackingGraph.snapshot(desktop)
	var alpha: Node = desktop.windows.get_child(6)
	var key := HackingGraph.chain_key(graph, alpha, null)
	var hits := PackedFloat32Array()
	for index: int in 40:
		hits.append(50.0)
	log.add("zz_alpha", key, {"event": "success", "level": 1, "complete": true, "used": 2.0, "damage_rate": 50.0, "hits": hits})

	var chain := HackingChain.read(desktop, {"zz_alpha": 1.0}, log, null, null)
	_check.call(chain.error == "" and chain.targets.size() == 2, "targets are found by what they expose, whatever their names")
	var labels := {"a": {"label": "Infiltrer Entreprises"}, "b": {"label": "Infiltrer Gouvernement"}}
	HackingChain._shorten_labels(labels)
	_check.call(labels.a.label == "Entreprises" and labels.b.label == "Gouvernement", "a first word shared by all targets goes")
	var alone := {"a": {"label": "Infiltrer Entreprises"}}
	HackingChain._shorten_labels(alone)
	_check.call(alone.a.label == "Infiltrer Entreprises", "a single target keeps its whole name")
	_check.call(chain.streams.has("R") and chain.streams.R.kind == "payload", "the payload is followed through a node never seen")
	_check.call(chain.streams.R.outputs == 3, "an output going elsewhere is counted")
	_check.call(chain.streams.R.source == "S" and chain.streams.V.source == "S", "the power is followed up to its source")
	_check.call(chain.sources.S.outputs == 3, "a consumer never seen shares the power")
	_check.call(chain.current.payload.zz_alpha == "R" and chain.current.infection.zz_beta == "", "the connections are read from the graph")
	_check.call(chain.streams.R.multipliers.size() == 40, "the hits measured on this chain are used")

	var model := HackingModel.new(chain)
	var row := model.evaluate(model.current_scenario())
	_check.call(row.current and row.insufficient.is_empty(), "a chain with unknown nodes is compared from its measured hits")
	_check.call(row.targets.zz_alpha.level >= 0, "the attack is calculated")
	_check.call(model.scenarios().size() > 1, "scenarios exist for any chain")
	_check.call(absf(model._scales("zz_alpha", chain.current).hit - 220.0 / 3.0) < 0.01, "an output going elsewhere keeps its share")

	var renamed := _strange_desktop()
	renamed.windows.get_child(2).window = "another_name_entirely"
	var other_graph := HackingGraph.snapshot(renamed)
	_check.call(HackingGraph.chain_key(other_graph, renamed.windows.get_child(6), null) != key, "a different node on the way is a different chain")
	var no_log := HackingChain.read(renamed, {"zz_alpha": 1.0}, null, null, null)
	var unmeasured := HackingModel.new(no_log)
	_check.call(unmeasured.evaluate(unmeasured.current_scenario()).insufficient.has(HackingModel.REASON_HITS), "without hits on this chain, no figure")
	_free_desktop(renamed)

	var vulnerable := _strange_desktop()
	var fed: FakeBreach = vulnerable.windows.get_child(6)
	fed.vulnerability.input_id = "V"
	fed.vulnerability.count = 0.0
	log.add("zz_alpha", "whatever", {"event": "success", "level": 1, "complete": true, "damage_rate": 1.0, "vulnerability": 0.24})
	var kept_value := HackingChain.read(vulnerable, {"zz_alpha": 1.0}, log, null, null)
	_check.call(is_equal_approx(kept_value.targets.zz_alpha.vulnerability, 0.24), "vulnerability falling to nothing between two attacks is not believed")
	_free_desktop(vulnerable)

	var missing := Slot.new()
	desktop.windows.get_child(0).containers = [missing, null, 12]
	var broken := HackingChain.read(desktop, {}, null, null, null)
	_check.call(broken.error == "", "broken slots are skipped")
	_check.call(broken.streams.R.source == "", "a source that cannot be read frees no power")
	missing.free()

	var spare := _strange_desktop()
	spare.windows.get_child(4).containers = [_slot("F3", "hack_power", 100.0, "S"), _slot("W", "payload_damage", 90.0)]
	var with_spare := HackingChain.read(spare, {"zz_alpha": 1.0}, log, null, null)
	_check.call(with_spare.streams.has("W") and with_spare.streams.W.kind == "payload", "a powered node connected to nothing can be proposed")
	var spare_model := HackingModel.new(with_spare)
	_check.call(absf(spare_model._scales("zz_alpha", with_spare.current).hit - 220.0 / 3.0) < 0.01, "a node connected to nothing does not free its power")
	_free_desktop(spare)

	var loop := FakeDesktop.new()
	loop.windows.add_child(_node("loop_a", [_slot("A1", "payload_damage", 1.0, "B2"), _slot("A2", "payload_damage", 1.0, "", ["B1"])]))
	loop.windows.add_child(_node("loop_b", [_slot("B1", "payload_damage", 1.0, "A2"), _slot("B2", "payload_damage", 1.0, "", ["A1"])]))
	_check.call(HackingGraph.upstream(HackingGraph.snapshot(loop), "A2").path.size() > 0, "a loop in the chain ends the walk")
	_free_desktop(loop)

	var two := _strange_desktop()
	two.windows.add_child(_breach("zz_alpha", "R", ""))
	var doubled := HackingChain.read(two, {}, null, null, null)
	_check.call(doubled.targets.size() == 3, "two nodes of a type are both read")
	_free_desktop(two)
	_free_desktop(desktop)


func _test_scenarios_and_power() -> void:
	var model := HackingModel.new(_chain())
	var list := model.scenarios()
	_check.call(list.size() == 12, "3 payload choices against 4 infection choices")
	_check.call(list.filter(func(s: Dictionary) -> bool: return model.is_current(s)).size() == 1, "the current connections are among the scenarios")

	var both: Dictionary = _chain().current
	var scales: Dictionary = model._scales("gov", both)
	_check.call(absf(scales.hit - 104.865) < 0.01 and absf(scales.stack - 28.89) < 0.01, "the current share is what the game announces")
	var alone := {"payload": {"corps": "P", "gov": ""}, "infection": {"corps": "", "gov": ""}, "vulnerability": false}
	_check.call(absf(model._scales("corps", alone).hit - 419.46) < 0.01, "no infection and one target doubles twice")
	_check.call(model._scales("gov", alone).hit == 0.0, "a target with nothing sent gets nothing")
	var row := model.evaluate(alone)
	_check.call(row.targets.gov.level == -1 and is_equal_approx(row.xp_rate, row.targets.corps.xp_rate), "a target with no damage brings nothing")

	var big := _chain()
	for index: int in 3:
		big.targets["extra%d" % index] = _target("Extra", "Extra", 100.0, 100.0)
		big.current.payload["extra%d" % index] = ""
		big.current.infection["extra%d" % index] = ""
	var bounded := HackingModel.new(big).scenarios()
	_check.call(bounded.size() <= HackingModel.MAX_SCENARIOS, "the number of scenarios stays bounded")
	_check.call(HackingModel.new(big).is_current(bounded[0]), "bounded scenarios still start from the current chain")

	var vulnerable := _chain()
	vulnerable.current.vulnerability = true
	vulnerable.targets.gov.vulnerability = 0.234
	vulnerable.streams["J"] = {"id": "J", "kind": "vulnerability", "resource": "vulnerability", "label": "Injection", "production": 1.0, "outputs": 2, "targets": ["corps", "gov"], "multipliers": PackedFloat32Array(), "source": "S", "window_type": "any"}
	vulnerable.sources.S.outputs = 3
	var with_it := HackingModel.new(vulnerable)
	_check.call(with_it.scenarios().size() == 24, "vulnerability can be kept or taken off")
	var off: Dictionary = vulnerable.current.duplicate(true)
	off.vulnerability = false
	_check.call(absf(with_it._scales("gov", off).hit / with_it._scales("gov", vulnerable.current).hit - 1.5) < 0.001, "taking a node off gives its share of power back")
	_check.call(is_equal_approx(with_it._scales("gov", vulnerable.current).bonus, 1.234) and is_equal_approx(with_it._scales("gov", off).bonus, 1.0), "vulnerability multiplies while it is there")


func _test_measured_rates() -> void:
	var model := HackingModel.new(_chain())
	var corps: Dictionary = _chain().targets.corps
	var government: Dictionary = _chain().targets.gov
	var hits := _measured_multipliers()
	_check.call(model.attack_outcome(corps.levels[9], 104.865, 57.78, 1.0, hits, 1.0).chance >= 0.85, "Corps level 9 with the whole infection mostly succeeds, as measured")
	_check.call(absf(model.attack_outcome(corps.levels[8], 104.865, 28.89, 1.0, hits, 1.0).chance - 0.48) < 0.2, "Corps level 8 with half the infection is a coin toss, as measured")
	_check.call(absf(model.attack_outcome(government.levels[8], 104.865, 28.89, 1.0, hits, 1.0).chance - 0.47) < 0.2, "Government level 8 with half the infection is a coin toss, as measured")
	_check.call(model.attack_outcome(corps.levels[9], 104.865, 28.89, 1.0, hits, 1.0).chance < 0.3, "Corps level 9 with half the infection fails, as measured")
	_check.call(is_equal_approx(model._next_shot(3.95, 1.0), 4.0) and is_equal_approx(model._next_shot(4.0, 1.0), 5.0), "the next attack waits for the next shot, as measured")

	var shared := model.evaluate(_chain().current)
	_check.call(shared.targets.gov.level == 7 and shared.targets.corps.level == 7, "both hold level 7 with half the infection, as measured")
	_check.call(absf(shared.targets.gov.used - 4.59) < 0.6, "the duration stays near the 4.59 s measured")
	_check.call(absf(shared.xp_rate - 2926.0) / 2926.0 < 0.15, "the XP rate stays near the 2926 per minute measured")

	var after := _chain()
	after.infection_factor = 1.1
	var bought := HackingModel.new(after).evaluate(_chain().current)
	_check.call(bought.targets.gov.level == 8 and bought.targets.corps.level == 8, "the purchase opens level 8 on both, as measured")
	_check.call(absf(bought.xp_rate - 5128.0) / 5128.0 < 0.2, "the XP rate stays near the 5128 measured after the purchase")
	var stronger := _chain()
	stronger.infection_factor = 1.1
	stronger.power_factor = 1.2
	var more := HackingModel.new(stronger).evaluate(_chain().current)
	_check.call(absf(more.xp_rate - 5694.0) / 5694.0 < 0.15, "the XP rate stays near the 5694 measured with more power")

	var doubled := PackedFloat32Array()
	for index: int in 99:
		doubled.append(0.606 * (2.0 if index % 3 == 0 else 1.0))
	var plain := HackingModel.new(_chain()).attack_outcome(corps.levels[8], 104.865, 28.89, 1.0, hits, 1.0)
	var charged := HackingModel.new(_chain()).attack_outcome(corps.levels[8], 104.865, 28.89, 1.0, doubled, 1.0)
	_check.call(charged.chance > plain.chance, "a node doubling some hits counts without being known, from its hits")
	var vulnerable := HackingModel.new(_chain()).attack_outcome(government.levels[8], 104.865, 28.89, 1.234, hits, 1.0)
	_check.call(vulnerable.chance > 0.9 and vulnerable.used < 6.0, "vulnerability helps, as measured")


func _test_abstention() -> void:
	var fresh := _chain()
	fresh.streams.P.multipliers = PackedFloat32Array([0.6, 0.6])
	var new_chain := HackingModel.new(fresh)
	var row := new_chain.evaluate(fresh.current)
	_check.call(row.insufficient.has(HackingModel.REASON_HITS) and row.targets.gov.level == -1 and row.xp_rate == 0.0, "too few hits give no figure")

	var no_attack := _chain()
	no_attack.targets.corps.interval = 0.0
	no_attack.targets.gov.interval = 0.0
	_check.call(HackingModel.new(no_attack).evaluate(no_attack.current).insufficient.has(HackingModel.REASON_INTERVAL), "no attack seen gives no figure")

	var stealth := _chain()
	stealth.targets.gov.variation = 1
	var hidden := HackingModel.new(stealth).evaluate(stealth.current)
	_check.call(hidden.insufficient.has(HackingModel.REASON_UNMEASURED) and hidden.targets.gov.level == -1, "what was never measured is never estimated")

	var current := HackingModel.new(_chain()).evaluate(_chain().current)
	var better := HackingModel.new(_chain()).evaluate(_chain().current)
	better.current = false
	better.xp_rate = 99999.0
	better.insufficient = PackedStringArray([HackingModel.REASON_HITS])
	var rows: Array[Dictionary] = [current, better]
	_check.call(HackingAdvice.best_row(rows, current, "xp") == current, "a scenario not understood leaves the ranking, however good it looks")

	var wrong := _chain()
	wrong.targets.gov.real = {"attacks": 30, "successes": 3, "used": 15.0}
	var refuting := HackingModel.new(wrong)
	var found := refuting.contradictions(refuting.evaluate(wrong.current))
	_check.call(found.size() == 1 and found[0].key == "gov" and found[0].attacks == 30, "real failures refute the calculation")
	var right := _chain()
	right.targets.gov.real = {"attacks": 30, "successes": 30, "used": 138.0}
	var agreeing := HackingModel.new(right)
	_check.call(agreeing.contradictions(agreeing.evaluate(right.current)).is_empty(), "attacks that agree refute nothing")
	var few := _chain()
	few.targets.gov.real = {"attacks": 3, "successes": 0, "used": 0.0}
	var too_few := HackingModel.new(few)
	_check.call(too_few.contradictions(too_few.evaluate(few.current)).is_empty(), "a few attacks are not enough to refute")


func _test_upgrade_table() -> void:
	var root := Node.new()
	var data := FakeTable.new()
	data.name = "Data"
	data.upgrades = {
		"a": {"name": "Dégâts", "category": "hacking", "cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_damage_multiplier": [0.1, 0.0, 0.0]}},
		"b": {"name": "Critique", "category": "hacking", "cost": 2.0, "limit": 5.0, "attribute_cost": "hack_points", "requirement": ["research.ok"], "attributes": {"breach_critical_multiplier": [0.0, 0.12, 0.0]}},
		"c": {"name": "Spécialiste", "category": "hacking", "cost": 4.0, "limit": 1.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_damage_multiplier": [0.0, 0.0, 0.6], "infection_damage_multiplier": [0.0, 0.0, 2.0]}},
		"d": {"name": "Temps", "category": "hacking", "cost": 9.0, "limit": 5.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_time_multiplier": [0.2, 0.0, 0.0]}},
		"full": {"name": "Plein", "category": "hacking", "cost": 1.0, "limit": 2.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_speed_multiplier": [0.04, 0.0, 0.0]}},
		"locked": {"name": "Verrou", "category": "hacking", "cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": ["research.no"], "attributes": {"infection_damage_multiplier": [0.1, 0.0, 0.0]}},
		"future": {"name": "Inconnu", "category": "hacking", "cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"attribute_never_seen": [1.0, 0.0, 0.0]}},
		"absent": {"name": "Absent", "category": "hacking", "cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_damage_multiplier": ["texte", 0.0, 0.0]}},
		"charge": {"name": "Charge", "category": "optimizations", "cost": 1.0, "limit": 1.0, "attribute_cost": "optimization", "requirement": [], "attributes": {"charged_attacks_requirement": [-1.0, 0.0, 0.0]}},
		"unrelated": {"name": "Hors sujet", "category": "main", "cost": 1.0, "limit": 0.0, "currency": "money", "requirement": [], "attributes": {"text_value_multiplier": [0.2, 0.0, 0.0]}},
	}
	data.perks = {"spec": {"name": "Spécialisation", "cost": 5.0, "cost_e": 2.0, "cost_inc": 1.0, "limit": 4.0, "currency": "token", "requirement": [], "attributes": {"hack_specialization_multiplier": [0.25, 0.0, 0.0]}}}
	root.add_child(data)
	var globals := FakeTable.new()
	globals.name = "Globals"
	globals.upgrades = {"a": 1, "full": 2, "d": 1}
	globals.perks = {"spec": 1}
	globals.unlocks = {"research.no": false, "research.ok": true}
	globals.currencies = {"token": 400.0}
	root.add_child(globals)
	var attributes := FakeTable.new()
	attributes.name = "Attributes"
	attributes.attributes = {
		"hack_points": FakeAttribute.new(6.0),
		"optimization": FakeAttribute.new(1.0),
		"breach_damage_multiplier": FakeAttribute.new(1.0, 0.1),
		"infection_damage_multiplier": FakeAttribute.new(1.0),
		"breach_critical_multiplier": FakeAttribute.new(1.5),
		"breach_time_multiplier": FakeAttribute.new(1.0, 0.2),
		"charged_attacks_requirement": FakeAttribute.new(3.0),
		"attribute_never_seen": FakeAttribute.new(1.0),
		"hack_specialization_multiplier": FakeAttribute.new(1.0, 0.25),
	}
	root.add_child(attributes)

	var by_name := {}
	for item: Dictionary in HackingUpgrades.read(root):
		by_name[item.name] = item
	_check.call(not by_name.has("Plein") and not by_name.has("Verrou"), "a purchase at its limit or locked is left out")
	_check.call(not by_name.has("Hors sujet"), "a purchase unrelated to hacking is left out")
	_check.call(by_name.has("Inconnu") and not by_name["Inconnu"].followed, "a purchase never seen is listed, without a figure")
	_check.call(by_name.has("Absent") and not by_name["Absent"].followed, "an effect that cannot be read gives no figure, and no failure")
	_check.call(by_name.has("Charge") and not by_name["Charge"].followed, "a hacking purchase found outside the hacking category is listed")
	_check.call(absf(by_name["Dégâts"].changes.breach_damage_multiplier.ratio - 1.2 / 1.1) < 0.001 and by_name["Dégâts"].followed, "an added value is measured against the current one")
	_check.call(absf(by_name["Critique"].changes.breach_critical_multiplier.ratio - 1.12) < 0.001, "a multiplier gives 12 %, as the game says")
	_check.call(absf(by_name["Spécialiste"].changes.breach_damage_multiplier.ratio - 0.6) < 0.001, "the specialist cuts the payload, as the game says")
	_check.call(HackingUpgrades.downsides(by_name["Spécialiste"].changes) == PackedStringArray(["Dégâts Payload -40 %"]), "the game's own drawback is named")
	_check.call(not by_name["Temps"].affordable and by_name["Dégâts"].affordable, "the points held decide what is affordable")
	_check.call(absf(by_name["Spécialisation"].cost - 500.0) < 0.001 and not by_name["Spécialisation"].affordable and by_name["Spécialisation"].held == 400.0, "400 tokens do not pay for 500")
	_check.call(by_name["Dégâts"].cost_text == "1 point de piratage" and by_name["Critique"].cost_text == "2 points de piratage", "the cost reads properly")
	globals.currencies = {}
	for item: Dictionary in HackingUpgrades.read(root):
		if item.name == "Spécialisation":
			_check.call(item.held == -1.0 and not item.affordable, "an unknown balance is never advised")
	root.free()

	var chain := _chain()
	var changed := HackingUpgrades.apply(chain, {"breach_damage_multiplier": {"ratio": 1.2}, "breach_speed_multiplier": {"ratio": 1.25}, "breach_time_multiplier": {"ratio": 1.5}, "hack_specialization_multiplier": {"ratio": 2.0}})
	_check.call(is_equal_approx(changed.payload_factor, 1.2) and is_equal_approx(changed.infection_factor, 1.0), "a purchase only changes what it touches")
	_check.call(is_equal_approx(changed.interval_factor, 1.25) and is_equal_approx(changed.time_factor, 1.5) and is_equal_approx(changed.power_factor, 2.0), "speed, time and power follow")
	_check.call(chain.payload_factor == 1.0, "the chain read from the game stays as it was")
	var before := HackingModel.new(chain).evaluate(chain.current)
	var after := HackingModel.new(HackingUpgrades.apply(chain, {"hack_specialization_multiplier": {"ratio": 2.0}})).evaluate(chain.current)
	_check.call(after.xp_rate > before.xp_rate, "more power brings more XP")


func _test_critical_changes() -> void:
	var hits := _measured_multipliers()
	_check.call(HackingUpgrades.can_follow_critical(hits, 1.5), "critical hits are told apart in the measures")
	_check.call(not HackingUpgrades.can_follow_critical(PackedFloat32Array([0.6, 0.6, 0.61]), 1.5), "no critical hit seen: no figure")
	_check.call(not HackingUpgrades.can_follow_critical(hits, 0.0), "no known multiplier: no figure")
	var chain := _chain()
	var stronger := HackingUpgrades.apply(chain, {"breach_critical_multiplier": {"ratio": 1.12, "added": 0.18}})
	var top: float = Array(stronger.streams.P.multipliers).max()
	_check.call(absf(top - 0.606 * (1.0 + 1.5 * 1.12)) < 0.01, "a higher multiplier grows the critical hits")
	_check.call(chain.streams.P.multipliers.size() == 100 and absf(Array(chain.streams.P.multipliers).max() - 1.515) < 0.01, "the measures stay as they were")
	var likelier := HackingUpgrades.apply(chain, {"breach_critical_chance": {"ratio": 1.1, "added": 0.1}})
	var list: PackedFloat32Array = likelier.streams.P.multipliers
	var count := 0
	for value: float in list:
		if value > 1.0:
			count += 1
	_check.call(absf(float(count) / list.size() - 0.2) < 0.02, "more chance means more critical hits")


func _test_advice() -> void:
	var chain := _chain()
	var model := HackingModel.new(chain)
	var current: Dictionary = model.evaluate(chain.current)
	var corps_only := model.evaluate({"payload": {"corps": "P", "gov": ""}, "infection": {"corps": "I", "gov": ""}, "vulnerability": false})
	var split := model.evaluate({"payload": {"corps": "P", "gov": "P"}, "infection": {"corps": "I", "gov": ""}, "vulnerability": false})
	var rows: Array[Dictionary] = [current, corps_only, split]

	var objectives := HackingAdvice.objectives(chain)
	_check.call(objectives.size() == 4 and objectives[1].label == "Données" and objectives[3].key == "balanced", "the objectives come from the chain's targets")
	_check.call(HackingAdvice.best_row(rows, current, "xp") == corps_only, "the XP objective picks the most XP")
	_check.call(is_equal_approx(HackingAdvice.score(corps_only, "balanced", current), 0.0), "balanced gives nothing to a chain bringing nothing of one thing")
	_check.call(is_equal_approx(HackingAdvice.score(current, "balanced", current), 1.0), "the current chain is balanced's reference")
	var lopsided := current.duplicate(true)
	lopsided.current = false
	lopsided.xp_rate = current.xp_rate * 2.0
	lopsided.targets.corps.reward_rate = current.targets.corps.reward_rate * 2.0
	lopsided.targets.gov.reward_rate = current.targets.gov.reward_rate * 0.5
	var even := current.duplicate(true)
	even.current = false
	even.xp_rate = current.xp_rate * 1.2
	even.targets.corps.reward_rate = current.targets.corps.reward_rate * 1.2
	even.targets.gov.reward_rate = current.targets.gov.reward_rate * 1.2
	var choices: Array[Dictionary] = [current, lopsided, even]
	_check.call(HackingAdvice.best_row(choices, current, "balanced") == even, "balanced prefers a gain on everything to doubling at another's expense")
	var only_lopsided: Array[Dictionary] = [current, lopsided]
	_check.call(HackingAdvice.best_row(only_lopsided, current, "balanced") == current, "balanced never halves something, whatever it gains")
	_check.call(HackingUpgrades.grouped(26113829114.0) == "26 113 829 114" and HackingUpgrades.grouped(405.0) == "405" and HackingUpgrades.grouped(1000.0) == "1 000", "large numbers read properly")
	var slightly := current.duplicate(true)
	slightly.current = false
	slightly.xp_rate = current.xp_rate * 1.005
	var noise: Array[Dictionary] = [current, slightly]
	_check.call(HackingAdvice.best_row(noise, current, "xp") == current, "a tiny gain is not worth rewiring")

	var text := HackingAdvice.connection_text(chain, current, corps_only)
	_check.call(text.contains("Payload critique : débrancher d'Infiltrer Gouvernement") and text.contains("Produit d'infection : débrancher d'Infiltrer Gouvernement"), "the advice says what to unplug, with the game's names")
	var no_infection := model.evaluate({"payload": {"corps": "P", "gov": "P"}, "infection": {"corps": "", "gov": ""}, "vulnerability": false})
	_check.call(HackingAdvice.connection_text(chain, current, no_infection).contains("Débranchez aussi Produit d'infection"), "taking the infection off also frees its power")
	var why := HackingAdvice.why_text(chain, current, corps_only)
	_check.call(why.contains("Infiltrer Entreprises passe du niveau 7 au niveau") and why.contains("Infiltrer Gouvernement ne reçoit plus"), "the advice says why")
	var effects := HackingAdvice.effects(chain, current, corps_only)
	_check.call(effects.gains.contains("XP +") and effects.drawbacks.contains("Renseignements -100 %"), "the advice gives the gain and the drawback")
	_check.call(HackingAdvice.effects(chain, current, current).drawbacks == "aucun", "no drawback is said plainly")
	var own := HackingAdvice.effects(chain, current, current, PackedStringArray(["Dégâts Payload -40 %"]))
	_check.call(own.drawbacks == "Dégâts Payload -40 %", "the game's own drawback shows even when the result is a gain")


func _test_trial_without_forecast() -> void:
	var observer := Observer.new()
	var window := TrialWindow.new()
	var tracker := {"type": "any", "window": window, "getters": {}}
	var profile := {"damage_rate": 30.0, "infection_rate": 0.0, "vulnerability": 0.234, "breach_variation": 0, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0, "signature": "v"}
	_check.call(observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "without a forecast, a real trial decides")
	_check.call(not observer._may_work(tracker, profile, {"level": 8, "max_level": 8}), "a trial never goes above the highest level")
	var stealth := profile.duplicate()
	stealth.vulnerability = 0.0
	stealth.breach_variation = 1
	stealth.signature = "s"
	_check.call(observer._may_work(tracker, stealth, {"level": 7, "max_level": 8}), "a mechanic never measured does not block a trial")
	var weak := profile.duplicate()
	weak.vulnerability = 0.0
	weak.damage_rate = 11.0
	weak.signature = "w"
	_check.call(not observer._may_work(tracker, weak, {"level": 7, "max_level": 8}), "when the forecast is sure of a failure, no trial")
	var nothing := profile.duplicate()
	nothing.vulnerability = 0.0
	nothing.damage_rate = 0.0
	nothing.signature = "n"
	_check.call(not observer._may_work(tracker, nothing, {"level": 7, "max_level": 8}), "without any damage, no trial")
	window.free()
	observer.free()
