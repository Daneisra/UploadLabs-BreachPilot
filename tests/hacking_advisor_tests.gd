extends RefCounted
## Scenario comparison, on values measured in game: 231.1 hack power split between the launcher and
## the infection gave 127.11 and 57.78, and Government level 7 took 4.65 s with half the infection.

const ADVISOR := "res://mods-unpacked/Daneisra-SmartAutomation/features/hacking_advisor/"
const HackingModel := preload(ADVISOR + "hacking_model.gd")
const HackingChain := preload(ADVISOR + "hacking_chain.gd")
const HackingUpgrades := preload(ADVISOR + "hacking_upgrades.gd")
const HackingAdvice := preload(ADVISOR + "hacking_advice.gd")
const Observer := preload("res://mods-unpacked/Daneisra-SmartAutomation/features/threat_manager/threat_observer.gd")

var _check: Callable


class FakeContainer extends Node:
	var id := ""
	var input_id := ""
	var outputs_id: Array = []
	var count := 0.0
	var production := 0.0
	var variation := 0


class FakeBreach extends Node:
	var window := ""
	var data := {"level": 7.0, "max_level": 8.0}
	var breach_damage := FakeContainer.new()
	var infection_damage := FakeContainer.new()
	var vulnerability := FakeContainer.new()
	var cur_reward := 68.3
	var cur_experience := 128.0

	func get_max_firewall(level: int) -> float: return 50.0 * level
	func get_max_breach(level: int) -> float: return 50.0 * level
	func get_max_time(_level: int) -> float: return 6.0
	func is_elite(_level: int) -> bool: return false
	func get_reward(level: int) -> float: return 2.0 * level
	func get_experience_reward(level: int) -> float: return pow(2.0, level)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			breach_damage.free()
			infection_damage.free()
			vulnerability.free()


class FakeNode extends Node:
	var window := ""
	var multiplier := 1.0
	var hack_power := FakeContainer.new()
	var damage := FakeContainer.new()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			hack_power.free()
			damage.free()


class FakeDesktop extends Node:
	var windows := Node.new()


func run(check: Callable) -> void:
	_check = check
	_test_scenarios()
	_test_power_split()
	_test_levels()
	_test_upgrades()
	_test_upgrade_table()
	_test_cycle_and_rates()
	_test_advice()
	_test_new_nodes()
	_test_trial_with_vulnerability()
	_test_problems()
	_test_reader()


func _levels(firewall: float, breach: float, count: int = 12) -> Dictionary:
	var levels := {}
	for level: int in count:
		var scale: float = pow(1.5, level - 7)
		levels[level] = {"firewall": firewall * scale, "breach": breach * scale, "time": 6.0, "elite": false, "reward": 10.0 * pow(1.5, level), "xp": pow(2.0, level)}
	return levels


func _target(label: String, firewall: float, breach: float, payload: float, infection: float) -> Dictionary:
	return {
		"label": label, "level": 7, "max_level": 8, "levels": _levels(firewall, breach),
		"announced_payload": payload, "announced_infection": infection,
		"vulnerability": 0.0, "breach_variation": 0, "infection_variation": 0,
	}


func _chain() -> Dictionary:
	return {
		"error": "", "power": 231.1, "launcher_ratio": 1.1, "has_infection": true, "infection_ratio": 0.5,
		"has_crit": true, "crit_factor": 1.65, "crit_chance": 0.1, "crit_multiplier": 1.5, "time_factor": 1.0, "other_consumers": 0, "interval": 1.0,
		"targets": {
			"breach_corps": _target("Entreprises", 137.0, 546.0, 104.86, 28.89),
			"breach_government": _target("Gouvernement", 341.5, 341.5, 104.86, 28.89),
		},
		"current": {"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]},
		"problems": [],
	}


func _test_scenarios() -> void:
	var model := HackingModel.new(_chain())
	var list := model.scenarios()
	_check.call(list.size() == 12, "advisor compares 3 payload sets against 4 infection sets")
	var current := 0
	var all_have_payload := true
	for scenario: Dictionary in list:
		all_have_payload = all_have_payload and not scenario.payload.is_empty()
		if model.is_current(scenario):
			current += 1
	_check.call(all_have_payload, "advisor always keeps a payload target")
	_check.call(current == 1, "advisor finds the current connections among the scenarios")

	var without := _chain()
	without.has_infection = false
	without.current.infection = []
	_check.call(HackingModel.new(without).scenarios().size() == 3, "advisor proposes no infection without its node")


func _test_power_split() -> void:
	var model := HackingModel.new(_chain())
	_check.call(is_equal_approx(model.power_share(["breach_corps"]), 115.55), "the source splits its power with the infection")
	_check.call(is_equal_approx(model.power_share([]), 231.1), "taking the infection off leaves all the power to the launcher")
	var shared := model.evaluate({"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]})
	_check.call(absf(shared.targets.breach_government.hit - 63.55) < 0.01, "a normal hit is the launcher's share, as measured (63 to 64)")
	_check.call(absf(shared.targets.breach_government.stack - 28.89) < 0.01, "infection is split between its targets, as measured")
	var alone := model.evaluate({"payload": ["breach_corps"], "infection": []})
	_check.call(absf(alone.targets.breach_corps.hit - 254.21) < 0.01, "no infection and one target doubles twice")
	_check.call(alone.targets.breach_government.level == -1 and alone.targets.breach_government.xp_rate == 0.0, "a target with no damage brings nothing")
	_check.call(is_equal_approx(alone.xp_rate, alone.targets.breach_corps.xp_rate), "the XP rate adds up the targets")


func _test_levels() -> void:
	var both := {"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]}
	var shared := HackingModel.new(_chain()).evaluate(both)
	_check.call(shared.targets.breach_government.level == 7, "Government holds level 7 with half the infection, as measured")
	_check.call(shared.targets.breach_corps.level == 7, "Corps holds level 7 with half the infection, as measured")
	_check.call(shared.targets.breach_government.used >= 4.0 and shared.targets.breach_government.used <= 5.2, "the duration stays near the 4.6 s measured")
	_check.call(absf(shared.xp_rate - 2926.0) / 2926.0 < 0.15, "the XP rate stays near the 2926 per minute measured at 7 and 7")

	# Measured over 461 and 21 and 19 attacks: 98 %, 48 % and 47 %.
	var model := HackingModel.new(_chain())
	var corps: Dictionary = _chain().targets.breach_corps
	var government: Dictionary = _chain().targets.breach_government
	_check.call(model.attack_outcome(corps.levels[9], 63.55, 57.78).chance >= 0.85, "Corps level 9 with the whole infection mostly succeeds, as measured")
	_check.call(absf(model.attack_outcome(corps.levels[8], 63.55, 28.89).chance - 0.48) < 0.2, "Corps level 8 with half the infection is a coin toss, as measured")
	_check.call(absf(model.attack_outcome(government.levels[8], 63.55, 28.89).chance - 0.47) < 0.2, "Government level 8 with half the infection is a coin toss, as measured")
	_check.call(model.attack_outcome(corps.levels[9], 63.55, 28.89).chance < 0.3, "Corps level 9 with half the infection fails, as measured")

	var corps_only := HackingModel.new(_chain()).evaluate({"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps"]})
	_check.call(corps_only.targets.breach_corps.level == 9, "Corps holds level 9 with the whole infection, as measured")
	_check.call(absf(corps_only.targets.breach_corps.xp_rate - 4655.0) / 4655.0 < 0.2, "the XP rate stays near the 4655 per minute measured at level 9")

	var no_crit := _chain()
	no_crit.crit_chance = 0.0
	var plain := HackingModel.new(no_crit)
	_check.call(plain.attack_outcome(corps.levels[8], 63.55, 28.89).chance < model.attack_outcome(corps.levels[8], 63.55, 28.89).chance, "critical hits make a level at the limit easier")

	var locked := _chain()
	locked.targets.breach_government.max_level = 2
	locked.targets.breach_government.levels[3].firewall = 1e9
	var gated := HackingModel.new(locked).evaluate({"payload": ["breach_government"], "infection": ["breach_government"]})
	_check.call(gated.targets.breach_government.level == 2, "a failing level above the unlocked ones closes those beyond")

	var open := _chain()
	open.targets.breach_government.levels[3].firewall = 1e9
	var skipping := HackingModel.new(open).evaluate({"payload": ["breach_government"], "infection": ["breach_government"]})
	_check.call(skipping.targets.breach_government.level > 3, "an unlocked level can be reached past one that fails")

	var unmeasured := _chain()
	unmeasured.targets.breach_government.breach_variation = 1
	var invalid := HackingModel.new(unmeasured).evaluate({"payload": ["breach_government"], "infection": []})
	_check.call(invalid.targets.breach_government.invalid and invalid.targets.breach_government.level == -1, "what was never measured is never estimated")

	var first := HackingModel.new(_chain()).evaluate(both)
	_check.call(first.xp_rate == shared.xp_rate, "two calculations give the same figures")


func _test_upgrades() -> void:
	var chain := _chain()
	var changes := {
		"breach_damage_multiplier": {"ratio": 1.2, "added": 0.2},
		"breach_speed_multiplier": {"ratio": 1.25, "added": 0.25},
		"breach_critical_chance": {"ratio": 1.2, "added": 0.02},
		"breach_time_multiplier": {"ratio": 1.5, "added": 0.5},
		"hack_specialization_multiplier": {"ratio": 2.0, "added": 1.0},
	}
	var changed := HackingUpgrades.apply(chain, changes)
	_check.call(is_equal_approx(changed.launcher_ratio, 1.32) and is_equal_approx(changed.infection_ratio, 0.5), "a purchase only changes what it touches")
	_check.call(is_equal_approx(changed.interval, 0.8) and is_equal_approx(changed.crit_chance, 0.12), "speed shortens the interval, and chance adds up")
	_check.call(is_equal_approx(changed.power, 462.2) and is_equal_approx(changed.time_factor, 1.5), "power and time follow")
	_check.call(chain.power == 231.1 and chain.launcher_ratio == 1.1, "the chain read from the game stays as it was")
	var both := {"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]}
	var before := HackingModel.new(chain).evaluate(both)
	var after := HackingModel.new(HackingUpgrades.apply(chain, {"hack_specialization_multiplier": {"ratio": 2.0, "added": 1.0}})).evaluate(both)
	_check.call(after.xp_rate > before.xp_rate, "more power brings more XP")


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


func _test_upgrade_table() -> void:
	var root := Node.new()
	var data := FakeTable.new()
	data.name = "Data"
	data.upgrades = {
		"hack_breach_damage": {"cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_damage_multiplier": [0.1, 0.0, 0.0]}},
		"hack_breach_critical_multiplier": {"cost": 2.0, "limit": 5.0, "attribute_cost": "hack_points", "requirement": ["research.critical_payload"], "attributes": {"breach_critical_multiplier": [0.0, 0.12, 0.0]}},
		"hack_infection_specialist": {"cost": 4.0, "limit": 1.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_damage_multiplier": [0.0, 0.0, 0.6], "infection_damage_multiplier": [0.0, 0.0, 2.0]}},
		"hack_sneak_attack": {"cost": 9.0, "limit": 5.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {"breach_time_multiplier": [0.2, 0.0, 0.0]}},
		"hack_breach_speed": {"cost": 1.0, "limit": 2.0, "attribute_cost": "hack_points", "requirement": [], "attributes": {}},
		"hack_infection_damage": {"cost": 1.0, "limit": 0.0, "attribute_cost": "hack_points", "requirement": ["research.locked"], "attributes": {}},
	}
	data.perks = {"hack_specialization": {"cost": 5.0, "cost_e": 2.0, "cost_inc": 1.0, "limit": 4.0, "currency": "token", "requirement": [], "attributes": {"hack_specialization_multiplier": [0.25, 0.0, 0.0]}}}
	root.add_child(data)
	var globals := FakeTable.new()
	globals.name = "Globals"
	globals.upgrades = {"hack_breach_damage": 1, "hack_breach_speed": 2, "hack_sneak_attack": 1}
	globals.perks = {"hack_specialization": 1}
	globals.unlocks = {"research.locked": false, "research.critical_payload": true}
	globals.currencies = {"token": 400.0}
	root.add_child(globals)
	var attributes := FakeTable.new()
	attributes.name = "Attributes"
	attributes.attributes = {
		"hack_points": FakeAttribute.new(6.0),
		"breach_damage_multiplier": FakeAttribute.new(1.0, 0.1),
		"infection_damage_multiplier": FakeAttribute.new(1.0),
		"breach_critical_multiplier": FakeAttribute.new(1.5),
		"breach_time_multiplier": FakeAttribute.new(1.0, 0.2),
		"hack_specialization_multiplier": FakeAttribute.new(1.0, 0.25),
	}
	root.add_child(attributes)

	var by_name := {}
	for item: Dictionary in HackingUpgrades.read(root):
		by_name[item.name] = item
	_check.call(not by_name.has("Vitesse d'intrusion"), "an upgrade at its limit is left out")
	_check.call(not by_name.has("Dégâts d'infection"), "a locked upgrade is left out")
	_check.call(absf(by_name["Dégâts Payload"].changes.breach_damage_multiplier.ratio - 1.2 / 1.1) < 0.001, "an added value is measured against the current one")
	_check.call(absf(by_name["Multiplicateur de critique"].changes.breach_critical_multiplier.ratio - 1.12) < 0.001, "a multiplier gives 12 %, as the game says")
	_check.call(absf(by_name["Spécialiste d'infection"].changes.breach_damage_multiplier.ratio - 0.6) < 0.001 and absf(by_name["Spécialiste d'infection"].changes.infection_damage_multiplier.ratio - 2.0) < 0.001, "the specialist cuts one and doubles the other, as the game says")
	_check.call(absf(by_name["Attaque furtive"].changes.breach_time_multiplier.ratio - 1.4 / 1.2) < 0.001, "the sneak attack adds a second to 6, as the game says")
	_check.call(not by_name["Attaque furtive"].affordable and by_name["Dégâts Payload"].affordable, "the points held decide what is affordable")
	_check.call(absf(by_name["Spécialisation de hack"].cost - 500.0) < 0.001 and absf(by_name["Spécialisation de hack"].changes.hack_specialization_multiplier.ratio - 1.2) < 0.001, "the perk costs 500 tokens for 20 %, as the game says")
	_check.call(not by_name["Spécialisation de hack"].affordable and by_name["Spécialisation de hack"].held == 400.0, "400 tokens do not pay for 500")
	_check.call(by_name["Dégâts Payload"].cost_text == "1 point de piratage" and by_name["Multiplicateur de critique"].cost_text == "2 points de piratage", "the cost reads properly")
	globals.currencies = {}
	var unknown: Dictionary = {}
	for item: Dictionary in HackingUpgrades.read(root):
		if item.name == "Spécialisation de hack":
			unknown = item
	_check.call(unknown.held == -1.0 and not unknown.affordable, "an unknown balance is never advised")
	root.free()


func _test_cycle_and_rates() -> void:
	var both := {"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]}
	var model := HackingModel.new(_chain())
	_check.call(is_equal_approx(model._next_shot(3.95), 4.0) and is_equal_approx(model._next_shot(4.0), 5.0), "the next attack waits for the next shot, as measured")
	# Measured after a purchase: 5128 XP per minute over 10 min, then 5694 over 24 min with 20 % more power.
	var infection := _chain()
	infection.infection_ratio = 0.55
	var after_purchase := HackingModel.new(infection).evaluate(both)
	_check.call(after_purchase.targets.breach_corps.level == 8 and after_purchase.targets.breach_government.level == 8, "the purchase opens level 8 on both, as measured")
	_check.call(absf(after_purchase.xp_rate - 5128.0) / 5128.0 < 0.15, "the XP rate stays near the 5128 measured after the purchase")
	var more_power := _chain()
	more_power.infection_ratio = 0.55
	more_power.power *= 1.2
	var stronger := HackingModel.new(more_power).evaluate(both)
	_check.call(absf(stronger.xp_rate - 5694.0) / 5694.0 < 0.15, "the XP rate stays near the 5694 measured with more power")


func _row(payload: Array, infection: Array, corps: Array, government: Array, xp: float) -> Dictionary:
	return {
		"scenario": {"payload": payload, "infection": infection}, "xp_rate": xp,
		"targets": {
			"breach_corps": {"level": corps[0], "chance": corps[1], "cycle": corps[2], "reward_rate": corps[3]},
			"breach_government": {"level": government[0], "chance": government[1], "cycle": government[2], "reward_rate": government[3]},
		},
	}


func _test_advice() -> void:
	var chain := _chain()
	var all := ["breach_corps", "breach_government"]
	var current := _row(all, all, [7, 1.0, 5.0, 776.0], [7, 1.0, 5.0, 774.0], 2900.0)
	var corps_only := _row(["breach_corps"], ["breach_corps"], [9, 1.0, 6.0, 1650.0], [-1, 0.0, 0.0, 0.0], 5490.0)
	var split := _row(all, ["breach_corps"], [9, 0.9, 6.0, 1400.0], [4, 1.0, 4.0, 290.0], 4900.0)
	var rows: Array[Dictionary] = [current, corps_only, split]

	var objectives := HackingAdvice.objectives(chain)
	_check.call(objectives.size() == 4 and objectives[0].key == "xp" and objectives[3].key == "balanced", "the objectives follow the chain's targets")
	_check.call(HackingAdvice.best_row(rows, current, "xp") == corps_only, "the XP objective picks the most XP")
	_check.call(HackingAdvice.best_row(rows, current, "breach_government") == current, "no row beats the current one on intelligence: keep it")
	_check.call(is_equal_approx(HackingAdvice.score(corps_only, "balanced"), 0.0), "balanced gives nothing to a chain bringing nothing of one thing")
	var slightly := _row(all, ["breach_corps"], [7, 1.0, 5.0, 776.0], [7, 1.0, 5.0, 774.0], 2910.0)
	var noise: Array[Dictionary] = [current, slightly]
	_check.call(HackingAdvice.best_row(noise, current, "xp") == current, "a tiny gain is not worth rewiring")

	var text := HackingAdvice.connection_text(chain, current, corps_only)
	_check.call(text.contains("Payload : débrancher de Gouvernement") and text.contains("Infection : débrancher de Gouvernement"), "the advice says what to unplug")
	var no_infection := _row(all, [], [7, 1.0, 5.0, 700.0], [7, 1.0, 5.0, 700.0], 2800.0)
	_check.call(HackingAdvice.connection_text(chain, current, no_infection).contains("Interface"), "taking the infection off also frees its power")
	var why := HackingAdvice.why_text(chain, current, corps_only)
	_check.call(why.contains("Entreprises passe du niveau 7 au niveau 9") and why.contains("Gouvernement ne reçoit plus"), "the advice says why")
	var faster := _row(all, all, [7, 1.0, 4.0, 900.0], [7, 1.0, 5.0, 774.0], 3100.0)
	_check.call(HackingAdvice.why_text(chain, current, faster) == "Entreprises attaque plus vite.", "without a new level, faster attacks explain the gain")

	var effects := HackingAdvice.effects(chain, current, corps_only)
	_check.call(effects.gains.contains("XP +89 %") and effects.gains.contains("Données +113 %"), "the advice gives the gains")
	_check.call(effects.drawbacks.contains("Renseignements -100 %"), "the advice gives the drawback")
	_check.call(HackingAdvice.effects(chain, current, split).drawbacks.contains("Entreprises moins sûr (90 % de réussite)"), "a level at risk counts as a drawback")
	_check.call(HackingAdvice.effects(chain, current, faster).drawbacks == "aucun", "no drawback is said plainly")
	_check.call(absf(HackingAdvice.gain(corps_only, current, "xp") - 0.893) < 0.01, "the gain is relative to the current chain")


func _test_new_nodes() -> void:
	var chain := _chain()
	var corps: Dictionary = chain.targets.breach_corps
	var plain := HackingModel.new(chain).attack_outcome(corps.levels[8], 76.26, 38.13)
	var weak := _chain()
	weak.crit_chance = 0.0
	var without := HackingModel.new(weak).attack_outcome(corps.levels[8], 40.0, 20.0)
	var charged := weak.duplicate()
	charged.charge_every = 3
	var with_charge := HackingModel.new(charged).attack_outcome(corps.levels[8], 40.0, 20.0)
	_check.call(with_charge.chance >= without.chance and with_charge.used <= without.used or without.used < 0.0, "charged shots do not slow an attack")
	var vulnerable := HackingModel.new(weak).attack_outcome(corps.levels[8], 40.0, 20.0, 0.5)
	_check.call(vulnerable.chance >= without.chance, "vulnerability helps an attack")
	_check.call(plain.chance > 0.9, "the level measured at this power holds")

	# Measured with the injection fed, 3 consumers: level 8 on both, 76 attacks out of 76, about 4.95 s.
	var fed := _chain()
	fed.power = 323.55
	fed.infection_ratio = 0.55
	fed.charge_every = 3
	fed.injection_fed = true
	fed.crit_factor = 2.2
	fed.targets.breach_corps.vulnerability = 0.234
	fed.targets.breach_government.vulnerability = 0.234
	fed.targets.breach_corps.announced_payload = 130.5
	fed.targets.breach_government.announced_payload = 130.5
	fed.targets.breach_corps.announced_infection = 29.66
	fed.targets.breach_government.announced_infection = 29.66
	var model := HackingModel.new(fed)
	_check.call(model.chain_problems().is_empty(), "a chain with these nodes follows the rules")
	_check.call(model.scenarios().size() == 24, "the injection doubles the scenarios: kept or taken off")
	var kept := model.evaluate(model.current_scenario())
	_check.call(kept.current, "the current connections include the injection")
	_check.call(kept.targets.breach_government.level >= 8 and absf(kept.targets.breach_government.used - 4.95) < 0.6, "the measured attacks are within reach, near the 4.95 s measured")
	_check.call(absf(model.power_share(["breach_corps"], true) - 107.85) < 0.01 and absf(model.power_share(["breach_corps"], false) - 161.78) < 0.01, "taking the injection off gives its share back")
	var off := {"scenario": {"payload": fed.current.payload, "infection": fed.current.infection, "injection": false}}
	_check.call(HackingAdvice.connection_text(fed, kept, off).contains("Exécuter l'injection"), "the advice names the injection")

	var requirement := HackingUpgrades.apply(fed, {"charged_attacks_requirement": {"ratio": 0.67, "added": -1.0}})
	_check.call(requirement.charge_every == 2, "the charged attack purchase lowers the charges needed")
	var specialist := {"breach_damage_multiplier": {"ratio": 0.6, "added": -0.44}, "infection_damage_multiplier": {"ratio": 2.0, "added": 1.0}}
	_check.call(HackingUpgrades.downsides(specialist) == PackedStringArray(["Dégâts Payload -40 %"]), "the game's own drawback is named")
	var effects := HackingAdvice.effects(fed, kept, kept, HackingUpgrades.downsides(specialist))
	_check.call(effects.drawbacks == "Dégâts Payload -40 %", "the drawback shows even when the result is a gain")
	var scanned := {"category": "optimizations", "attributes": {"charged_attacks_requirement": [-1.0, 0.0, 0.0]}}
	_check.call(HackingUpgrades._follows("anything", scanned), "a new hacking purchase the comparison can follow is listed")
	var foreign := {"category": "optimizations", "attributes": {"breach_skills": [1.0, 0.0, 0.0]}}
	_check.call(not HackingUpgrades._follows("anything", foreign), "a purchase the comparison cannot follow stays out")


func _test_trial_with_vulnerability() -> void:
	var observer := Observer.new()
	var window := FakeBreach.new()
	var tracker := {"type": "breach_corps", "window": window, "getters": {}}
	var profile := {"damage_rate": 30.0, "infection_rate": 0.0, "vulnerability": 0.234, "breach_variation": 0, "infection_variation": 0, "interval": 1.0, "tick_speed": 0.05, "infection_offset": -1.0, "signature": "v"}
	_check.call(observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "with vulnerability a real trial is allowed")
	_check.call(not observer._may_work(tracker, profile, {"level": 8, "max_level": 8}), "a trial never goes above the highest level")
	profile.vulnerability = 0.0
	profile.signature = "no"
	profile.damage_rate = 1.0
	_check.call(not observer._may_work(tracker, profile, {"level": 7, "max_level": 8}), "without vulnerability the forecast still decides")
	window.free()
	observer.free()


func _test_problems() -> void:
	_check.call(HackingModel.new(_chain()).chain_problems().is_empty(), "the measured chain follows the rules")
	var odd := _chain()
	odd.targets.breach_corps.announced_payload = 40.0
	_check.call(HackingModel.new(odd).chain_problems().has("payload_mismatch:breach_corps"), "a chain off the rules is flagged")


func _test_reader() -> void:
	var desktop := FakeDesktop.new()
	_check_read_error(desktop, "chain_shape", "a chain without its source is refused")

	var source := FakeNode.new()
	source.window = "hacker"
	source.hack_power.id = "S"
	source.hack_power.count = 231.1
	source.hack_power.outputs_id = ["L", "I"]
	var launcher := FakeNode.new()
	launcher.window = "payload_launcher"
	launcher.hack_power.id = "L"
	launcher.hack_power.input_id = "S"
	launcher.hack_power.count = 115.55
	launcher.damage.production = 127.11
	var infection := FakeNode.new()
	infection.window = "build_infection"
	infection.hack_power.id = "I"
	infection.hack_power.input_id = "S"
	infection.hack_power.count = 115.55
	infection.damage.production = 57.78
	var breach := FakeBreach.new()
	breach.window = "breach_government"
	breach.breach_damage.production = 127.11
	breach.infection_damage.production = 57.78
	for node: Node in [source, launcher, infection, breach]:
		desktop.windows.add_child(node)

	_check_read_error(desktop, "no_attack_seen", "no comparison before an attack was seen")
	var chain := HackingChain.read(desktop, {"breach_government": 1.0}, null)
	_check.call(chain.error == "", "the reader accepts a standard chain")
	_check.call(chain.other_consumers == 0, "the reader counts the source's consumers")
	_check.call(absf(chain.launcher_ratio - 1.1) < 0.01 and absf(chain.infection_ratio - 0.5) < 0.01, "the reader measures the nodes' ratios")
	_check.call(chain.current.payload == ["breach_government"] and chain.current.infection == ["breach_government"], "the reader sees the current connections")
	_check.call(chain.targets.breach_government.levels.size() == 8 + HackingChain.LEVELS_AHEAD + 1, "the reader looks a few levels ahead")
	_check.call(HackingModel.new(chain).chain_problems().is_empty(), "the reader's chain follows the rules")

	var second := FakeBreach.new()
	second.window = "breach_government"
	desktop.windows.add_child(second)
	_check_read_error(desktop, "chain_shape", "two nodes of a type are refused")
	desktop.windows.free()
	desktop.free()


func _check_read_error(desktop: Node, expected: String, message: String) -> void:
	_check.call(HackingChain.read(desktop, {}, null).error == expected, message)
