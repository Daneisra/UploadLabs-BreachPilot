extends Node
## Ctrl+Alt+F8: compares the ways of connecting the hacking chain. Read-only: the player decides.

const HackingChain := preload("hacking_chain.gd")
const HackingModel := preload("hacking_model.gd")
const AdvisorPanel := preload("advisor_panel.gd")

const ERROR_TEXTS := {
	"no_desktop": "Aucune partie en cours.",
	"chain_shape": "Il faut une seule Interface de hacking, un seul Lanceur Payload, et au plus une infection, un Payload critique et un nœud par cible.",
	"no_target": "Aucun nœud d'infiltration trouvé.",
	"no_payload": "Aucune cible ne reçoit de Payload : rien à comparer pour l'instant.",
	"no_attack_seen": "Le mod n'a pas encore vu d'attaque : réessayez dans quelques secondes.",
}

var _log: Variant
var _observer: Variant
var _margin := 0.1
var _required_success := 0.99
var _panel: AdvisorPanel
var _chain: Dictionary
var _model: HackingModel
var _pending: Array[Dictionary] = []
var _rows: Array[Dictionary] = []


func configure(logger: Variant, observer: Variant, margin: float, required_success: float) -> void:
	_log = logger
	_observer = observer
	_margin = margin
	_required_success = required_success


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
	var desktop: Variant = get_tree().root.get_node("Globals").desktop
	_chain = HackingChain.read(desktop, _observer.attack_intervals(), _margin, _required_success)
	if _chain.error != "":
		_log.info("advisor_compare result=%s" % _chain.error)
		_panel.show_message(ERROR_TEXTS.get(_chain.error, _chain.error))
		return
	_model = HackingModel.new(_chain)
	_pending = _model.scenarios()
	_rows = []
	set_process(true)


## One scenario per frame: the game must not stutter for a panel.
func _process(_delta: float) -> void:
	if not _panel.visible:
		set_process(false)
		return
	_rows.append(_model.evaluate(_pending.pop_back()))
	if not _pending.is_empty():
		return
	set_process(false)
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.xp_rate > b.xp_rate)
	var problems := _model.chain_problems()
	_log_rows(_chain, _rows, problems)
	_show(_chain, _rows, problems)


func _show(chain: Dictionary, rows: Array[Dictionary], problems: PackedStringArray) -> void:
	var types: Array = chain.targets.keys()
	var table: Array = []
	var kinds: Array = []
	var header := ["Payload vers", "Infection vers"]
	for type: String in types:
		header.append(chain.targets[type].label)
	header.append("XP/min")
	for type: String in types:
		header.append("Gains %s/min" % chain.targets[type].label)
	table.append(header)
	kinds.append("header")

	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var cells := [_names(chain, row.scenario.payload), _names(chain, row.scenario.infection)]
		for type: String in types:
			cells.append(_level_text(row.targets[type]))
		cells.append(_number(row.xp_rate))
		for type: String in types:
			cells.append(_number(row.targets[type].reward_rate))
		table.append(cells)
		kinds.append("current" if row.current else ("best" if index == 0 else ""))
	_panel.show_table(_summary(chain, rows[0], _current_row(rows), problems), table, kinds, _note(chain))


func _summary(chain: Dictionary, best: Dictionary, current: Variant, problems: PackedStringArray) -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("Attention : votre chaîne ne suit pas tout à fait les règles mesurées (%s). Les chiffres sont à prendre avec prudence." % ", ".join(problems))
	if current == null:
		lines.append("Votre branchement actuel ne figure pas parmi ces scénarios.")
	elif best == current:
		lines.append("Votre branchement est déjà le meilleur pour l'XP.")
	else:
		var parts := PackedStringArray()
		if current.xp_rate > 0.0:
			parts.append("XP %s" % _change(best.xp_rate, current.xp_rate))
		for type: String in chain.targets:
			if current.targets[type].reward_rate > 0.0:
				parts.append("%s %s" % [chain.targets[type].label, _change(best.targets[type].reward_rate, current.targets[type].reward_rate)])
		lines.append("Meilleur pour l'XP : Payload vers %s, infection vers %s (%s)." % [_names(chain, best.scenario.payload), _names(chain, best.scenario.infection), ", ".join(parts)])
	return "\n".join(lines)


func _note(chain: Dictionary) -> String:
	var levels := PackedStringArray()
	for type: String in chain.targets:
		levels.append("%s %d/%d" % [chain.targets[type].label, chain.targets[type].level, chain.targets[type].max_level])
	return "Niveaux réels : %s. En bleu : votre branchement. En vert : le meilleur pour l'XP.\nEstimations prudentes, avec les coups normaux : les coups critiques et les essais de niveau peuvent faire mieux. « aucune » pour l'infection suppose aussi de la débrancher de l'Interface, ce qui rend sa puissance au Lanceur." % ", ".join(levels)


func _current_row(rows: Array[Dictionary]) -> Variant:
	for row: Dictionary in rows:
		if row.current:
			return row
	return null


func _names(chain: Dictionary, types: Array) -> String:
	if types.is_empty():
		return "aucune"
	var names := PackedStringArray()
	for type: String in types:
		names.append(chain.targets[type].label)
	return " + ".join(names)


func _level_text(target: Dictionary) -> String:
	if target.invalid:
		return "non calculable"
	if target.level < 0:
		return "–"
	return "niv. %d, %.1f s" % [target.level, target.used]


func _change(value: float, reference: float) -> String:
	return "%+d %%" % roundi((value / reference - 1.0) * 100.0)


func _number(value: float) -> String:
	if value >= 10000.0:
		return "%.1fk" % (value / 1000.0)
	return "%d" % roundi(value)


func _log_rows(chain: Dictionary, rows: Array[Dictionary], problems: PackedStringArray) -> void:
	_log.info("advisor_compare result=ok power=%s launcher_ratio=%s infection_ratio=%s crit_factor=%s others=%d interval=%s problems=%s" % [chain.power, chain.launcher_ratio, chain.infection_ratio, chain.crit_factor, chain.other_consumers, chain.interval, ",".join(problems)])
	for type: String in chain.targets:
		var target: Dictionary = chain.targets[type]
		var at_level: Dictionary = target.levels[target.level]
		_log.info("advisor_target type=%s level=%d max_level=%d reward=%s cur_reward=%s xp=%s cur_xp=%s" % [type, target.level, target.max_level, at_level.reward, target.cur_reward, at_level.xp, target.cur_experience])
	for row: Dictionary in rows:
		var parts := PackedStringArray()
		for type: String in row.targets:
			var target: Dictionary = row.targets[type]
			parts.append("%s=%d/%.2fs/%.0f" % [type, target.level, target.used, target.reward_rate])
		_log.info("advisor_row current=%s payload=%s infection=%s xp_rate=%.0f %s" % [row.current, ",".join(row.scenario.payload), ",".join(row.scenario.infection), row.xp_rate, " ".join(parts)])
