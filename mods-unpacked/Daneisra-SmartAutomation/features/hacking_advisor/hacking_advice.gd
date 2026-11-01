extends RefCounted
## Turns compared rows into advice for one objective: what to change, why, the gain and the drawback.
## Pure text and arithmetic: the player decides and does everything.

const XP := "xp"
const BALANCED := "balanced"
const REWARD_NAMES := {"breach_corps": "Données", "breach_government": "Renseignements", "breach_bank": "Banque", "breach_anonymous": "Anonymous"}
## Below this, a difference is noise from the random attacks, and not worth rewiring anything.
const MIN_GAIN := 0.01
## Below this chance, the player should know a level may slip.
const SAFE_CHANCE := 0.95


static func objectives(chain: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = [{"key": XP, "label": "XP"}]
	for type: String in chain.targets:
		list.append({"key": type, "label": reward_name(chain, type)})
	list.append({"key": BALANCED, "label": "Équilibré"})
	return list


static func reward_name(chain: Dictionary, type: String) -> String:
	return REWARD_NAMES.get(type, chain.targets[type].label)


## Balanced is a geometric mean: it rewards the same relative gain on each thing, and a chain
## bringing nothing of one of them scores nothing.
static func score(row: Dictionary, objective: String) -> float:
	if objective == XP:
		return row.xp_rate
	if objective != BALANCED:
		return row.targets[objective].reward_rate
	var product: float = row.xp_rate
	for type: String in row.targets:
		product *= row.targets[type].reward_rate
	return pow(product, 1.0 / (1.0 + row.targets.size()))


## The current connections stay unless another one is really better.
static func best_row(rows: Array[Dictionary], current: Dictionary, objective: String) -> Dictionary:
	var best := current
	var limit := score(current, objective) * (1.0 + MIN_GAIN)
	for row: Dictionary in rows:
		var value := score(row, objective)
		if value > limit and value > score(best, objective):
			best = row
	return best


## Relative gain for the objective, or 1 when starting from nothing.
static func gain(row: Dictionary, current: Dictionary, objective: String) -> float:
	var before := score(current, objective)
	var after := score(row, objective)
	if before <= 0.0:
		return 1.0 if after > 0.0 else 0.0
	return after / before - 1.0


static func connection_text(chain: Dictionary, current: Dictionary, best: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append_array(_set_changes(chain, "Payload", current.scenario.payload, best.scenario.payload))
	parts.append_array(_set_changes(chain, "Infection", current.scenario.infection, best.scenario.infection))
	if best.scenario.infection.is_empty() and not current.scenario.infection.is_empty():
		parts.append("Débranchez aussi le Produit d'infection de l'Interface, pour rendre sa puissance au Lanceur")
	elif current.scenario.infection.is_empty() and not best.scenario.infection.is_empty():
		parts.append("Branchez aussi l'Interface sur le Produit d'infection, ce qui partage sa puissance")
	return ". ".join(parts) + "."


## What changes on each target. An unchanged target is left out.
static func why_text(chain: Dictionary, current: Dictionary, row: Dictionary) -> String:
	var parts := PackedStringArray()
	for type: String in row.targets:
		var before: Dictionary = current.targets[type]
		var after: Dictionary = row.targets[type]
		var label: String = chain.targets[type].label
		if after.level < 0 and before.level >= 0:
			parts.append("%s ne reçoit plus assez de dégâts" % label)
		elif after.level != before.level:
			parts.append("%s passe du niveau %d au niveau %d" % [label, before.level, after.level])
		elif after.level >= 0 and after.cycle < before.cycle * (1.0 - MIN_GAIN):
			parts.append("%s attaque plus vite" % label)
	return ", ".join(parts) + "." if not parts.is_empty() else "Aucun niveau ne change."


## gains and drawbacks, for everything a chain brings and not only the objective.
static func effects(chain: Dictionary, current: Dictionary, row: Dictionary) -> Dictionary:
	var gains := PackedStringArray()
	var drawbacks := PackedStringArray()
	_add_effect(gains, drawbacks, "XP", row.xp_rate, current.xp_rate)
	for type: String in row.targets:
		_add_effect(gains, drawbacks, reward_name(chain, type), row.targets[type].reward_rate, current.targets[type].reward_rate)
		var target: Dictionary = row.targets[type]
		if target.level >= 0 and target.chance < SAFE_CHANCE:
			drawbacks.append("%s moins sûr (%d %% de réussite)" % [chain.targets[type].label, roundi(target.chance * 100.0)])
	return {
		"gains": ", ".join(gains) if not gains.is_empty() else "aucun",
		"drawbacks": ", ".join(drawbacks) if not drawbacks.is_empty() else "aucun",
	}


static func percent(value: float, reference: float) -> String:
	if reference <= 0.0:
		return "–"
	return "%+d %%" % roundi((value / reference - 1.0) * 100.0)


static func _add_effect(gains: PackedStringArray, drawbacks: PackedStringArray, name: String, value: float, reference: float) -> void:
	if reference <= 0.0:
		if value > 0.0:
			gains.append("%s en plus" % name)
		return
	var change := value / reference - 1.0
	if change >= MIN_GAIN:
		gains.append("%s %s" % [name, percent(value, reference)])
	elif change <= -MIN_GAIN:
		drawbacks.append("%s %s" % [name, percent(value, reference)])


static func _of(label: String) -> String:
	return ("d'%s" if "AEIOU".contains(label.left(1)) else "de %s") % label


static func _set_changes(chain: Dictionary, name: String, before: Array, after: Array) -> PackedStringArray:
	var parts := PackedStringArray()
	for type: String in after:
		if not before.has(type):
			parts.append("%s : brancher vers %s" % [name, chain.targets[type].label])
	for type: String in before:
		if not after.has(type):
			parts.append("%s : débrancher %s" % [name, _of(chain.targets[type].label)])
	return parts
