extends RefCounted
## Turns compared rows into advice for one objective: what to change, why, the gain and the drawback.
## Pure text and arithmetic: the player decides and does everything.

const LevelChoice := preload("../threat_manager/level_choice.gd")
const I18n := preload("../../core/i18n.gd")

const XP := "xp"
const BALANCED := "balanced"
## Below this, a difference is noise from the random attacks, and not worth rewiring anything.
const MIN_GAIN := 0.01
## Below this chance, the player should know a level may slip.
const SAFE_CHANCE := 0.95


static func objectives(chain: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = [{"key": XP, "label": I18n.t("objective.xp")}]
	for key: String in chain.targets:
		list.append({"key": key, "label": chain.targets[key].reward_name})
	list.append({"key": BALANCED, "label": I18n.t("objective.balanced")})
	return list


## Balanced compares with the current chain, as the regulation compares levels: a chain counts when it loses
## nothing, or a little of one thing for much more of another. It is then worth the average change, and 0.0
## otherwise: doubling the XP does not make up for halving something else. What the current chain does not
## bring does not count.
static func score(row: Dictionary, objective: String, current: Dictionary) -> float:
	if objective == XP:
		return row.xp_rate
	if objective != BALANCED:
		return row.targets[objective].reward_rate
	var changes: Array[float] = [_ratio(row.xp_rate, current.xp_rate)]
	for key: String in row.targets:
		changes.append(_ratio(row.targets[key].reward_rate, current.targets[key].reward_rate))
	var low: float = changes.min()
	if low < 1.0 and (low < 1.0 - LevelChoice.MAX_LOSS or changes.max() < 1.0 + LevelChoice.MIN_TRADE):
		return 0.0
	var product := 1.0
	for change: float in changes:
		product *= change
	return pow(product, 1.0 / changes.size())


static func _ratio(value: float, reference: float) -> float:
	return value / reference if reference > 0.0 else 1.0


## The current connections stay unless another one is really better. Not fully understood: out of the ranking.
static func best_row(rows: Array[Dictionary], current: Dictionary, objective: String) -> Dictionary:
	var best := current
	var limit := score(current, objective, current) * (1.0 + MIN_GAIN)
	for row: Dictionary in rows:
		if not row.insufficient.is_empty():
			continue
		var value := score(row, objective, current)
		if value > limit and value > score(best, objective, current):
			best = row
	return best


## Balanced refuses a chain that loses too much of one thing for what it gains: not a loss of everything.
static func is_refused_trade(row: Dictionary, current: Dictionary, objective: String) -> bool:
	return objective == BALANCED and score(row, objective, current) <= 0.0 and score(current, objective, current) > 0.0


## Relative gain for the objective, or 1 when starting from nothing.
static func gain(row: Dictionary, current: Dictionary, objective: String) -> float:
	var before := score(current, objective, current)
	var after := score(row, objective, current)
	if before <= 0.0:
		return 1.0 if after > 0.0 else 0.0
	return after / before - 1.0


static func connection_text(chain: Dictionary, current: Dictionary, best: Dictionary) -> String:
	return ". ".join(steps(chain, current, best)) + "."


## One cable to change per step, in the game's names.
static func steps(chain: Dictionary, current: Dictionary, best: Dictionary) -> PackedStringArray:
	var parts := PackedStringArray()
	for kind: String in ["payload", "infection"]:
		for key: String in chain.targets:
			var before: String = current.scenario[kind][key]
			var after: String = best.scenario[kind][key]
			if before == after:
				continue
			var name: String = _stream_label(chain, after if after != "" else before, kind)
			var target: String = chain.targets[key].label
			if after != "":
				parts.append(I18n.t("step.plug", {"stream": name, "target": target}))
			else:
				parts.append(I18n.t(I18n.vowel_variant("step.unplug", target), {"stream": name, "target": target}))
	for stream: Dictionary in chain.streams.values():
		if not _feeds(stream, current.scenario) or _feeds(stream, best.scenario) or stream.source == "":
			continue
		parts.append(I18n.t("step.unplug_source", {"stream": stream.label}))
	return parts


## How far a figure can be trusted, and why: {"level": 0 to 2, "text": ..., "reasons": ...}. What the current
## chain does is measured. A stream sent where it never attacked is estimated from its hits elsewhere, and a
## level that may slip is less sure. Each doubt takes one step down.
static func reliability(chain: Dictionary, row: Dictionary) -> Dictionary:
	var reasons := PackedStringArray()
	var level := 2
	var moved := PackedStringArray()
	for kind: String in ["payload", "infection"]:
		for key: String in chain.targets:
			var stream_id: String = row.scenario[kind][key]
			if stream_id != "" and chain.streams.has(stream_id) and not chain.streams[stream_id].targets.has(key):
				moved.append(I18n.t("reliability.moved", {"stream": _stream_label(chain, stream_id, kind), "target": chain.targets[key].label}))
	if not moved.is_empty():
		level -= 1
		reasons.append(I18n.t("reliability.never_tried", {"items": ", ".join(moved)}))
	var risky := PackedStringArray()
	for key: String in row.targets:
		var target: Dictionary = row.targets[key]
		if target.level >= 0 and target.chance < SAFE_CHANCE:
			risky.append("%s %s" % [chain.targets[key].label, I18n.percent(roundi(target.chance * 100.0))])
	if not risky.is_empty():
		level -= 1
		reasons.append(I18n.t("reliability.uncertain", {"items": ", ".join(risky)}))
	if reasons.is_empty():
		reasons.append(I18n.t("reliability.measured" if row.current else "reliability.same_hits"))
	return {"level": level, "text": I18n.t("reliability.%d" % level), "reasons": "; ".join(reasons)}


## What changes on each target. An unchanged target is left out.
static func why_text(chain: Dictionary, current: Dictionary, row: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in row.targets:
		var before: Dictionary = current.targets[key]
		var after: Dictionary = row.targets[key]
		var label: String = chain.targets[key].label
		if after.level < 0 and before.level >= 0:
			parts.append(I18n.t("why.no_damage", {"target": label}))
		elif after.level != before.level:
			parts.append(I18n.t("why.level", {"target": label, "from": before.level, "to": after.level}))
		elif after.level >= 0 and after.cycle < before.cycle * (1.0 - MIN_GAIN):
			parts.append(I18n.t("why.faster", {"target": label}))
	return ", ".join(parts) + "." if not parts.is_empty() else I18n.t("why.nothing")


## gains and drawbacks, for everything a chain brings and not only the objective; has_drawbacks says
## whether there is any, so that no one has to compare the text.
static func effects(chain: Dictionary, current: Dictionary, row: Dictionary, own_drawbacks: PackedStringArray = PackedStringArray()) -> Dictionary:
	var gains := PackedStringArray()
	var drawbacks := own_drawbacks.duplicate()
	_add_effect(gains, drawbacks, "XP", row.xp_rate, current.xp_rate)
	for key: String in row.targets:
		_add_effect(gains, drawbacks, chain.targets[key].reward_name, row.targets[key].reward_rate, current.targets[key].reward_rate)
		var target: Dictionary = row.targets[key]
		if target.level >= 0 and target.chance < SAFE_CHANCE:
			drawbacks.append(I18n.t("effects.less_sure", {"target": chain.targets[key].label, "chance": I18n.percent(roundi(target.chance * 100.0))}))
	return {
		"gains": ", ".join(gains) if not gains.is_empty() else I18n.t("effects.none"),
		"drawbacks": ", ".join(drawbacks) if not drawbacks.is_empty() else I18n.t("effects.none"),
		"has_drawbacks": not drawbacks.is_empty(),
	}


static func percent(value: float, reference: float) -> String:
	if reference <= 0.0:
		return "–"
	return I18n.percent(roundi((value / reference - 1.0) * 100.0), true)


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
			gains.append(I18n.t("effects.extra", {"name": name}))
		return
	var change := value / reference - 1.0
	if change >= MIN_GAIN:
		gains.append("%s %s" % [name, percent(value, reference)])
	elif change <= -MIN_GAIN:
		drawbacks.append("%s %s" % [name, percent(value, reference)])

