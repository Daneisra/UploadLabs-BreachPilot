extends RefCounted
## The advisor on chains it has never seen, and on values measured in game: 231.1 hack power split
## between the launcher and the infection gave 127.11 and 57.78, Government level 7 took 4.59 s with
## half the infection, and critical hits were 2.5 normal hits.

const ADVISOR := "res://mods-unpacked/Daneisra-BreachPilot/features/hacking_advisor/"
const HackingModel := preload(ADVISOR + "hacking_model.gd")
const HackingChain := preload(ADVISOR + "hacking_chain.gd")
const HackingGraph := preload(ADVISOR + "hacking_graph.gd")
const HackingUpgrades := preload(ADVISOR + "hacking_upgrades.gd")
const HackingAdvice := preload(ADVISOR + "hacking_advice.gd")
const HitLog := preload(ADVISOR + "hit_log.gd")
const HackingAdvisor := preload(ADVISOR + "hacking_advisor.gd")
const AdvisorPanel := preload(ADVISOR + "advisor_panel.gd")
const AdvisorTrials := preload(ADVISOR + "advisor_trials.gd")
const Observer := preload("res://mods-unpacked/Daneisra-BreachPilot/features/threat_manager/threat_observer.gd")
const Regulator := preload("res://mods-unpacked/Daneisra-BreachPilot/features/threat_manager/threat_regulator.gd")
const SaLog := preload("res://mods-unpacked/Daneisra-BreachPilot/core/sa_log.gd")
const Classifier := preload("res://mods-unpacked/Daneisra-BreachPilot/features/threat_manager/breach_classifier.gd")

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


class TimedWindow extends FakeBreach:
	var time := 6.0
	func get_max_firewall(_level: int) -> float: return 300.0
	func get_max_breach(_level: int) -> float: return 500.0
	func get_max_time(_level: int) -> float: return time


class TrialWindow extends FakeBreach:
	func get_max_firewall(_level: int) -> float: return 300.0
	func get_max_breach(_level: int) -> float: return 300.0


## Every fifth level is longer and pays ten times more, like the game's elite levels.
class EliteWindow extends FakeBreach:
	func get_max_firewall(level: int) -> float: return 50.0 * level
	func get_max_breach(level: int) -> float: return 50.0 * level
	func get_max_time(level: int) -> float: return 12.0 if level % 5 == 0 else 6.0
	func get_reward(level: int) -> float: return 4.0 * pow(1.5, level) * (10.0 if level % 5 == 0 else 1.0)
	func get_experience_reward(level: int) -> float: return pow(2.0, level) * (10.0 if level % 5 == 0 else 1.0)


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
	_test_profit_choice()
	_test_profitable_level_in_panel()
	_test_refresh_state()
	_test_balanced_trade()
	_test_reliability()
	_test_chain_search()
	_test_recommendation_card()
	_test_trials()
	_test_english()
	_test_stealth()
	_test_target_rules()
	_test_infection_measure()
	_test_infection_model()


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
	log.add("corps", "a", {"event": "success", "level": 8, "complete": true, "used": 5.0, "damage_rate": 100.0, "interval": 1.0, "vulnerability": 0.25, "hits": PackedFloat32Array([125.0, 250.0])})
	log.add("corps", "a", {"event": "failure_power", "level": 8, "complete": true, "damage_rate": 100.0, "vulnerability": 0.25})
	log.add("corps", "a", {"event": "success", "level": 8, "complete": false, "used": 9.0, "damage_rate": 100.0, "hits": PackedFloat32Array([999.0])})
	var kept := log.multipliers("a")
	_check.call(kept.size() == 2 and is_equal_approx(kept[0], 1.0) and is_equal_approx(kept[1], 2.0), "hits are kept relative to the announcement, without vulnerability")
	var stats := log.attack_stats("corps", "a", 8, HitLog.power_key(100.0, 0.0))
	_check.call(stats.attacks == 2 and stats.successes == 1 and is_equal_approx(stats.used, 5.0), "only complete attacks count")
	_check.call(log.attack_stats("corps", "a", 8, HitLog.power_key(130.0, 0.0)).attacks == 0, "attacks at another power do not compare")
	_check.call(is_equal_approx(log.last_vulnerability("corps"), 0.25) and log.last_vulnerability("other") == 0.0, "the last attack's vulnerability is kept")
	_check.call(log.multipliers("b").is_empty(), "another chain starts a new measure")
	var faster := HitLog.new()
	faster.add("corps", "f", {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "interval": 0.5, "hits": PackedFloat32Array([50.0])})
	_check.call(is_equal_approx(faster.multipliers("f")[0], 1.0), "a shot is a rate times the interval")
	_check.call(log.multipliers("a").size() == 2, "the old chain's measures stay")
	for index: int in HitLog.MAX_CHAINS + 2:
		log.add("corps", "other%d" % index, {"event": "success", "level": 1, "complete": true, "damage_rate": 1.0})
	_check.call(log.multipliers("a").is_empty(), "the oldest chains make room")
	var many := HitLog.new()
	var big := PackedFloat32Array()
	big.resize(HitLog.MAX_HITS + 50)
	big.fill(10.0)
	many.add("corps", "x", {"event": "success", "level": 1, "complete": true, "damage_rate": 10.0, "interval": 1.0, "hits": big})
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
	log.add("zz_alpha", key, {"event": "success", "level": 1, "complete": true, "used": 2.0, "damage_rate": 50.0, "interval": 1.0, "hits": hits})
	var no_infection := HackingChain.read(desktop, {"zz_alpha": 1.0}, log, null, null)
	_check.call(HackingModel.new(no_infection).evaluate(no_infection.current).insufficient.has(HackingModel.REASON_HITS), "infection on the chain gives no figure until it is measured")
	var gains := PackedFloat32Array()
	for index: int in HackingModel.MIN_PULSES:
		gains.append(20.0)
	log.add("zz_alpha", key, {"event": "success", "level": 1, "complete": true, "used": 2.0, "damage_rate": 50.0, "infection_rate": 20.0, "interval": 1.0, "hits": PackedFloat32Array(), "infection_growth": 0.0, "infection_gains": gains}, HackingGraph.chain_key(graph, alpha, null, HackingGraph.INFECTION_SLOT))

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

	var quick := _chain()
	quick.targets.corps.interval = 0.5
	quick.targets.gov.interval = 0.5
	var quick_model := HackingModel.new(quick)
	var scales: Dictionary = quick_model._scales("corps", quick.current)
	_check.call(is_equal_approx(scales.hit * quick_model._shot_time("corps"), 104.865 * 0.5), "a rate gives less per shot when shots come sooner")
	var sped_up := _chain()
	sped_up.interval_factor = 1.25
	var sped_model := HackingModel.new(sped_up)
	_check.call(is_equal_approx(sped_model._interval("corps"), 0.8) and is_equal_approx(sped_model._shot_time("corps"), 1.0), "buying speed makes shots come sooner, each one the same")

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

	var growing := _chain()
	growing.stealth_mask = 1
	growing.streams.I.variation = 2
	var hidden := HackingModel.new(growing).evaluate(growing.current)
	_check.call(hidden.insufficient.has(HackingModel.REASON_UNMEASURED) and hidden.targets.gov.level == -1, "what was never measured is never estimated")
	var unnamed := _chain()
	unnamed.streams.P.variation = 1
	_check.call(HackingModel.new(unnamed).evaluate(unnamed.current).insufficient.has(HackingModel.REASON_UNMEASURED), "a game that does not name stealth leaves it unknown")

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


func _changed(current: Dictionary, xp: float, corps: float, gov: float) -> Dictionary:
	var row := current.duplicate(true)
	row.current = false
	row.xp_rate = current.xp_rate * xp
	row.targets.corps.reward_rate = current.targets.corps.reward_rate * corps
	row.targets.gov.reward_rate = current.targets.gov.reward_rate * gov
	return row


## Balanced takes the same trade as the regulation: up to 5 % less of one thing for 10 % more of another.
func _test_balanced_trade() -> void:
	var model := HackingModel.new(_chain())
	var current: Dictionary = model.evaluate(_chain().current)
	var trade := _changed(current, 1.0, 2.3, 0.97)
	_check.call(HackingAdvice.best_row([current, trade] as Array[Dictionary], current, "balanced") == trade, "balanced gives up 3 % of one resource for 130 % more of another")
	_check.call(HackingAdvice.best_row([current, _changed(current, 1.0, 2.3, 0.94)] as Array[Dictionary], current, "balanced") == current, "but not 6 %")
	_check.call(HackingAdvice.best_row([current, _changed(current, 1.0, 1.08, 0.99)] as Array[Dictionary], current, "balanced") == current, "nor for only 8 % more")
	var even := _changed(current, 1.04, 1.04, 1.04)
	_check.call(HackingAdvice.best_row([current, trade, even] as Array[Dictionary], current, "balanced") == trade, "the larger average gain wins")
	_check.call(absf(HackingAdvice.gain(even, current, "balanced") - 0.04) < 1e-6, "balanced's gain is the average change")
	_check.call(HackingAdvice.best_row([current, trade] as Array[Dictionary], current, "gov") == current, "an objective naming a resource still keeps it")
	var refused := _changed(current, 1.25, 1.0, 0.6)
	_check.call(HackingAdvice.is_refused_trade(refused, current, "balanced") and not HackingAdvice.is_refused_trade(refused, current, "xp") and not HackingAdvice.is_refused_trade(trade, current, "balanced"), "a refused trade is told apart from a loss")
	var advisor := HackingAdvisor.new()
	advisor._chain = _chain()
	advisor._current = current
	advisor._objective = HackingAdvice.BALANCED
	var cell := advisor._purchase_gain(refused)
	_check.call(cell.begins_with("compromis : ") and cell.contains("Renseignements -40 %") and not cell.contains("-100"), "a purchase balanced refuses says what it costs, not -100 %%: %s" % cell)
	advisor._upgrade_rows = [{"upgrade": {"name": "Dégâts Payload", "affordable": true, "resource": "points", "cost": 1.0, "cost_text": "1 point", "held": 12.0, "changes": {}}, "row": refused}]
	advisor._rows = [current]
	advisor._model = HackingModel.new(_chain())
	var card := advisor._card()
	var said := false
	for line: Dictionary in card:
		said = said or (line.text.contains("Dégâts Payload donnerait XP +25 %") and line.text.contains("Renseignements -40 %"))
	_check.call(said, "and the card names the trade it refused")
	advisor.free()


func _test_reliability() -> void:
	var chain := _chain()
	chain.streams.I.targets = ["corps"]
	chain.current.infection.gov = ""
	var model := HackingModel.new(chain)
	var current: Dictionary = model.evaluate(chain.current)
	var sure := HackingAdvice.reliability(chain, current)
	_check.call(sure.level == 2 and sure.reasons.contains("mesuré"), "what the chain does today is measured: %s" % str(sure))
	var moved := model.evaluate({"payload": {"corps": "P", "gov": "P"}, "infection": {"corps": "I", "gov": "I"}, "vulnerability": false})
	var estimated := HackingAdvice.reliability(chain, moved)
	_check.call(estimated.level <= 1 and estimated.reasons.contains("Produit d'infection vers Infiltrer Gouvernement"), "a stream sent where it never attacked is estimated: %s" % str(estimated))
	var shaky := moved.duplicate(true)
	shaky.targets.gov.chance = 0.85
	shaky.targets.gov.level = 7
	var weak := HackingAdvice.reliability(chain, shaky)
	_check.call(weak.level == 0 and weak.text == "faible" and weak.reasons.contains("85 %"), "and a level that may slip on top of it is weak")
	var steps := HackingAdvice.steps(chain, current, moved)
	_check.call(steps.size() == 1 and steps[0] == "Produit d'infection : brancher vers Infiltrer Gouvernement", "one step per cable: %s" % str(steps))


## A chain too large to try whole is searched change after change, until nothing better turns up.
func _test_chain_search() -> void:
	var big := _chain()
	for index: int in 3:
		big.targets["extra%d" % index] = _target("Extra %d" % index, "Extra", 100.0, 100.0)
		big.current.payload["extra%d" % index] = ""
		big.current.infection["extra%d" % index] = ""
	var advisor := HackingAdvisor.new()
	advisor._chain = big
	advisor._model = HackingModel.new(big)
	advisor._objective = HackingAdvice.XP
	_check.call(advisor._model.searches(), "a chain this large is searched")
	advisor._pending = advisor._model.scenarios()
	var first_round: int = advisor._pending.size()
	for scenario: Dictionary in advisor._pending:
		advisor._seen[str(scenario)] = true
	advisor._search_base = big.current
	var evaluated := 0
	while true:
		while not advisor._pending.is_empty():
			advisor._rows.append(advisor._model.evaluate(advisor._pending.pop_back()))
			evaluated += 1
		if not advisor._next_round():
			break
	var current := advisor._current_row()
	var one_change := HackingAdvice.best_row(advisor._rows.slice(0, first_round), current, HackingAdvice.XP)
	var found := HackingAdvice.best_row(advisor._rows, current, HackingAdvice.XP)
	_check.call(found.xp_rate >= one_change.xp_rate and advisor._rounds >= 1, "the search finds at least the best single change, then goes on: %d rounds" % advisor._rounds)
	_check.call(advisor._rounds <= HackingModel.MAX_SEARCH_ROUNDS and evaluated <= first_round * (HackingModel.MAX_SEARCH_ROUNDS + 1), "and stays bounded: %d chains" % evaluated)
	var differences := 0
	for kind: String in ["payload", "infection"]:
		for key: String in big.targets:
			if found.scenario[kind][key] != big.current[kind][key]:
				differences += 1
	_check.call(differences >= 2, "several changes add up: %d" % differences)
	var keys := {}
	for row: Dictionary in advisor._rows:
		keys[str(row.scenario)] = true
	_check.call(keys.size() == advisor._rows.size(), "no chain is tried twice")
	advisor.free()


## The recommendation comes first, with its gain, drawbacks and reliability; the tables fold away.
func _test_recommendation_card() -> void:
	var chain := _chain()
	var advisor := HackingAdvisor.new()
	advisor._chain = chain
	advisor._model = HackingModel.new(chain)
	advisor._objective = HackingAdvice.XP
	for scenario: Dictionary in advisor._model.scenarios():
		advisor._rows.append(advisor._model.evaluate(scenario))
	advisor._current = advisor._model.evaluate(chain.current)
	var card := advisor._card()
	var texts := PackedStringArray()
	for line: Dictionary in card:
		texts.append(line.text)
	var all := "\n".join(texts)
	_check.call(card[0].kind == "title" and (all.contains("Meilleur branchement pour XP") or all.contains("Gardez votre branchement")), "the card opens on the recommendation: %s" % all)
	_check.call(all.contains("Fiabilité : "), "with its reliability")
	if all.contains("Meilleur branchement"):
		_check.call(all.contains("Gain estimé : ") and all.contains("Inconvénients : ") and all.contains("   1. "), "its gain, drawbacks and steps")
	advisor._current.insufficient = PackedStringArray([HackingModel.REASON_HITS])
	_check.call(advisor._card()[0].text.begins_with("Données insuffisantes"), "without a measure, the card says so first")

	var panel := AdvisorPanel.new()
	var options: Array[Dictionary] = [{"key": "xp", "label": "XP"}]
	panel.show_advice(options, "xp", func(_key: String) -> void: pass, card, {"rows": [["a"], ["b"]], "kinds": ["header", ""]}, {"rows": [], "kinds": []}, "note")
	_check.call(panel._card.get_child_count() == card.size() and not panel._details.visible, "the details start folded")
	panel._on_toggle()
	_check.call(panel._details.visible and panel._toggle.text == "Masquer le détail des calculs", "a click unfolds them")
	panel.show_advice(options, "xp", func(_key: String) -> void: pass, card, {"rows": [["a"], ["b"]], "kinds": ["header", ""]}, {"rows": [], "kinds": []}, "note")
	_check.call(panel._details.visible, "and they stay open on the next calculation")
	panel.show_message("Calcul en cours…")
	_check.call(not panel._toggle.visible and panel._summary.visible, "a message hides the card")
	panel.free()
	advisor.free()


## The whole panel in English: no French word, no value left unfilled, no raw id, and the game's own names kept.
func _test_english() -> void:
	var I18n: GDScript = load("res://mods-unpacked/Daneisra-BreachPilot/core/i18n.gd")
	I18n.forced = "en"
	var texts := PackedStringArray()
	var chain := _chain()
	# The game in English gives its own names in English.
	for key: String in chain.targets:
		chain.targets[key].label = "Breach %s" % key.capitalize()
		chain.targets[key].reward_name = "%s Data" % key.capitalize()
	var advisor := HackingAdvisor.new()
	advisor._chain = chain
	advisor._model = HackingModel.new(chain)
	for objective: String in [HackingAdvice.XP, HackingAdvice.BALANCED]:
		advisor._objective = objective
		advisor._rows.clear()
		for scenario: Dictionary in advisor._model.scenarios():
			advisor._rows.append(advisor._model.evaluate(scenario))
		advisor._current = advisor._model.evaluate(chain.current)
		var richer := advisor._current.duplicate(true)
		richer.xp_rate *= 1.3
		for target: Dictionary in richer.targets.values():
			target.reward_rate *= 1.3
		advisor._upgrade_rows = [
			{"upgrade": {"name": "Payload Damage", "affordable": true, "resource": "points", "cost": 1.0, "cost_text": "1 hack point", "held": 4.0, "changes": {}}, "row": richer},
			{"upgrade": {"name": "Breach Speed", "affordable": false, "resource": "points", "cost": 10.0, "cost_text": "10 hack points", "held": 4.0, "changes": {}}, "row": richer},
		]
		var desktop := _trial_desktop()
		var data := TrialTable.new()
		data.windows = _trial_windows()
		data.windows.bank.description = "Gets Tokens when it wins."
		data.windows.bank.name = "Breach Bank"
		data.resources = {"vulnerability": {"name": "Vulnerability"}, "infection_damage": {"name": "Infection Damage"}, "payload_damage": {"name": "Payload Damage"}}
		var globals := FakeGlobalsTable.new()
		globals.unlocks = {"research.bank": true}
		advisor._trials = AdvisorTrials.read(HackingGraph.snapshot(desktop), data, globals)
		for line: Dictionary in advisor._card():
			texts.append(line.text)
		for table: Dictionary in [advisor._connections_table(), advisor._purchases_table()]:
			for row: Array in table.rows:
				texts.append(" | ".join(row))
		texts.append(advisor._note())
		globals.free()
		data.free()
		_free_desktop(desktop)
	advisor._current.insufficient = PackedStringArray([HackingModel.REASON_HITS, HackingModel.REASON_UNMEASURED])
	for line: Dictionary in advisor._card():
		texts.append(line.text)
	var panel := AdvisorPanel.new()
	panel.show_message(I18n.t("panel.computing"))
	texts.append_array([panel._title.text, panel._close.text, panel._toggle.text, panel._summary.text])
	panel.free()
	advisor.free()
	var all := "\n".join(texts)
	var french := RegEx.create_from_string("[éèàçêùôî«»]|\\b(de|du|des|le|la|les|vers|est|pas|vous|votre|aucun|aucune|Achat|Fiabilité|Gardez|Données|niv)\\b")
	var hit := french.search(all)
	_check.call(hit == null, "nothing French in the English panel: %s" % (all.substr(maxi(hit.get_start() - 200, 0), 400).c_escape() if hit != null else ""))
	_check.call(not all.contains("{") and not all.contains("}"), "every value is filled in")
	var raw := PackedStringArray()
	for id: String in I18n.TABLES.en:
		if all.contains(id):
			raw.append(id)
	_check.call(raw.is_empty(), "no raw id shows: %s" % ", ".join(raw))
	_check.call(all.contains("Things to try") and all.contains("Reliability: ") and all.contains("Recommended purchase: Payload Damage") and all.contains("Not enough data to advise:"), "the English card reads as such")
	_check.call(all.contains("Breach Bank is not placed yet: Gets Tokens when it wins"), "a node's name and description stay the game's")
	I18n.forced = "fr"


class FakeGlobalsTable extends Node:
	var unlocks := {}


## A chain like the one of 2026-11-03: two nodes without power, a target with no damage, empty inputs.
func _trial_desktop() -> FakeDesktop:
	var desktop := FakeDesktop.new()
	var nodes: Array[Node] = [
		_node("src", [_slot("S", "hack_power", 300.0, "", ["F1", "F4"])]),
		_node("launcher", [_slot("F1", "hack_power", 150.0, "S"), _slot("L", "payload_damage", 110.0, "", ["corps_p", "gov_p"])]),
		_node("virus", [_slot("F2", "hack_power", 0.0), _slot("V", "infection_damage", 0.0)]),
		_node("injector", [_slot("F3", "hack_power", 0.0), _slot("J", "vulnerability", 0.0)]),
		_node("spare", [_slot("F4", "hack_power", 150.0, "S"), _slot("X", "payload_damage", 50.0)]),
		_node("splitter", [_slot("F5", "hack_power", 150.0, "S"), _slot("Y1", "payload_damage", 50.0, "", ["elsewhere"]), _slot("Y2", "payload_damage", 50.0)]),
		_node("modifier", [_slot("M1", "vulnerability", 0.0), _slot("M2", "vulnerability", 0.0, "", ["elsewhere"])]),
		_breach("corps", "L", ""),
		_breach("gov", "L", ""),
		_breach("anon", "", ""),
		_node("collector", [_slot("C", "reward", 0.0)]),
	]
	for node: Node in nodes:
		desktop.windows.add_child(node)
	return desktop


func _trial_windows() -> Dictionary:
	var windows := {}
	for type: String in ["src", "launcher", "virus", "injector", "spare", "splitter", "modifier", "corps", "gov", "anon"]:
		windows[type] = {"name": type.capitalize(), "category": "hacking", "requirement": []}
	windows["bank"] = {"name": "Infiltrer Banque", "category": "hacking", "requirement": ["research.bank"], "description": "Récupère des Jetons si elle réussit."}
	windows["locked"] = {"name": "Verrouillé", "category": "hacking", "requirement": ["research.locked"]}
	windows["collector"] = {"name": "Collecteur", "category": "other", "requirement": []}
	windows["shop"] = {"name": "Boutique", "category": "other", "requirement": []}
	return windows


class TrialTable extends FakeTable:
	var windows := {}
	var resources := {"vulnerability": {"name": "Vulnérabilité"}, "infection_damage": {"name": "Dégâts d'infection"}, "payload_damage": {"name": "Dégâts Payload"}}


func _test_trials() -> void:
	var desktop := _trial_desktop()
	var data := TrialTable.new()
	data.windows = _trial_windows()
	var globals := FakeGlobalsTable.new()
	globals.unlocks = {"research.bank": true, "research.locked": false}
	var trials := AdvisorTrials.read(HackingGraph.snapshot(desktop), data, globals)
	var keys := PackedStringArray()
	var texts := {}
	for trial: Dictionary in trials:
		keys.append(trial.key)
		texts[trial.key] = trial.text
	_check.call(keys.has("no_power|virus") and keys.has("no_power|injector"), "nodes without power are found: %s" % ", ".join(keys))
	_check.call(keys.has("no_damage|anon") and texts["no_damage|anon"].contains("Anon ne reçoit aucun dégât"), "and a target that never attacks")
	_check.call(keys.has("unused|spare") and texts["unused|spare"].contains("Dégâts Payload"), "and an output plugged into nothing")
	_check.call(texts["unused|spare"].contains("sa sortie") and texts.get("unused|splitter", "").contains("une de ses sorties"), "a split with one free output says so: %s" % texts.get("unused|splitter", ""))
	_check.call(keys.has("empty|vulnerability") and texts["empty|vulnerability"].contains("Vulnérabilité est vide sur Corps, Gov") and texts["empty|vulnerability"].contains("Injector") and texts["empty|vulnerability"].contains("Alimentez-le"), "an empty input another node could fill: %s" % texts.get("empty|vulnerability", ""))
	_check.call(not texts.get("empty|vulnerability", "").contains("Modifier") and not texts.get("empty|vulnerability", "").contains("Anon"), "an idle input in the middle makes nothing, and a target without damage is told on its own")
	_check.call(keys.has("empty|infection_damage") and texts["empty|infection_damage"].contains("Virus"), "the infection a node could bring once powered")
	_check.call(keys.has("new|bank") and texts["new|bank"].contains("Récupère des Jetons si elle réussit") and texts["new|bank"].contains("Add Node"), "a node unlocked but not placed, with what the game says")
	_check.call(not keys.has("new|locked") and not keys.has("new|shop") and not keys.has("new|corps"), "neither what is locked, nor what is not hacking, nor what is placed")
	_check.call(trials[0].priority == AdvisorTrials.IDLE and trials[-1].key == "new|bank", "what can be done with the nodes already there comes first")
	for trial: Dictionary in trials:
		_check.call(not trial.text.contains("%"), "no figure in a suggestion: %s" % trial.text)
	_check.call(AdvisorTrials.read({"windows": []}, null, null).is_empty(), "without the game's tables, nothing is suggested")

	var advisor := HackingAdvisor.new()
	advisor._chain = _chain()
	advisor._model = HackingModel.new(advisor._chain)
	advisor._objective = HackingAdvice.XP
	for scenario: Dictionary in advisor._model.scenarios():
		advisor._rows.append(advisor._model.evaluate(scenario))
	advisor._current = advisor._model.evaluate(advisor._chain.current)
	advisor._trials = trials
	var richer := advisor._current.duplicate(true)
	richer.xp_rate *= 1.3
	advisor._upgrade_rows = [{"upgrade": {"name": "Dégâts Payload", "affordable": false, "resource": "points", "cost": 10.0, "cost_text": "10 points", "held": 4.0, "changes": {}}, "row": richer}]
	var card := advisor._card()
	var shown := 0
	var titled := false
	for line: Dictionary in card:
		titled = titled or line.text == "À essayer"
		shown += 1 if line.text.begins_with("• ") else 0
	_check.call(titled and shown == AdvisorTrials.SHOWN, "the card keeps a short list: %d" % shown)
	_check.call(advisor._note().contains("Autres pistes à essayer") and advisor._note().contains("Infiltrer Banque"), "the others wait in the details")
	_check.call(advisor._saving_trial().text.contains("Il vous manque 6") and advisor._saving_trial().text.contains("+30 %"), "a purchase worth saving for: %s" % advisor._saving_trial().get("text", ""))
	var state: String = advisor._state_of(advisor._chain, [], trials)
	_check.call(state != advisor._state_of(advisor._chain, [], trials.slice(1)), "a node powered or placed refreshes the panel")
	advisor.free()
	globals.free()
	data.free()
	_free_desktop(desktop)


## A recalculation stutters: only a gesture of the player may start one.
func _test_refresh_state() -> void:
	var advisor := HackingAdvisor.new()
	var upgrades: Array[Dictionary] = [{"name": "Recherche", "cost": 100.0, "held": 50.0, "affordable": false}]
	var chain := _chain()
	var state: String = advisor._state_of(chain, upgrades)

	var same := _chain()
	same.targets.corps.level = 8
	same.targets.corps.interval = 0.95
	same.targets.gov.vulnerability = 0.24
	same.targets.gov.real = {"attacks": 500, "successes": 500, "used": 2000.0}
	same.streams.P.multipliers.append(0.7)
	var grown: Array[Dictionary] = [{"name": "Recherche", "cost": 100.0, "held": 51.0, "affordable": false}]
	_check.call(advisor._state_of(same, grown) == state, "what moves by itself does not recalculate")

	var rewired := _chain()
	rewired.current.infection.gov = ""
	_check.call(advisor._state_of(rewired, upgrades) != state, "a new connection recalculates")
	var stronger := _chain()
	stronger.streams.P.production = 300.0
	_check.call(advisor._state_of(stronger, upgrades) != state, "new power recalculates")
	var payable: Array[Dictionary] = [{"name": "Recherche", "cost": 100.0, "held": 100.0, "affordable": true}]
	_check.call(advisor._state_of(chain, payable) != state, "a purchase becoming possible recalculates")
	var measuring := _chain()
	measuring.streams.P.multipliers = PackedFloat32Array([0.6])
	_check.call(advisor._state_of(measuring, upgrades) != state, "a measure becoming sufficient recalculates")
	_check.call(advisor._state_of({"error": "no_target"}, upgrades).ends_with("|no_target") and advisor._state_of({"error": "no_target"}, upgrades).begins_with("fr:"), "an error is a state too, in its language")
	advisor.free()


## Figures from the log of 2026-11-01, with Ghost on both streams at 2775.97 and 1669.05 per second.
func _ghost_hits() -> PackedFloat32Array:
	var hits := PackedFloat32Array()
	for index: int in 300:
		var hit := 0.33
		if index % 3 == 0:
			hit *= 2.0
		if index % 5 == 0:
			hit *= 2.68
		hits.append(hit)
	return hits


## Bought at the same power, more attack time must reopen the levels it brings within reach.
func _test_target_rules() -> void:
	var observer := Observer.new()
	var window := TimedWindow.new()
	var tracker := {"type": "any", "window": window, "getters": {}, "chain_key": "chain"}
	var hits := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "interval": 1.0, "hits": PackedFloat32Array()}
	for index: int in HackingModel.MIN_HITS:
		hits.hits.append(100.0)
	observer.hit_log().add("any", "chain", hits)
	var profile := {"damage_rate": 100.0, "announced_rate": 100.0, "infection_rate": 0.0, "vulnerability": 0.0, "breach_variation": 0, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0}
	var attack := {"level": 7, "max_level": 8}
	profile.signature = observer._with_target_rules(tracker, "power")
	var before: String = profile.signature
	_check.call(not observer._may_work(tracker, profile, attack), "six seconds are too short for this level")
	_check.call(observer._with_target_rules(tracker, "power") == before, "the same target keeps the same situation")
	window.time = 8.0
	profile.signature = observer._with_target_rules(tracker, "power")
	_check.call(profile.signature != before, "more attack time is a new situation")
	_check.call(observer._may_work(tracker, profile, attack), "and the level it brings within reach is tried at once")
	var blind := {"type": "any", "window": window, "getters": {"get_max_time": false}}
	_check.call(observer._with_target_rules(blind, "power") == "power", "without the game's values, power alone tells")
	window.free()
	observer.free()


func _infection_sample(time: float, count: float, breached: float) -> Dictionary:
	return {
		"instance_id": 1, "level": 1, "max_level": 5, "time": time, "max_time": 10.0, "detected": true, "paused": false,
		"firewall": 100.0, "max_firewall": 100.0, "breached": breached, "max_breach": 1000000.0, "damage_rate": 100.0, "breach_variation": 1,
		"infection_count": count, "infection_rate": 20.0, "infection_variation": 3, "vulnerability": 0.0, "tick_speed": 0.05, "now_usec": 0,
	}


## An attack as the game plays it with a growing infection fed by the hits: nothing tells the node behind it.
func _played_attack(growth: float, share: float, hits: Array) -> Dictionary:
	var classifier := Classifier.new()
	var count := 0.0
	var breached := 0.0
	var time := 10.0
	var index := 0
	var events: Array[Dictionary] = []
	classifier.observe(_infection_sample(time, 0.0, 0.0))
	for tick: int in 100:
		time -= 0.05
		count *= exp(growth * 0.05)
		if tick % 15 == 0:
			var hit: float = hits[index % hits.size()]
			index += 1
			count += hit * share
			breached += hit
		breached += count * 0.05
		classifier.observe(_infection_sample(time, count, breached))
	events = classifier.on_breached(_infection_sample(time, count, breached))
	return events[0]


func _test_infection_measure() -> void:
	var event := _played_attack(log(1.1), 0.2, [100.0, 200.0, 540.0])
	_check.call(absf(event.infection_growth - log(1.1)) < 0.002, "growth is measured tick by tick: %.4f" % event.infection_growth)
	_check.call(event.infection_gains.size() == 7, "each shot's gain is seen: %d" % event.infection_gains.size())
	_check.call(absf(event.infection_gains[1] - 40.0) < 0.5 and absf(event.infection_gains[2] - 108.0) < 0.5, "and what it adds, beyond the growth")
	var still := _played_attack(0.0, 0.2, [100.0])
	_check.call(absf(still.infection_growth) < 0.0001 and still.infection_gains.size() == 7, "an infection that does not grow is measured as such")
	var none := Classifier.new()
	none.observe(_infection_sample(10.0, 0.0, 0.0))
	var dry: Dictionary = none.on_breached(_infection_sample(9.9, 0.0, 10.0))[0]
	_check.call(not dry.has("infection_gains"), "no infection, no measure")

	var log_of := HitLog.new()
	_check.call(log_of.infection("i").pulses == 0 and log_of.infection("i").follow == 0.0, "nothing measured yet")
	var following := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "infection_rate": 20.0, "interval": 1.0, "breach_variation": 1, "infection_variation": 3,
		"hits": PackedFloat32Array([50.0, 100.0, 270.0]), "infection_growth": log(1.1), "infection_gains": PackedFloat32Array([10.0, 20.0, 54.0])}
	log_of.add("t", "h", following, "i")
	var read := log_of.infection("i")
	_check.call(read.pulses == 3 and absf(read.growth - log(1.1)) < 0.0001, "the measure keeps gains and growth")
	_check.call(read.follow > 0.9 and read.follow < 1.1, "gains that spread like hits follow them: %.2f" % read.follow)
	_check.call(log_of.effects_seen("i") == 3 and log_of.effects_seen("h") == 1 and log_of.effects_seen("x") == 0, "each flow keeps the effects attacks ran with")
	var steady := following.duplicate()
	steady.infection_growth = 0.0
	steady.infection_gains = PackedFloat32Array([20.0, 20.0, 20.0])
	log_of.add("t", "h", steady, "j")
	_check.call(log_of.infection("j").follow == 0.0 and is_equal_approx(log_of.infection("j").level, 1.0), "gains that do not spread are a fixed amount")

	_check.call(HackingUpgrades.grouped(4603854016022367232.0) == "4.60e18", "numbers beyond whole ones stay readable: %s" % HackingUpgrades.grouped(4603854016022367232.0))
	_check.call(not HackingUpgrades.grouped(2.3e22).begins_with("-"), "and never turn negative")
	_check.call(HackingUpgrades.grouped(1e21) == "1.00e21" and HackingUpgrades.grouped(99999999999999992000000.0) == "1.00e23", "a power of ten keeps one figure before the point: %s" % HackingUpgrades.grouped(1e21))
	var observer := Observer.new()
	var target := FakeBreach.new()
	target.breach_damage = _slot("in", "breach_damage", 5.0)
	target.containers = [target.breach_damage, _slot("xp", "hack_experience", 33.5), _slot("data", "corporation_data", 101.0)]
	_check.call(observer._outputs(target) == "hack_experience:33.5:33.5,corporation_data:101.0:101.0", "what a target gives is read without its attack inputs: %s" % observer._outputs(target))
	_check.call(observer._outputs(null) == "", "no target, nothing read")
	for slot: Variant in target.containers:
		slot.free()
	target.free()
	observer.free()
	_check.call(HackingUpgrades.cost_text(1e30, "hack_points").ends_with("points de piratage"), "a huge cost is still plural")


## The log of 2026-11-02, Infecter Payload, Spread Infection and Ghost on both flows: 37946 announced, 7589 of infection,
## an infection growing about 10 % per second fed by 20 % of each real hit, hits of 6527, 13056 and critical ones.
func _spread_hits() -> PackedFloat32Array:
	var hits := PackedFloat32Array()
	for index: int in 300:
		var hit := 6527.0 / (37946.33 * 0.741)
		if index % 3 == 0:
			hit *= 2.0
		if index % 5 == 0:
			hit *= 3.4
		hits.append(hit)
	return hits


func _test_infection_model() -> void:
	var model := HackingModel.new({"time_factor": 1.0})
	var hits := _spread_hits()
	var measured := {"pulses": 100, "growth": log(1.1), "level": 0.6, "follow": 1.0}
	var cells: Array = [
		["Government 23, 18 of 18", {"firewall": 224454.5, "breach": 224454.5, "time": 9.0}, 0.8, 1.0, 6.86],
		["Corps 22, 22 of 23", {"firewall": 59854.6, "breach": 239418.4, "time": 9.0}, 0.8, 1.0, 6.85],
		["Government 24, 4 of 7", {"firewall": 336682.0, "breach": 336682.0, "time": 9.0}, 0.0, 0.79, -1.0],
	]
	for cell: Array in cells:
		var outcome := model.attack_outcome(cell[1], 37946.33 * 0.741, 7589.27 * 0.741, 1.0, hits, 0.741, true, true, measured)
		_check.call(outcome.chance >= cell[2] and outcome.chance <= cell[3], "%s as measured: %.2f" % [cell[0], outcome.chance])
		if cell[4] > 0.0:
			_check.call(absf(outcome.used - cell[4]) < 0.75, "%s lasts as measured: %.2f" % [cell[0], outcome.used])
	var wall := {"firewall": 0.0, "breach": 400000.0, "time": 9.0}
	var flat := measured.duplicate()
	flat.growth = 0.0
	var lesser := model.attack_outcome(wall, 0.0, 1000.0, 1.0, hits, 0.741, true, true, flat)
	var greater := model.attack_outcome(wall, 0.0, 1000.0, 1.0, hits, 0.741, true, true, measured)
	_check.call(greater.chance >= lesser.chance, "growth can only help")
	var shrinking := measured.duplicate()
	shrinking.growth = -1.0
	_check.call(model.attack_outcome(wall, 37946.33 * 0.741, 7589.27 * 0.741, 1.0, hits, 0.741, true, true, shrinking).chance <= greater.chance, "an infection that fades, unseen so far, is followed too")

	# A node nobody has ever seen, on the chain: blocked until attacks run with it, then counted.
	var chain := _chain()
	chain.stealth_mask = 1
	chain.streams.I.variation = 4
	_check.call(HackingModel.new(chain).evaluate(chain.current).insufficient.has(HackingModel.REASON_UNMEASURED), "no attack has shown this effect yet")
	chain.streams.I.effects_seen = 4
	chain.streams.I.infection = {"pulses": 3, "growth": log(1.1), "level": 1.0, "follow": 0.0}
	_check.call(HackingModel.new(chain).evaluate(chain.current).insufficient.has(HackingModel.REASON_HITS), "while it is measured, still no figure")
	chain.streams.I.infection.pulses = HackingModel.MIN_PULSES
	var row := HackingModel.new(chain).evaluate(chain.current)
	var plain := HackingModel.new(_chain()).evaluate(_chain().current)
	_check.call(row.insufficient.is_empty() and row.targets.gov.level >= plain.targets.gov.level, "once measured it counts, and growth gains levels")

	var follower := _chain()
	follower.streams.I.infection = {"pulses": 100, "growth": 0.0, "level": 0.6, "follow": 1.0}
	var before: float = HackingModel.new(follower)._scales("gov", follower.current).stack
	follower.payload_factor = 1.5
	_check.call(is_equal_approx(HackingModel.new(follower)._scales("gov", follower.current).stack, before * 1.5), "infection that follows the hits gains what the payload gains")
	follower.payload_factor = 1.0
	var off_payload: Dictionary = follower.current.duplicate(true)
	off_payload.payload.gov = ""
	_check.call(HackingModel.new(follower).evaluate(off_payload).insufficient.has(HackingModel.REASON_UNMEASURED), "without hits to follow, no figure")

	var desktop := _strange_desktop()
	var graph := HackingGraph.snapshot(desktop)
	for entry: Dictionary in graph.windows:
		if HackingGraph.is_target(entry.node):
			_check.call(HackingGraph.chain_key(graph, entry.node, null, HackingGraph.INFECTION_SLOT) != HackingGraph.chain_key(graph, entry.node, null), "the infection has its own measure")
			break
	_free_desktop(desktop)

	var observer := Observer.new()
	observer._stealth_mask = 1
	var attack := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "infection_rate": 20.0, "interval": 1.0, "breach_variation": 1, "infection_variation": 3, "hits": PackedFloat32Array(),
		"infection_growth": log(1.1), "infection_gains": PackedFloat32Array()}
	for index: int in HackingModel.MIN_HITS:
		attack.hits.append(100.0)
		attack.infection_gains.append(20.0)
	var window := TrialWindow.new()
	var tracker := {"type": "any", "window": window, "getters": {}, "chain_key": "chain", "infection_key": "bio"}
	var profile := {"damage_rate": 1.0, "announced_rate": 1.0, "infection_rate": 0.2, "vulnerability": 0.0, "breach_variation": 1, "infection_variation": 3, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0, "signature": "before"}
	_check.call(observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "without the infection's measure, a real trial decides")
	observer.hit_log().add("any", "chain", attack, "bio")
	profile.signature = "after"
	_check.call(not observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "once measured, a hopeless try is spared even with growth")
	var strong := profile.duplicate()
	strong.announced_rate = 100.0
	strong.infection_rate = 20.0
	strong.signature = "strong"
	_check.call(observer._may_work(tracker, strong, {"level": 7, "max_level": 8}), "and a level within reach is tried")
	window.free()
	observer.free()


func _test_stealth() -> void:
	var model := HackingModel.new({"time_factor": 1.0})
	var hits := _ghost_hits()
	var cells: Array = [
		["Corps 17", {"firewall": 7882.0, "breach": 31528.0, "time": 6.0}, true, 4.92],
		["Government 18", {"firewall": 29557.5, "breach": 29557.5, "time": 6.0}, true, 4.85],
		["Corps 18", {"firewall": 11823.0, "breach": 47292.0, "time": 6.0}, false, -1.0],
		["Government 19", {"firewall": 44336.5, "breach": 44336.5, "time": 6.0}, false, -1.0],
	]
	for cell: Array in cells:
		var outcome := model.attack_outcome(cell[1], 2775.97 * 0.8583, 1669.05 * 0.8583, 1.0, hits, 0.8583, true, true)
		_check.call(outcome.chance >= HackingModel.MIN_HOLD if cell[2] else outcome.chance < HackingModel.MIN_HOLD, "%s with Ghost as measured: %.2f" % [cell[0], outcome.chance])
		if cell[2]:
			_check.call(absf(outcome.used - cell[3]) < 0.5, "%s with Ghost lasts as measured: %.2f" % [cell[0], outcome.used])
	var wall := {"firewall": 29557.5, "breach": 29557.5, "time": 6.0}
	_check.call(model.attack_outcome(wall, 2775.97 * 0.8583, 1669.05 * 0.8583, 1.0, hits, 0.8583).chance < 0.1, "the same attack without stealth stops at the firewall")

	var chain := _chain()
	chain.stealth_mask = 1
	chain.streams.P.variation = 1
	chain.streams.I.variation = 1
	var row := HackingModel.new(chain).evaluate(chain.current)
	var plain_row := HackingModel.new(_chain()).evaluate(_chain().current)
	_check.call(row.insufficient.is_empty() and row.targets.gov.level >= plain_row.targets.gov.level, "stealth gives figures, at least as high as without it")
	var scales := HackingModel.new(chain)._scales("gov", chain.current)
	_check.call(scales.hit_stealth and scales.stack_stealth, "each stream carries its own stealth")
	chain.streams.I.variation = 3
	_check.call(HackingModel.new(chain).evaluate(chain.current).insufficient.has(HackingModel.REASON_UNMEASURED), "stealth with an unknown effect stays unknown")

	var desktop := _strange_desktop()
	var read := HackingChain.read(desktop, {}, null, null, null, 1)
	for slot: Variant in desktop.windows.get_children():
		if slot.get("breach_damage") != null:
			slot.breach_damage.variation = 1
	var ghost := HackingChain.read(desktop, {}, null, null, null, 1)
	_check.call(read.stealth_mask == 1 and read.streams.R.variation == 0 and ghost.streams.R.variation == 1, "stealth is read from what the game exposes, on any node")
	_free_desktop(desktop)

	var observer := Observer.new()
	observer._stealth_mask = 1
	var log_event := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "interval": 1.0, "hits": PackedFloat32Array()}
	for index: int in HackingModel.MIN_HITS:
		log_event.hits.append(100.0)
	observer.hit_log().add("any", "chain", log_event)
	var tracker := {"type": "any", "window": TrialWindow.new(), "getters": {}, "chain_key": "chain"}
	var profile := {"damage_rate": 30.0, "announced_rate": 1.0, "infection_rate": 0.0, "vulnerability": 0.0, "breach_variation": 1, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0, "signature": "g1"}
	_check.call(not observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "with stealth too, the hits measured spare a hopeless try")
	var strong := profile.duplicate()
	strong.announced_rate = 100.0
	strong.signature = "g2"
	_check.call(observer._may_work(tracker, strong, {"level": 7, "max_level": 8}), "with stealth, a level within reach is tried")
	tracker.window.free()
	observer.free()


func _test_profit_choice() -> void:
	var observer := Observer.new()
	observer.configure(SaLog.new("info"), 0.25, false)
	var strong_hits := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "interval": 1.0, "hits": PackedFloat32Array()}
	for index: int in HackingModel.MIN_HITS:
		strong_hits.hits.append(100.0)
	observer.hit_log().add("any", "chain", strong_hits)
	var window := EliteWindow.new()
	var tracker := {"type": "any", "window": window, "getters": {}, "chain_key": "chain", "reward_getters": true}
	var profile := {"damage_rate": 100.0, "announced_rate": 100.0, "infection_rate": 0.0, "vulnerability": 0.0, "breach_variation": 0, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0, "signature": "e"}
	var regulator := Regulator.new("balanced")
	var first := observer._profit_choice(tracker, profile, regulator, {"level": 5, "max_level": 6})
	_check.call(first.profitable == -1, "the levels are measured over the next ticks, not during the attack")
	for tick: int in 6:
		observer._advance_profit_tables()
	_check.call(observer._profit_choice(tracker, profile, regulator, {"level": 5, "max_level": 6}).profitable == -1, "one level a tick")
	observer._advance_profit_tables()
	var choice := observer._profit_choice(tracker, profile, regulator, {"level": 5, "max_level": 6})
	_check.call(choice.profitable == 5 and choice.unlock == 6, "the elite level pays more, and the highest level is worth a try: %s" % str(choice))
	observer.set_objective(HackingAdvice.XP)
	_check.call(observer._profit_choice(tracker, profile, regulator, {"level": 5, "max_level": 6}).profitable == 5, "the panel's objective is followed")
	var opened := observer._profit_choice(tracker, profile, regulator, {"level": 6, "max_level": 7})
	_check.call(opened.profitable == -1, "a level newly opened is measured before choosing again")
	observer._advance_profit_tables()
	var after := observer._profit_choice(tracker, profile, regulator, {"level": 6, "max_level": 7})
	_check.call(after.profitable == 5 and after.unlock == -1, "a level out of reach is not tried: %s" % str(after))
	var unpaid := tracker.duplicate()
	unpaid.reward_getters = false
	_check.call(observer._profit_choice(unpaid, profile, regulator, {"level": 5, "max_level": 6}).is_empty(), "without the game's rewards, the highest level stays the aim")
	var unmeasured := tracker.duplicate()
	unmeasured.chain_key = "never"
	_check.call(observer._profit_choice(unmeasured, profile, regulator, {"level": 5, "max_level": 6}).is_empty(), "nor without hits measured")
	var unknown := profile.duplicate()
	unknown.breach_variation = 4
	unknown.signature = "u"
	_check.call(observer._profit_choice(tracker, unknown, regulator, {"level": 5, "max_level": 6}).is_empty(), "nor with an effect never seen")
	observer.free()
	window.free()


## The panel shows the levels the regulation would choose.
func _test_profitable_level_in_panel() -> void:
	var plain := HackingModel.new(_chain())
	var usual: int = plain.evaluate(plain.current_scenario()).targets.gov.level
	var chain := _chain()
	var lower: int = usual - 2
	chain.targets.gov.levels[lower].reward *= 20.0
	chain.targets.gov.levels[lower].xp *= 20.0
	var model := HackingModel.new(chain)
	var row := model.evaluate(model.current_scenario())
	_check.call(usual > 0 and row.targets.gov.level == lower, "a level that pays far more is shown instead of the highest: %d then %d" % [usual, row.targets.gov.level])
	_check.call(row.targets.corps.level == plain.evaluate(plain.current_scenario()).targets.corps.level, "the other target keeps its level")
	var xp_chain := _chain()
	xp_chain.targets.gov.levels[lower].reward *= 20.0
	xp_chain.objective = HackingAdvice.XP
	var xp_model := HackingModel.new(xp_chain)
	_check.call(xp_model.evaluate(xp_model.current_scenario()).targets.gov.level == usual, "for XP, only the XP counts")


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
	var measured := Observer.new()
	var strong_hits := {"event": "success", "level": 1, "complete": true, "damage_rate": 100.0, "interval": 1.0, "hits": PackedFloat32Array()}
	for index: int in HackingModel.MIN_HITS:
		strong_hits.hits.append(100.0)
	measured.hit_log().add("any", "chain", strong_hits)
	var with_hits := profile.duplicate()
	with_hits.vulnerability = 0.0
	with_hits.announced_rate = 100.0
	with_hits.signature = "h"
	var known := {"type": "any", "window": window, "getters": {}, "chain_key": "chain"}
	_check.call(measured._may_work(known, with_hits, {"level": 7, "max_level": 8}), "the hits measured say a level is worth trying")
	var hopeless := with_hits.duplicate()
	hopeless.announced_rate = 1.0
	hopeless.signature = "h2"
	_check.call(not measured._may_work(known, hopeless, {"level": 7, "max_level": 8}), "the hits measured spare a hopeless try")
	measured.free()

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
