extends Node
## The Conseil button on the nodes, or Ctrl+Alt+F8: advice on the hacking chain for a chosen objective.
## Read-only: the player decides. Nothing it cannot explain may stop the rest of the mod.

const HackingChain := preload("hacking_chain.gd")
const HackingModel := preload("hacking_model.gd")
const HackingUpgrades := preload("hacking_upgrades.gd")
const HackingAdvice := preload("hacking_advice.gd")
const AdvisorPanel := preload("advisor_panel.gd")

const ERROR_TEXTS := {
	"no_desktop": "Aucune partie en cours.",
	"no_target": "Aucun nœud d'infiltration trouvé.",
}
const INSUFFICIENT_TEXTS := {
	HackingModel.REASON_HITS: "pas encore assez de coups mesurés sur cette chaîne",
	HackingModel.REASON_INTERVAL: "pas encore d'attaque vue",
	HackingModel.REASON_UNMEASURED: "mécanique jamais mesurée (furtivité, infection qui grandit)",
}
const CHANCE_NOT_FOLLOWED := "effet non chiffré"
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
var _shown_state := ""
var _computing := false
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
	_panel.show_message("Calcul en cours…")
	_shown_state = ""
	set_process(true)
	_look_at_chain()


## Starts a calculation when the chain changed. What is shown stays until the new figures are ready.
func _look_at_chain() -> void:
	_since_check = 0.0
	var root := get_tree().root
	var chain := HackingChain.read(root.get_node("Globals").desktop, _observer.attack_intervals(), _observer.hit_log(), root.get_node("Attributes"), root.get_node("Data"))
	var upgrades := HackingUpgrades.read(root)
	var state := _state_of(chain, upgrades)
	if state == _shown_state:
		return
	_shown_state = state
	if chain.error != "":
		_computing = false
		_log.info("advisor_compare result=%s" % chain.error)
		_panel.show_message(ERROR_TEXTS.get(chain.error, chain.error))
		return
	_chain = chain
	_model = HackingModel.new(_chain)
	_pending = _model.scenarios()
	_rows = []
	_upgrades = upgrades
	_upgrade_rows = []
	_computing = true


## What the figures depend on: connections, power, levels, and whether enough has been measured.
func _state_of(chain: Dictionary, upgrades: Array[Dictionary]) -> String:
	if chain.error != "":
		return chain.error
	var parts := PackedStringArray([str(chain.current)])
	for key: String in chain.targets:
		var target: Dictionary = chain.targets[key]
		parts.append("%s:%d:%d:%.2f:%.2f:%.2f" % [key, target.level, target.max_level, target.interval, target.vulnerability, target.real.attacks / HackingModel.MIN_ATTACKS_TO_CHECK])
	for stream: Dictionary in chain.streams.values():
		parts.append("%s:%.2f:%d" % [stream.id, stream.production, stream.multipliers.size() / HackingModel.MIN_HITS])
	for upgrade: Dictionary in upgrades:
		parts.append("%s:%.2f:%.2f" % [upgrade.name, upgrade.cost, upgrade.held])
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
	if _upgrade_rows.size() < _upgrades.size():
		_upgrade_rows.append(_evaluate_upgrade(_upgrades[_upgrade_rows.size()]))
		return
	_computing = false
	_current = _model.evaluate(_model.current_scenario())
	_log_rows()
	_render()


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


func _on_objective_selected(key: String) -> void:
	_objective = key
	_render()


func _render() -> void:
	var options := HackingAdvice.objectives(_chain)
	if not options.any(func(option: Dictionary) -> bool: return option.key == _objective):
		_objective = HackingAdvice.BALANCED
	_panel.show_advice(options, _objective, _on_objective_selected, _advice_text(), _connections_table(), _purchases_table(), _note())


func _advice_text() -> String:
	var lines := PackedStringArray()
	if not _current.insufficient.is_empty():
		lines.append("Données insuffisantes pour conseiller : %s. Le conseil reviendra de lui-même, laissez tourner quelques attaques." % _insufficient_text(_current.insufficient))
		return "\n".join(lines)
	var refuted := _model.contradictions(_current)
	if not refuted.is_empty():
		for found: Dictionary in refuted:
			if found.duration:
				lines.append("Le calcul ne correspond pas à ce qui est mesuré sur %s au niveau %d : %.1f s prévues, %.1f s réelles sur %d attaques." % [found.label, found.level, found.expected_used, found.real_used, found.attacks])
			else:
				lines.append("Le calcul ne correspond pas à ce qui est mesuré sur %s au niveau %d : %d %% de réussite prévus, %d %% réels sur %d attaques." % [found.label, found.level, roundi(found.expected * 100.0), roundi(found.real * 100.0), found.attacks])
		lines.append("Aucun conseil chiffré tant que ce n'est pas résolu.")
		return "\n".join(lines)
	var best := HackingAdvice.best_row(_rows, _current, _objective)
	if best == _current:
		lines.append("Branchement : gardez le vôtre, il est déjà le meilleur pour cet objectif.")
	else:
		var effects := HackingAdvice.effects(_chain, _current, best)
		lines.append("Branchement : %s" % HackingAdvice.connection_text(_chain, _current, best))
		lines.append("   Pourquoi : %s Gain : %s. Inconvénient : %s." % [HackingAdvice.why_text(_chain, _current, best), effects.gains, effects.drawbacks])
	var by_resource := {}
	for item: Dictionary in _ranked_purchases():
		if item.row.is_empty() or not item.upgrade.affordable or by_resource.has(item.upgrade.resource):
			continue
		if HackingAdvice.gain(item.row, _current, _objective) >= HackingAdvice.MIN_GAIN:
			by_resource[item.upgrade.resource] = item
	if by_resource.is_empty():
		lines.append("Achat : rien de ce que vous pouvez payer n'aide cet objectif de façon chiffrable pour l'instant.")
	for resource: String in by_resource:
		var item: Dictionary = by_resource[resource]
		var effects := HackingAdvice.effects(_chain, _current, item.row, HackingUpgrades.downsides(item.upgrade.changes))
		lines.append("Achat : %s (%s, vous en avez %s)." % [item.upgrade.name, item.upgrade.cost_text, _number(item.upgrade.held)])
		lines.append("   Pourquoi : %s Gain : %s. Inconvénient : %s." % [HackingAdvice.why_text(_chain, _current, item.row), effects.gains, effects.drawbacks])
	return "\n".join(lines)


## The current connections, then the best for each objective. One row can win several titles.
func _connections_table() -> Dictionary:
	var keys: Array = _chain.targets.keys()
	var header := ["", "Payload vers", "Infection vers"]
	if _chain.current.vulnerability:
		header.append("Vulnérabilité")
	for key: String in keys:
		header.append(_chain.targets[key].label)
	header.append("XP/min")
	for key: String in keys:
		header.append("%s/min" % _chain.targets[key].reward_name.split(" ", false)[0])
	header.append("Fiabilité")
	var rows: Array = [header]
	var kinds: Array = ["header"]
	var picked: Array[Dictionary] = [{"titles": PackedStringArray(["Actuel"]), "row": _current}]
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
			cells.append("gardée" if row.scenario.vulnerability else "retirée")
		for key: String in keys:
			cells.append(_level_text(row.targets[key]))
		cells.append(_with_change(row.xp_rate, _current.xp_rate, row.current))
		for key: String in keys:
			cells.append(_with_change(row.targets[key].reward_rate, _current.targets[key].reward_rate, row.current))
		cells.append("mesuré" if row.current else "estimé")
		rows.append(cells)
		kinds.append("current" if row.current else ("best" if entry.get("selected", false) else ""))
	return {"rows": rows, "kinds": kinds}


func _purchases_table() -> Dictionary:
	var rows: Array = [["Achat", "Coût", "Disponible", "Niveaux", "XP/min", "Gain pour l'objectif"]]
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
			_number(item.row.xp_rate) if followed else "–",
			"%+d %%" % roundi(HackingAdvice.gain(item.row, _current, _objective) * 100.0) if followed else CHANCE_NOT_FOLLOWED,
		])
		kinds.append("" if item.upgrade.affordable and followed else "muted")
	return {"rows": rows, "kinds": kinds}


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
	return "Niveaux réels : %s. Mesuré : coups réellement observés sur votre chaîne. Estimé : les mêmes coups, recalculés selon la puissance et les branchements ; une chaîne jamais jouée reste une estimation. Le pourcentage est la chance de réussir une attaque. Les achats sont estimés sur votre branchement, un à la fois : leurs gains ne s'additionnent pas, rouvrez le panneau après chaque achat." % ", ".join(levels)


func _insufficient_text(reasons: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for reason: String in reasons:
		parts.append(INSUFFICIENT_TEXTS.get(reason, reason))
	return ", ".join(parts)


func _sent_to(assignment: Dictionary) -> String:
	var names := PackedStringArray()
	for key: String in assignment:
		if assignment[key] != "":
			names.append(_chain.targets[key].label)
	return " + ".join(names) if not names.is_empty() else "aucune"


func _short(key: String) -> String:
	var words: PackedStringArray = _chain.targets[key].label.split(" ", false)
	return words[-1].left(1) if not words.is_empty() else key


func _level_text(target: Dictionary) -> String:
	if target.insufficient != "":
		return "données insuffisantes"
	if target.level < 0:
		return "–"
	return "niv. %d, %d %%" % [target.level, roundi(target.chance * 100.0)]


func _held_text(upgrade: Dictionary) -> String:
	if upgrade.held < 0.0:
		return "inconnu"
	if upgrade.affordable:
		return _number(upgrade.held)
	return "%s (manque %s)" % [_number(upgrade.held), _number(upgrade.cost - upgrade.held)]


func _with_change(value: float, reference: float, is_reference: bool) -> String:
	if is_reference or reference <= 0.0:
		return _number(value)
	return "%s (%s)" % [_number(value), HackingAdvice.percent(value, reference)]


func _number(value: float) -> String:
	return HackingUpgrades.grouped(value)


func _log_rows() -> void:
	var hits := PackedStringArray()
	for stream: Dictionary in _chain.streams.values():
		hits.append("%s:%s:%d" % [stream.kind, stream.window_type, stream.multipliers.size()])
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
