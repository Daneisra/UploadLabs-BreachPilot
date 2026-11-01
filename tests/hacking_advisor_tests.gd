extends RefCounted
## Scenario comparison, on values measured in game: 231.1 hack power split between the launcher and
## the infection gave 127.11 and 57.78, and Government level 7 took 4.65 s with half the infection.

const ADVISOR := "res://mods-unpacked/Daneisra-SmartAutomation/features/hacking_advisor/"
const HackingModel := preload(ADVISOR + "hacking_model.gd")
const HackingChain := preload(ADVISOR + "hacking_chain.gd")

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
		"has_crit": true, "crit_factor": 1.65, "other_consumers": 0, "margin": 0.1, "required_success": 0.99, "interval": 1.0,
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
	var model := HackingModel.new(_chain())
	var shared := model.evaluate({"payload": ["breach_corps", "breach_government"], "infection": ["breach_corps", "breach_government"]})
	var government: Dictionary = shared.targets.breach_government
	_check.call(government.level == 7, "Government level 7 is reachable, as measured")
	_check.call(government.used >= 4.0 and government.used <= 5.4, "the duration stays near the 4.65 s measured")
	_check.call(government.xp_rate > 0.0 and government.reward_rate > 0.0, "rates come out of the chosen level")

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
	unmeasured.targets.breach_government.vulnerability = 1.0
	var invalid := HackingModel.new(unmeasured).evaluate({"payload": ["breach_government"], "infection": []})
	_check.call(invalid.targets.breach_government.invalid and invalid.targets.breach_government.level == -1, "what the forecast has not measured is never estimated")


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
	var chain := HackingChain.read(desktop, {"breach_government": 1.0}, 0.1, 0.99)
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
	_check.call(HackingChain.read(desktop, {}, 0.1, 0.99).error == expected, message)
