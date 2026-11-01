extends Node
## Ctrl+Alt+F8: advice on the hacking chain for a chosen objective. Read-only: the player decides.

const HackingChain := preload("hacking_chain.gd")
const HackingModel := preload("hacking_model.gd")
const HackingUpgrades := preload("hacking_upgrades.gd")
const HackingAdvice := preload("hacking_advice.gd")
const AdvisorPanel := preload("advisor_panel.gd")

const ERROR_TEXTS := {
	"no_desktop": "Aucune partie en cours.",
	"chain_shape": "Il faut une seule Interface de hacking, un seul Lanceur Payload, et au plus une infection, un Payload critique et un nœud par cible.",
	"no_target": "Aucun nœud d'infiltration trouvé.",
	"no_payload": "Aucune cible ne reçoit de Payload : rien à comparer pour l'instant.",
	"no_attack_seen": "Le mod n'a pas encore vu d'attaque : réessayez dans quelques secondes.",
}
const SHORT_NAMES := {"breach_corps": "E", "breach_government": "G", "breach_bank": "B", "breach_anonymous": "A"}

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
	set_process(false)
	if _panel.visible:
		_panel.visible = false
		return
	_panel.show_message("Calcul en cours…")
	var root := get_tree().root
	_chain = HackingChain.read(root.get_node("Globals").desktop, _observer.attack_intervals(), root.get_node("Attributes"))
	if _chain.error != "":
		_log.info("advisor_compare result=%s" % _chain.error)
		_panel.show_message(ERROR_TEXTS.get(_chain.error, _chain.error))
		return
	_model = HackingModel.new(_chain)
	_pending = _model.scenarios()
	_rows = []
	_upgrades = HackingUpgrades.read(root)
	_upgrade_rows = []
	set_process(true)


## One calculation per frame: the game must not stutter for a panel.
func _process(_delta: float) -> void:
	if not _panel.visible:
		set_process(false)
		return
	if not _pending.is_empty():
		_rows.append(_model.evaluate(_pending.pop_back()))
		return
	if _upgrade_rows.size() < _upgrades.size():
		var upgrade: Dictionary = _upgrades[_upgrade_rows.size()]
		var model := HackingModel.new(HackingUpgrades.apply(_chain, upgrade.changes))
		_upgrade_rows.append({"upgrade": upgrade, "row": model.evaluate(_model.current_scenario())})
		return
	set_process(false)
	_current = _model.evaluate(_model.current_scenario())
	_log_rows()
	_render()


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
	var problems := _model.chain_problems()
	if not problems.is_empty():
		lines.append("Attention : votre chaîne ne suit pas les règles mesurées (%s). Chiffres à prendre avec prudence." % ", ".join(problems))
	var best := HackingAdvice.best_row(_rows, _current, _objective)
	if best == _current:
		lines.append("Branchement : gardez le vôtre, il est déjà le meilleur pour cet objectif.")
	else:
		var effects := HackingAdvice.effects(_chain, _current, best)
		lines.append("Branchement : %s" % HackingAdvice.connection_text(_chain, _current, best))
		lines.append("   Pourquoi : %s Gain : %s. Inconvénient : %s." % [HackingAdvice.why_text(_chain, _current, best), effects.gains, effects.drawbacks])
	var by_resource := {}
	for item: Dictionary in _ranked_purchases():
		if item.upgrade.affordable and HackingAdvice.gain(item.row, _current, _objective) >= HackingAdvice.MIN_GAIN and not by_resource.has(item.upgrade.resource):
			by_resource[item.upgrade.resource] = item
	if by_resource.is_empty():
		lines.append("Achat : rien de ce que vous pouvez payer n'aide cet objectif pour l'instant.")
	for resource: String in by_resource:
		var item: Dictionary = by_resource[resource]
		var effects := HackingAdvice.effects(_chain, _current, item.row)
		lines.append("Achat : %s (%s, vous en avez %s)." % [item.upgrade.name, item.upgrade.cost_text, _number(item.upgrade.held)])
		lines.append("   Pourquoi : %s Gain : %s. Inconvénient : %s." % [HackingAdvice.why_text(_chain, _current, item.row), effects.gains, effects.drawbacks])
	return "\n".join(lines)


## The current connections, the best for each objective. One row can win several titles.
func _connections_table() -> Dictionary:
	var types: Array = _chain.targets.keys()
	var header := ["", "Payload vers", "Infection vers"]
	for type: String in types:
		header.append(_chain.targets[type].label)
	header.append("XP/min")
	for type: String in types:
		header.append("%s/min" % HackingAdvice.reward_name(_chain, type))
	var rows: Array = [header]
	var kinds: Array = ["header"]
	var picked: Array[Dictionary] = [{"titles": PackedStringArray(["Actuel"]), "row": _current}]
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
		if entry.row != _current:
			entry.titles.append(option.label)
	for entry: Dictionary in picked:
		var row: Dictionary = entry.row
		var is_current: bool = row == _current
		var cells := [" + ".join(entry.titles), _names(row.scenario.payload), _names(row.scenario.infection)]
		for type: String in types:
			cells.append(_level_text(row.targets[type]))
		cells.append(_with_change(row.xp_rate, _current.xp_rate, is_current))
		for type: String in types:
			cells.append(_with_change(row.targets[type].reward_rate, _current.targets[type].reward_rate, is_current))
		rows.append(cells)
		kinds.append("current" if is_current else ("best" if entry.get("selected", false) else ""))
	return {"rows": rows, "kinds": kinds}


func _purchases_table() -> Dictionary:
	var types: Array = _chain.targets.keys()
	var rows: Array = [["Achat", "Coût", "Disponible", "Niveaux", "XP/min", "Gain pour l'objectif"]]
	var kinds: Array = ["header"]
	for item: Dictionary in _ranked_purchases():
		var levels := PackedStringArray()
		for type: String in types:
			levels.append("%s %d" % [SHORT_NAMES[type], item.row.targets[type].level])
		var change := HackingAdvice.gain(item.row, _current, _objective)
		rows.append([item.upgrade.name, item.upgrade.cost_text, _held_text(item.upgrade), ", ".join(levels), _number(item.row.xp_rate), "%+d %%" % roundi(change * 100.0)])
		kinds.append("" if item.upgrade.affordable else "muted")
	return {"rows": rows, "kinds": kinds}


## What can be paid first, each resource together: a point and a token cannot be compared.
func _ranked_purchases() -> Array[Dictionary]:
	var ranked := _upgrade_rows.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.upgrade.affordable != b.upgrade.affordable:
			return a.upgrade.affordable
		if a.upgrade.resource != b.upgrade.resource:
			return a.upgrade.resource < b.upgrade.resource
		return HackingAdvice.gain(a.row, _current, _objective) / a.upgrade.cost > HackingAdvice.gain(b.row, _current, _objective) / b.upgrade.cost)
	return ranked


func _note() -> String:
	var levels := PackedStringArray()
	for type: String in _chain.targets:
		levels.append("%s %d/%d" % [_chain.targets[type].label, _chain.targets[type].level, _chain.targets[type].max_level])
	return "Niveaux réels : %s. Estimations : attaques tirées au hasard avec les critiques du jeu. Le pourcentage est la chance de réussir une attaque. Les achats sont estimés sur votre branchement, un à la fois : leurs gains ne s'additionnent pas, rouvrez le panneau après chaque achat." % ", ".join(levels)


func _names(types: Array) -> String:
	if types.is_empty():
		return "aucune"
	var names := PackedStringArray()
	for type: String in types:
		names.append(_chain.targets[type].label)
	return " + ".join(names)


func _level_text(target: Dictionary) -> String:
	if target.invalid:
		return "non mesuré"
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
	var whole := roundi(value)
	if whole < 1000:
		return str(whole)
	return "%d %03d" % [whole / 1000, whole % 1000]


func _log_rows() -> void:
	_log.info("advisor_compare result=ok power=%s launcher_ratio=%s infection_ratio=%s crit=%s/%s others=%d interval=%s problems=%s" % [_chain.power, _chain.launcher_ratio, _chain.infection_ratio, _chain.crit_chance, _chain.crit_multiplier, _chain.other_consumers, _chain.interval, ",".join(_model.chain_problems())])
	for row: Dictionary in _rows:
		_log.info("advisor_row current=%s payload=%s infection=%s %s" % [row.current, ",".join(row.scenario.payload), ",".join(row.scenario.infection), _row_text(row)])
	for item: Dictionary in _upgrade_rows:
		_log.info("advisor_upgrade name=%s cost=%s affordable=%s %s" % [item.upgrade.name, item.upgrade.cost, item.upgrade.affordable, _row_text(item.row)])
	_log.info("advisor_current %s" % _row_text(_current))


func _row_text(row: Dictionary) -> String:
	var parts := PackedStringArray(["xp_rate=%.0f" % row.xp_rate])
	for type: String in row.targets:
		var target: Dictionary = row.targets[type]
		parts.append("%s=%d/%.2f/%.2fs/%.2fs/%.0f" % [type, target.level, target.chance, target.used, target.cycle, target.reward_rate])
	return " ".join(parts)
