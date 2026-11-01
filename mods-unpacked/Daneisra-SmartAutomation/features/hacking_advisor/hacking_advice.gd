extends RefCounted
## Turns compared rows into advice for one objective: what to change, why, the gain and the drawback.
## Pure text and arithmetic: the player decides and does everything.

const XP := "xp"
const BALANCED := "balanced"
## Below this, a difference is noise from the random attacks, and not worth rewiring anything.
const MIN_GAIN := 0.01
## Below this chance, the player should know a level may slip.
const SAFE_CHANCE := 0.95


static func objectives(chain: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = [{"key": XP, "label": "XP"}]
	for key: String in chain.targets:
		list.append({"key": key, "label": chain.targets[key].reward_name})
	list.append({"key": BALANCED, "label": "Équilibré"})
	return list


## Balanced is a geometric mean: it rewards the same relative gain on each thing, and a chain
## bringing nothing of one of them scores nothing.
static func score(row: Dictionary, objective: String) -> float:
	if objective == XP:
		return row.xp_rate
	if objective != BALANCED:
		return row.targets[objective].reward_rate
	var product: float = row.xp_rate
	for key: String in row.targets:
		product *= row.targets[key].reward_rate
	return pow(product, 1.0 / (1.0 + row.targets.size()))


## The current connections stay unless another one is really better. Not fully understood: out of the ranking.
static func best_row(rows: Array[Dictionary], current: Dictionary, objective: String) -> Dictionary:
	var best := current
	var limit := score(current, objective) * (1.0 + MIN_GAIN)
	for row: Dictionary in rows:
		if not row.insufficient.is_empty():
			continue
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
	for kind: String in ["payload", "infection"]:
		for key: String in chain.targets:
			var before: String = current.scenario[kind][key]
			var after: String = best.scenario[kind][key]
			if before == after:
				continue
			var name: String = _stream_label(chain, after if after != "" else before, kind)
			var target: String = chain.targets[key].label
			parts.append("%s : brancher vers %s" % [name, target] if after != "" else "%s : débrancher %s" % [name, _of(target)])
	for stream: Dictionary in chain.streams.values():
		if not _feeds(stream, current.scenario) or _feeds(stream, best.scenario) or stream.source == "":
			continue
		parts.append("Débranchez aussi %s de sa source, pour rendre sa puissance aux autres" % stream.label)
	return ". ".join(parts) + "."


## What changes on each target. An unchanged target is left out.
static func why_text(chain: Dictionary, current: Dictionary, row: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in row.targets:
		var before: Dictionary = current.targets[key]
		var after: Dictionary = row.targets[key]
		var label: String = chain.targets[key].label
		if after.level < 0 and before.level >= 0:
			parts.append("%s ne reçoit plus assez de dégâts" % label)
		elif after.level != before.level:
			parts.append("%s passe du niveau %d au niveau %d" % [label, before.level, after.level])
		elif after.level >= 0 and after.cycle < before.cycle * (1.0 - MIN_GAIN):
			parts.append("%s attaque plus vite" % label)
	return ", ".join(parts) + "." if not parts.is_empty() else "Aucun niveau ne change."


## gains and drawbacks, for everything a chain brings and not only the objective.
static func effects(chain: Dictionary, current: Dictionary, row: Dictionary, own_drawbacks: PackedStringArray = PackedStringArray()) -> Dictionary:
	var gains := PackedStringArray()
	var drawbacks := own_drawbacks.duplicate()
	_add_effect(gains, drawbacks, "XP", row.xp_rate, current.xp_rate)
	for key: String in row.targets:
		_add_effect(gains, drawbacks, chain.targets[key].reward_name, row.targets[key].reward_rate, current.targets[key].reward_rate)
		var target: Dictionary = row.targets[key]
		if target.level >= 0 and target.chance < SAFE_CHANCE:
			drawbacks.append("%s moins sûr (%d %% de réussite)" % [chain.targets[key].label, roundi(target.chance * 100.0)])
	return {
		"gains": ", ".join(gains) if not gains.is_empty() else "aucun",
		"drawbacks": ", ".join(drawbacks) if not drawbacks.is_empty() else "aucun",
	}


static func percent(value: float, reference: float) -> String:
	if reference <= 0.0:
		return "–"
	return "%+d %%" % roundi((value / reference - 1.0) * 100.0)


static func _feeds(stream: Dictionary, scenario: Dictionary) -> bool:
	if stream.kind == "vulnerability":
		return scenario.vulnerability
	return scenario.has(stream.kind) and scenario[stream.kind].values().has(stream.id)


static func _stream_label(chain: Dictionary, stream_id: String, kind: String) -> String:
	if chain.streams.has(stream_id) and chain.streams[stream_id].label != "":
		return chain.streams[stream_id].label
	return kind.capitalize()


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
