extends Node
## Ctrl+Alt+F8: compares the ways of connecting the hacking chain, and what each purchase would bring.
## Read-only: the player decides.

const HackingChain := preload("hacking_chain.gd")
const HackingModel := preload("hacking_model.gd")
const HackingUpgrades := preload("hacking_upgrades.gd")
const AdvisorPanel := preload("advisor_panel.gd")

const ERROR_TEXTS := {
	"no_desktop": "Aucune partie en cours.",
	"chain_shape": "Il faut une seule Interface de hacking, un seul Lanceur Payload, et au plus une infection, un Payload critique et un nœud par cible.",
	"no_target": "Aucun nœud d'infiltration trouvé.",
	"no_payload": "Aucune cible ne reçoit de Payload : rien à comparer pour l'instant.",
	"no_attack_seen": "Le mod n'a pas encore vu d'attaque : réessayez dans quelques secondes.",
}
const REWARD_NAMES := {"breach_corps": "Données", "breach_government": "Renseign."}
const SHORT_NAMES := {"breach_corps": "E", "breach_government": "G", "breach_bank": "B", "breach_anonymous": "A"}

var _log: Variant
var _observer: Variant
var _panel: AdvisorPanel
var _chain: Dictionary
var _model: HackingModel
var _pending: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _upgrades: Array[Dictionary] = []
var _upgrade_rows: Array[Dictionary] = []


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
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.xp_rate > b.xp_rate)
	var problems := _model.chain_problems()
	var current := _model.evaluate(_model.current_scenario())
	_upgrade_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _gain_per_cost(a, current) > _gain_per_cost(b, current))
	_log_rows(current, problems)
	_show(current, problems)


func _show(current: Dictionary, problems: PackedStringArray) -> void:
	var types: Array = _chain.targets.keys()
	var header := ["", "Payload vers", "Infection vers"]
	for type: String in types:
		header.append(_chain.targets[type].label)
	header.append("XP/min")
	for type: String in types:
		header.append("%s/min" % REWARD_NAMES.get(type, _chain.targets[type].label))
	var table: Array = [header]
	var kinds: Array = ["header"]
	for picked: Dictionary in _picked_rows(current, types):
		var row: Dictionary = picked.row
		var cells := [picked.label, _names(row.scenario.payload), _names(row.scenario.infection)]
		for type: String in types:
			cells.append(_level_text(row.targets[type]))
		cells.append(_with_change(row.xp_rate, current.xp_rate, picked.kind == "current"))
		for type: String in types:
			cells.append(_with_change(row.targets[type].reward_rate, current.targets[type].reward_rate, picked.kind == "current"))
		table.append(cells)
		kinds.append(picked.kind)

	var upgrade_table: Array = [["Achat", "Coût", "Niveaux", "XP/min", "Gain XP"]]
	var upgrade_kinds: Array = ["header"]
	for item: Dictionary in _upgrade_rows:
		var levels := PackedStringArray()
		for type: String in types:
			levels.append("%s %d" % [SHORT_NAMES[type], item.row.targets[type].level])
		upgrade_table.append([item.upgrade.name, item.upgrade.cost_text, ", ".join(levels), _number(item.row.xp_rate), _percent(item.row.xp_rate, current.xp_rate)])
		upgrade_kinds.append("" if item.upgrade.affordable else "muted")

	_panel.show_tables(_summary(current, problems), table, kinds, upgrade_table, upgrade_kinds, _note())


## The player's connections, then the best for each thing a chain can bring. One row can win several titles.
func _picked_rows(current: Dictionary, types: Array) -> Array[Dictionary]:
	var picked: Array[Dictionary] = [{"label": "Actuel", "kind": "current", "row": current}]
	var titles: Array = [["Meilleur XP", func(row: Dictionary) -> float: return row.xp_rate]]
	for type: String in types:
		var name: String = REWARD_NAMES.get(type, _chain.targets[type].label)
		titles.append(["Meilleur %s" % name, func(row: Dictionary) -> float: return row.targets[type].reward_rate])
	for title: Array in titles:
		var best: Dictionary = _rows[0]
		for row: Dictionary in _rows:
			if title[1].call(row) > title[1].call(best):
				best = row
		if _model.is_current(best.scenario):
			picked[0].label += ", " + title[0].to_lower()
			continue
		var found := false
		for entry: Dictionary in picked:
			if entry.row.scenario == best.scenario:
				entry.label += ", " + title[0].to_lower()
				found = true
		if not found:
			picked.append({"label": title[0], "kind": "best" if picked.size() == 1 else "", "row": best})
	return picked


func _summary(current: Dictionary, problems: PackedStringArray) -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("Attention : votre chaîne ne suit pas les règles mesurées (%s). Chiffres à prendre avec prudence." % ", ".join(problems))
	var best: Dictionary = _rows[0]
	if _model.is_current(best.scenario):
		lines.append("Votre branchement est déjà le meilleur pour l'XP.")
	else:
		lines.append("Pour plus d'XP : Payload vers %s, infection vers %s (%s XP)." % [_names(best.scenario.payload), _names(best.scenario.infection), _percent(best.xp_rate, current.xp_rate)])
	for item: Dictionary in _upgrade_rows:
		if item.upgrade.affordable and item.row.xp_rate > current.xp_rate:
			lines.append("Achat le plus rentable, sur votre branchement : %s (%s, %s XP)." % [item.upgrade.name, item.upgrade.cost_text, _percent(item.row.xp_rate, current.xp_rate)])
			break
	return "\n".join(lines)


func _note() -> String:
	var levels := PackedStringArray()
	for type: String in _chain.targets:
		levels.append("%s %d/%d" % [_chain.targets[type].label, _chain.targets[type].level, _chain.targets[type].max_level])
	return "Niveaux réels : %s. Estimations : attaques tirées au hasard avec les critiques du jeu. Le pourcentage est la chance de réussir une attaque. Infection vers « aucune » suppose de la débrancher aussi de l'Interface, ce qui rend sa puissance au Lanceur." % ", ".join(levels)


func _gain_per_cost(item: Dictionary, current: Dictionary) -> float:
	if not item.upgrade.affordable or item.upgrade.cost <= 0.0:
		return -1.0
	return (item.row.xp_rate - current.xp_rate) / item.upgrade.cost


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


func _with_change(value: float, reference: float, is_reference: bool) -> String:
	if is_reference or reference <= 0.0:
		return _number(value)
	return "%s (%s)" % [_number(value), _percent(value, reference)]


func _percent(value: float, reference: float) -> String:
	if reference <= 0.0:
		return "–"
	return "%+d %%" % roundi((value / reference - 1.0) * 100.0)


func _number(value: float) -> String:
	var whole := roundi(value)
	if whole < 1000:
		return str(whole)
	return "%d %03d" % [whole / 1000, whole % 1000]


func _log_rows(current: Dictionary, problems: PackedStringArray) -> void:
	_log.info("advisor_compare result=ok power=%s launcher_ratio=%s infection_ratio=%s crit=%s/%s others=%d interval=%s problems=%s" % [_chain.power, _chain.launcher_ratio, _chain.infection_ratio, _chain.crit_chance, _chain.crit_multiplier, _chain.other_consumers, _chain.interval, ",".join(problems)])
	for row: Dictionary in _rows:
		_log.info("advisor_row current=%s payload=%s infection=%s %s" % [row.current, ",".join(row.scenario.payload), ",".join(row.scenario.infection), _row_text(row)])
	for item: Dictionary in _upgrade_rows:
		_log.info("advisor_upgrade name=%s cost=%s affordable=%s %s" % [item.upgrade.name, item.upgrade.cost, item.upgrade.affordable, _row_text(item.row)])
	_log.info("advisor_current %s" % _row_text(current))


func _row_text(row: Dictionary) -> String:
	var parts := PackedStringArray(["xp_rate=%.0f" % row.xp_rate])
	for type: String in row.targets:
		var target: Dictionary = row.targets[type]
		parts.append("%s=%d/%.2f/%.2fs/%.0f" % [type, target.level, target.chance, target.used, target.reward_rate])
	return " ".join(parts)
