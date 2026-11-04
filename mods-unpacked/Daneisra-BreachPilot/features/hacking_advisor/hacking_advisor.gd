extends Node
## The Conseil button on the nodes, or Ctrl+Alt+F8: advice on the hacking chain for a chosen objective.
## Read-only: the player decides. Nothing it cannot explain may stop the rest of the mod.

const HackingChain := preload("hacking_chain.gd")
const HackingModel := preload("hacking_model.gd")
const HackingUpgrades := preload("hacking_upgrades.gd")
const HackingAdvice := preload("hacking_advice.gd")
const AdvisorPanel := preload("advisor_panel.gd")
const AdvisorTrials := preload("advisor_trials.gd")
const HackingGraph := preload("hacking_graph.gd")
const LevelChoice := preload("../threat_manager/level_choice.gd")
const I18n := preload("../../core/i18n.gd")

## The chain's errors with their own words, as error.<name>.
const ERROR_TEXTS: Array[String] = ["no_desktop", "no_target"]
## Why a figure is missing, as insufficient.<reason>.
const INSUFFICIENT_TEXTS := {
	HackingModel.REASON_HITS: "insufficient.hits",
	HackingModel.REASON_INTERVAL: "insufficient.interval",
	HackingModel.REASON_UNMEASURED: "insufficient.unmeasured",
}
## How often an open panel looks at the chain. A second is quick enough for a player plugging a cable.
const REFRESH_SECONDS := 1.0

var _log: Variant
var _observer: Variant
var _panel: AdvisorPanel
var _chain: Dictionary
var _model: HackingModel
var _pending: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _current: Dictionary
var _upgrades: Array[Dictionary] = []
var _upgrade_rows: Array[Dictionary] = []
var _trials: Array[Dictionary] = []
var _shown_state := ""
var _computing := false
## The search through a chain too large to try whole: what was tried, from which chain, and how many rounds.
var _seen := {}
var _search_base: Dictionary
var _rounds := 0
var _since_check := 0.0
## Kept for the session: the player's choice should survive closing the panel.
var _objective := HackingAdvice.BALANCED


func configure(logger: Variant, observer: Variant) -> void:
	_log = logger
	_observer = observer


func _ready() -> void:
	_panel = AdvisorPanel.new()
	add_child(_panel)
	set_process(false)


func toggle() -> void:
	if _panel.visible:
		_panel.visible = false
		set_process(false)
		return
	_panel.show_message(I18n.t("panel.computing"))
	_shown_state = ""
	set_process(true)
	_look_at_chain()


## Starts a calculation when the chain changed. What is shown stays until the new figures are ready.
func _look_at_chain() -> void:
	_since_check = 0.0
	var root := get_tree().root
	var chain := HackingChain.read(root.get_node("Globals").desktop, _observer.attack_intervals(), _observer.hit_log(), root.get_node("Attributes"), root.get_node("Data"), _observer.stealth_mask())
	chain.objective = _objective
	var upgrades := HackingUpgrades.read(root)
	var trials := AdvisorTrials.read(HackingGraph.snapshot(root.get_node("Globals").desktop), root.get_node("Data"), root.get_node("Globals"))
	var state := _state_of(chain, upgrades, trials)
	if state == _shown_state:
		return
	_shown_state = state
	if chain.error != "":
		_computing = false
		_log.info("advisor_compare result=%s" % chain.error)
		_panel.show_message(I18n.t("error.%s" % chain.error) if ERROR_TEXTS.has(chain.error) else chain.error)
		return
	_chain = chain
	_trials = trials
	_model = HackingModel.new(_chain)
	_pending = _model.scenarios()
	_seen = {}
	for scenario: Dictionary in _pending:
		_seen[str(scenario)] = true
	_search_base = _chain.current
	_rounds = 0
	_rows = []
	_upgrades = upgrades
	_upgrade_rows = []
	_computing = true


## Only what the player changes: the connections, the power, a purchase becoming possible, a measure
## becoming sufficient, and the objective, which picks the levels. What moves by itself, like hits piling
## up or research growing, must not recalculate.
func _state_of(chain: Dictionary, upgrades: Array[Dictionary], trials: Array[Dictionary] = []) -> String:
	# The language too: the texts are written when the figures are shown.
	# The full locale, not only the table used: the game's names change with it even when the mod's do not.
	var language := "%s:%s" % [I18n.language(), TranslationServer.get_locale()]
	if chain.error != "":
		return "%s|%s" % [language, chain.error]
	var parts := PackedStringArray([language, _objective, str(chain.current)])
	for trial: Dictionary in trials:
		parts.append(trial.key)
	for key: String in chain.targets:
		var target: Dictionary = chain.targets[key]
		parts.append("%s:%d:%s" % [key, target.max_level, target.chain_key])
	for stream: Dictionary in chain.streams.values():
		parts.append("%s:%.1f:%s:%s:%d" % [stream.id, stream.production, stream.multipliers.size() >= HackingModel.MIN_HITS, stream.get("infection", {}).get("pulses", 0) >= HackingModel.MIN_PULSES, stream.get("effects_seen", 0)])
	for upgrade: Dictionary in upgrades:
		parts.append("%s:%.0f:%s" % [upgrade.name, upgrade.cost, upgrade.affordable])
	return "|".join(parts)


## One calculation per frame: the game must not stutter for a panel.
func _process(delta: float) -> void:
	if not _panel.visible:
		set_process(false)
		return
	if not _computing:
		_since_check += delta
		if _since_check >= REFRESH_SECONDS:
			_look_at_chain()
		return
	if not _pending.is_empty():
		_rows.append(_model.evaluate(_pending.pop_back()))
		return
	if _model.searches() and _next_round():
		return
	if _upgrade_rows.size() < _upgrades.size():
		_upgrade_rows.append(_evaluate_upgrade(_upgrades[_upgrade_rows.size()]))
		return
	_computing = false
	_current = _model.evaluate(_model.current_scenario())
	_log_rows()
	_render()


## From the best chain found so far, every cable change is tried again, until nothing better turns up.
## Several changes can then add up, as on a chain small enough to try whole.
func _next_round() -> bool:
	if _rounds >= HackingModel.MAX_SEARCH_ROUNDS:
		return false
	var current := _current_row()
	if current.is_empty():
		return false
	var best := HackingAdvice.best_row(_rows, current, _objective)
	if best.scenario == _search_base:
		return false
	_search_base = best.scenario
	_rounds += 1
	for scenario: Dictionary in _model.neighbors(best.scenario):
		var key := str(scenario)
		if not _seen.has(key):
			_seen[key] = true
			_pending.append(scenario)
	return not _pending.is_empty()


func _current_row() -> Dictionary:
	for row: Dictionary in _rows:
		if row.current:
			return row
	return {}


func _evaluate_upgrade(upgrade: Dictionary) -> Dictionary:
	var item := {"upgrade": upgrade, "row": {}}
	if upgrade.followed and _can_follow(upgrade):
		item.row = HackingModel.new(HackingUpgrades.apply(_chain, upgrade.changes)).evaluate(_model.current_scenario())
		if not item.row.insufficient.is_empty():
			item.row = {}
	return item


func _can_follow(upgrade: Dictionary) -> bool:
	if not upgrade.changes.has("breach_critical_chance") and not upgrade.changes.has("breach_critical_multiplier"):
		return true
	for stream: Dictionary in _chain.streams.values():
		if stream.kind == "payload" and HackingUpgrades.can_follow_critical(stream.multipliers, _chain.crit_multiplier):
			return true
	return false


## The levels depend on the objective, here as in the regulation, which follows the same choice.
func _on_objective_selected(key: String) -> void:
	_objective = key
	_observer.set_objective(key)
	_look_at_chain()


func _render() -> void:
	var options := HackingAdvice.objectives(_chain)
	if not options.any(func(option: Dictionary) -> bool: return option.key == _objective):
		_objective = HackingAdvice.BALANCED
		_observer.set_objective(_objective)
	_panel.show_advice(options, _objective, _on_objective_selected, _card(), _connections_table(), _purchases_table(), _note())


## The recommendation first, then what could be tried. Each line has a kind for its color: "title",
## "good", "bad" or "" for plain text, "muted" for what explains.
func _card() -> Array[Dictionary]:
	var lines := _recommendation()
	var trials := _all_trials()
	if not trials.is_empty():
		lines.append({"text": I18n.t("card.trials"), "kind": "title"})
		for trial: Dictionary in trials.slice(0, AdvisorTrials.SHOWN):
			lines.append({"text": "• %s" % trial.text, "kind": ""})
		if trials.size() > AdvisorTrials.SHOWN:
			lines.append({"text": I18n.t_count("card.more_trials", trials.size() - AdvisorTrials.SHOWN), "kind": "muted"})
	return lines


## The nodes and cables worth trying, and the best purchase to save for, most useful first.
func _all_trials() -> Array[Dictionary]:
	var list := _trials.duplicate()
	var saving := _saving_trial()
	if not saving.is_empty():
		list.append(saving)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority < b.priority)
	return list


## A purchase that cannot be paid yet but would help the objective: its figure comes from the hits measured.
func _saving_trial() -> Dictionary:
	if _current.is_empty() or not _current.insufficient.is_empty():
		return {}
	var best := {}
	for item: Dictionary in _upgrade_rows:
		if item.row.is_empty() or item.upgrade.affordable or item.upgrade.held < 0.0:
			continue
		var gain := HackingAdvice.gain(item.row, _current, _objective)
		if gain >= HackingAdvice.MIN_GAIN and (best.is_empty() or gain > best.gain):
			best = {"item": item, "gain": gain}
	if best.is_empty():
		return {}
	var upgrade: Dictionary = best.item.upgrade
	return {"key": "save|%s" % upgrade.name, "priority": AdvisorTrials.SAVING, "text": I18n.t("trial.saving", {"name": upgrade.name, "gain": _gain_text(best.item.row), "missing": _number(upgrade.cost - upgrade.held)})}


func _recommendation() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if not _current.insufficient.is_empty():
		lines.append({"text": I18n.t("card.insufficient", {"reasons": _insufficient_text(_current.insufficient)}), "kind": "title"})
		lines.append({"text": I18n.t("card.insufficient_hint"), "kind": "muted"})
		return lines
	var refuted := _model.contradictions(_current)
	if not refuted.is_empty():
		lines.append({"text": I18n.t("card.refuted"), "kind": "title"})
		for found: Dictionary in refuted:
			var values := {"target": found.label, "level": found.level, "attacks": found.attacks}
			if found.duration:
				values.merge({"expected": "%.1f" % found.expected_used, "real": "%.1f" % found.real_used})
				lines.append({"text": I18n.t("card.refuted_duration", values), "kind": "bad"})
			else:
				values.merge({"expected": I18n.percent(roundi(found.expected * 100.0)), "real": I18n.percent(roundi(found.real * 100.0))})
				lines.append({"text": I18n.t("card.refuted_chance", values), "kind": "bad"})
		return lines
	var goal := _objective_label()
	var best := HackingAdvice.best_row(_rows, _current, _objective)
	if best == _current:
		var sure := HackingAdvice.reliability(_chain, _current)
		lines.append({"text": I18n.t("card.keep", {"goal": goal}), "kind": "title"})
		lines.append({"text": I18n.t("card.reliability", {"level": sure.text, "reasons": sure.reasons}), "kind": "muted"})
	else:
		var effects := HackingAdvice.effects(_chain, _current, best)
		var sure := HackingAdvice.reliability(_chain, best)
		lines.append({"text": I18n.t("card.best", {"goal": goal, "gain": _gain_text(best)}), "kind": "title"})
		var steps := HackingAdvice.steps(_chain, _current, best)
		for index: int in steps.size():
			lines.append({"text": "   %d. %s." % [index + 1, steps[index]], "kind": ""})
		lines.append({"text": I18n.t("card.gain", {"gains": effects.gains}), "kind": "good"})
		lines.append({"text": I18n.t("card.drawbacks", {"drawbacks": effects.drawbacks}), "kind": "bad" if effects.has_drawbacks else "muted"})
		lines.append({"text": I18n.t("card.reliability", {"level": sure.text, "reasons": sure.reasons}), "kind": "" if sure.level == 2 else "bad"})
		lines.append({"text": I18n.t("card.why", {"why": HackingAdvice.why_text(_chain, _current, best)}), "kind": "muted"})
	var by_resource := {}
	for item: Dictionary in _ranked_purchases():
		if item.row.is_empty() or not item.upgrade.affordable or by_resource.has(item.upgrade.resource):
			continue
		if HackingAdvice.gain(item.row, _current, _objective) >= HackingAdvice.MIN_GAIN:
			by_resource[item.upgrade.resource] = item
	if by_resource.is_empty():
		lines.append({"text": I18n.t("card.no_purchase"), "kind": "muted"})
		var trade := _refused_trade()
		if not trade.is_empty():
			var effects := HackingAdvice.effects(_chain, _current, trade.row)
			lines.append({"text": "   " + I18n.t("card.refused_trade", {"name": trade.upgrade.name, "gains": effects.gains, "drawbacks": effects.drawbacks}), "kind": "muted"})
	for resource: String in by_resource:
		var item: Dictionary = by_resource[resource]
		var effects := HackingAdvice.effects(_chain, _current, item.row, HackingUpgrades.downsides(item.upgrade.changes))
		lines.append({"text": I18n.t("card.purchase", {"name": item.upgrade.name, "cost": item.upgrade.cost_text, "held": _number(item.upgrade.held), "gain": _gain_text(item.row)}), "kind": "title"})
		lines.append({"text": "   " + I18n.t("card.purchase_effects", {"gains": effects.gains, "drawbacks": effects.drawbacks}), "kind": ""})
	return lines


## The best purchase balanced refuses for what it costs elsewhere, by XP: the player may still want it.
func _refused_trade() -> Dictionary:
	var found := {}
	for item: Dictionary in _upgrade_rows:
		if item.row.is_empty() or not item.upgrade.affordable or not HackingAdvice.is_refused_trade(item.row, _current, _objective):
			continue
		if found.is_empty() or item.row.xp_rate > found.row.xp_rate:
			found = item
	return found


func _objective_label() -> String:
	for option: Dictionary in HackingAdvice.objectives(_chain):
		if option.key == _objective:
			return option.label if option.key != HackingAdvice.BALANCED else I18n.t("objective.balanced_goal")
	return _objective


## The gain for the objective; balanced gives the average change of what the chain brings.
func _gain_text(row: Dictionary) -> String:
	var value := I18n.percent(roundi(HackingAdvice.gain(row, _current, _objective) * 100.0), true)
	return I18n.t("gain.average", {"value": value}) if _objective == HackingAdvice.BALANCED else value


## The current connections, then the best for each objective. One row can win several titles.
func _connections_table() -> Dictionary:
	var keys: Array = _chain.targets.keys()
	var header := ["", I18n.t("table.payload_to"), I18n.t("table.infection_to")]
	if _chain.current.vulnerability:
		header.append(I18n.t("table.vulnerability"))
	for key: String in keys:
		header.append(_chain.targets[key].label)
	header.append(I18n.t("table.xp_rate"))
	for key: String in keys:
		var words: PackedStringArray = str(_chain.targets[key].reward_name).split(" ", false)
		header.append(I18n.t("table.rate", {"name": words[0] if not words.is_empty() else _chain.targets[key].label}))
	header.append(I18n.t("table.reliability"))
	var rows: Array = [header]
	var kinds: Array = ["header"]
	var picked: Array[Dictionary] = [{"titles": PackedStringArray([I18n.t("table.current")]), "row": _current}]
	if _current.insufficient.is_empty() and _model.contradictions(_current).is_empty():
		for option: Dictionary in HackingAdvice.objectives(_chain):
			var best := HackingAdvice.best_row(_rows, _current, option.key)
			var entry: Variant = null
			for candidate: Dictionary in picked:
				if candidate.row.scenario == best.scenario:
					entry = candidate
			if entry == null:
				entry = {"titles": PackedStringArray(), "row": best}
				picked.append(entry)
			if option.key == _objective:
				entry.selected = true
			if not entry.row.current:
				entry.titles.append(option.label)
	for entry: Dictionary in picked:
		var row: Dictionary = entry.row
		var cells := [" + ".join(entry.titles), _sent_to(row.scenario.payload), _sent_to(row.scenario.infection)]
		if _chain.current.vulnerability:
			cells.append(I18n.t("table.kept" if row.scenario.vulnerability else "table.removed"))
		for key: String in keys:
			cells.append(_level_text(row.targets[key]))
		cells.append(_with_change(row.xp_rate, _current.xp_rate, row.current))
		for key: String in keys:
			cells.append(_with_change(row.targets[key].reward_rate, _current.targets[key].reward_rate, row.current))
		cells.append(HackingAdvice.reliability(_chain, row).text)
		rows.append(cells)
		kinds.append("current" if row.current else ("best" if entry.get("selected", false) else ""))
	return {"rows": rows, "kinds": kinds}


func _purchases_table() -> Dictionary:
	var rows: Array = [[I18n.t("table.purchase"), I18n.t("table.cost"), I18n.t("table.available"), I18n.t("table.levels"), I18n.t("table.xp_rate"), I18n.t("table.objective_gain")]]
	var kinds: Array = ["header"]
	var usable: bool = _current.insufficient.is_empty() and _model.contradictions(_current).is_empty()
	for item: Dictionary in _ranked_purchases():
		var followed: bool = usable and not item.row.is_empty()
		var levels := PackedStringArray()
		if followed:
			for key: String in item.row.targets:
				levels.append("%s %d" % [_short(key), item.row.targets[key].level])
		rows.append([
			item.upgrade.name, item.upgrade.cost_text, _held_text(item.upgrade),
			", ".join(levels) if followed else "–",
			_estimate(item.row.xp_rate) if followed else "–",
			_purchase_gain(item.row) if followed else I18n.t("purchase.not_followed"),
		])
		kinds.append("" if item.upgrade.affordable and followed else "muted")
	return {"rows": rows, "kinds": kinds}


## A trade balanced refuses is not a loss of everything: what it would lose is said instead.
func _purchase_gain(row: Dictionary) -> String:
	if HackingAdvice.is_refused_trade(row, _current, _objective):
		return I18n.t("purchase.trade", {"drawbacks": HackingAdvice.effects(_chain, _current, row).drawbacks})
	return I18n.percent(roundi(HackingAdvice.gain(row, _current, _objective) * 100.0), true)


## What can be paid and is understood first, each resource together: a point and a token cannot be compared.
func _ranked_purchases() -> Array[Dictionary]:
	var ranked := _upgrade_rows.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_ready: bool = a.upgrade.affordable and not a.row.is_empty()
		var b_ready: bool = b.upgrade.affordable and not b.row.is_empty()
		if a_ready != b_ready:
			return a_ready
		if a.row.is_empty() != b.row.is_empty():
			return b.row.is_empty()
		if a.upgrade.resource != b.upgrade.resource:
			return a.upgrade.resource < b.upgrade.resource
		if a.row.is_empty():
			return a.upgrade.name < b.upgrade.name
		return HackingAdvice.gain(a.row, _current, _objective) / maxf(a.upgrade.cost, 1.0) > HackingAdvice.gain(b.row, _current, _objective) / maxf(b.upgrade.cost, 1.0))
	return ranked


func _note() -> String:
	var levels := PackedStringArray()
	for key: String in _chain.targets:
		levels.append("%s %d/%d" % [_chain.targets[key].label, _chain.targets[key].level, _chain.targets[key].max_level])
	var more := ""
	var trials := _all_trials()
	if trials.size() > AdvisorTrials.SHOWN:
		var rest := PackedStringArray()
		for trial: Dictionary in trials.slice(AdvisorTrials.SHOWN):
			rest.append("• %s" % trial.text)
		more = "%s\n%s\n\n" % [I18n.t("note.more"), "\n".join(rest)]
	return more + I18n.t("note.text", {"levels": ", ".join(levels)})


func _insufficient_text(reasons: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for reason: String in reasons:
		parts.append(I18n.t(INSUFFICIENT_TEXTS[reason]) if INSUFFICIENT_TEXTS.has(reason) else reason)
	return ", ".join(parts)


func _sent_to(assignment: Dictionary) -> String:
	var names := PackedStringArray()
	for key: String in assignment:
		if assignment[key] != "":
			names.append(_chain.targets[key].label)
	return " + ".join(names) if not names.is_empty() else I18n.t("table.none")


func _short(key: String) -> String:
	var words: PackedStringArray = _chain.targets[key].label.split(" ", false)
	return words[-1].left(1) if not words.is_empty() else key


func _level_text(target: Dictionary) -> String:
	if target.insufficient != "":
		return I18n.t("table.insufficient")
	if target.level < 0:
		return "–"
	return I18n.t("table.level", {"level": target.level, "chance": I18n.percent(roundi(target.chance * 100.0))})


func _held_text(upgrade: Dictionary) -> String:
	if upgrade.held < 0.0:
		return I18n.t("held.unknown")
	if upgrade.affordable:
		return _number(upgrade.held)
	return I18n.t("held.missing", {"held": _number(upgrade.held), "missing": _number(upgrade.cost - upgrade.held)})


func _with_change(value: float, reference: float, is_reference: bool) -> String:
	if is_reference or reference <= 0.0:
		return _estimate(value)
	return "%s (%s)" % [_estimate(value), HackingAdvice.percent(value, reference)]


## Three significant digits: these are estimates, and the digits after those are only noise.
func _estimate(value: float) -> String:
	if value < 1000.0:
		return _number(value)
	var scale: float = pow(10.0, floorf(log(value) / log(10.0)) - 2.0)
	return _number(roundf(value / scale) * scale)


func _number(value: float) -> String:
	return HackingUpgrades.grouped(value)


func _log_rows() -> void:
	var hits := PackedStringArray()
	for stream: Dictionary in _chain.streams.values():
		hits.append("%s:%s:%d" % [stream.kind, stream.window_type, stream.multipliers.size()])
		if stream.has("infection"):
			hits.append("pulses=%d/growth=%.4f/level=%.3f/follow=%.3f" % [stream.infection.pulses, stream.infection.growth, stream.infection.level, stream.infection.follow])
	_log.info("advisor_compare result=ok streams=%s scenarios=%d purchases=%d refuted=%d" % [",".join(hits), _rows.size(), _upgrade_rows.size(), _model.contradictions(_model.evaluate(_model.current_scenario())).size()])
	for row: Dictionary in _rows:
		_log.info("advisor_row current=%s insufficient=%s %s" % [row.current, ",".join(row.insufficient), _row_text(row)])
	for item: Dictionary in _upgrade_rows:
		_log.info("advisor_upgrade name=%s cost=%s affordable=%s followed=%s %s" % [item.upgrade.name, item.upgrade.cost, item.upgrade.affordable, item.upgrade.followed, _row_text(item.row) if not item.row.is_empty() else "no_figure"])
	_log.info("advisor_current %s" % _row_text(_current))


func _row_text(row: Dictionary) -> String:
	var parts := PackedStringArray(["xp_rate=%.0f" % row.xp_rate])
	for key: String in row.targets:
		var target: Dictionary = row.targets[key]
		parts.append("%s=%d/%.2f/%.2fs/%.2fs/%.0f" % [key, target.level, target.chance, target.used, target.cycle, target.reward_rate])
	return " ".join(parts)
