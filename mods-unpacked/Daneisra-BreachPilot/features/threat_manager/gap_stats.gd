extends RefCounted
## Totals of the gap measures, by case. Pure, with a fixed upper bound on what it keeps.

const MAX_CASES := 64
const MAX_BUCKET := 240
const SEQUENCES_PER_CASE := 20
const MAX_SEQUENCES := 300
const REPORT_EVERY := 100

var cases_dropped := 0

var _cases: Dictionary = {}
var _sequences := 0
var _common: Dictionary = {}
var _changes: Dictionary = {}


## Adds a gap record. Returns whether to log its sequence, and the case to report, if any.
func add(type: String, record: Dictionary) -> Dictionary:
	var key := "%s|%s|%s|%d|%.1f|%.1f|%s" % [type, record.case_result, record.tick_speed, record.level, record.damage_rate, record.infection_rate, record.offscreen]
	if not _cases.has(key):
		if _cases.size() >= MAX_CASES:
			cases_dropped += 1
			return {"sequence": false, "report": ""}
		_cases[key] = _new_case(type, record)
	var entry: Dictionary = _cases[key]
	entry.n += 1
	entry.no_window += 1 if record.no_window else 0
	entry.known_after_start += 1 if record.known_after_start else 0
	entry.not_armed += 0 if record.get("armed_at_idle", true) else 1
	entry.uncertainty_max = maxi(entry.uncertainty_max, record.uncertainty_us)
	if record.known_to_available_us >= 0:
		entry.known_to_available_max = maxi(entry.known_to_available_max, record.known_to_available_us)
	entry.known_before_available += 1 if record.known_to_available_frames > 0 else 0
	_bump(entry.signs, record.start_sign)
	_add_range(entry.raw_us, record.raw_us)
	_add_range(entry.usable_us, record.usable_us)
	_bump(entry.raw_frames, _bucket(record.raw_frames))
	_bump(entry.usable_frames, _bucket(record.usable_frames))
	_bump(entry.raw_ticks, _bucket(record.raw_ticks))
	_bump(entry.usable_ticks, _bucket(record.usable_ticks))
	entry.usable_frames_min = mini(entry.usable_frames_min, record.usable_frames)
	entry.usable_ticks_min = mini(entry.usable_ticks_min, record.usable_ticks)

	var sequence: bool = entry.sequences < SEQUENCES_PER_CASE and _sequences < MAX_SEQUENCES
	if sequence:
		entry.sequences += 1
		_sequences += 1
	return {"sequence": sequence, "report": key if entry.n % REPORT_EVERY == 0 else ""}


## Several windows of one type share its level, so a change would need all of them free at once.
func note_common(type: String, nodes: int, all_available: bool) -> void:
	if not _common.has(type):
		_common[type] = {"nodes": nodes, "frames": 0, "available": 0, "run": 0, "runs": 0, "shortest": -1, "longest": 0}
	var entry: Dictionary = _common[type]
	entry.nodes = nodes
	entry.frames += 1
	if all_available:
		entry.available += 1
		entry.run += 1
	elif entry.run > 0:
		entry.runs += 1
		entry.shortest = entry.run if entry.shortest < 0 else mini(entry.shortest, entry.run)
		entry.longest = maxi(entry.longest, entry.run)
		entry.run = 0


func add_changes(type: String, changes: Dictionary) -> void:
	if not _changes.has(type):
		_changes[type] = {}
	for key: String in changes:
		_changes[type][key] = _changes[type].get(key, 0) + changes[key]


func case_line(key: String) -> String:
	var entry: Dictionary = _cases[key]
	return "gap_case type=%s result=%s tick_speed=%s level=%d damage_rate=%.2f infection_rate=%.2f offscreen=%s n=%d no_window=%d known_after_start=%d not_armed=%d known_before_available=%d raw_ms=%s usable_ms=%s usable_frames_min=%d usable_ticks_min=%d uncertainty_ms_max=%.1f known_to_available_ms_max=%.1f signs=%s raw_frames=%s usable_frames=%s raw_ticks=%s usable_ticks=%s" % [
		entry.type, entry.result, entry.tick_speed, entry.level, entry.damage_rate, entry.infection_rate, entry.offscreen,
		entry.n, entry.no_window, entry.known_after_start, entry.not_armed, entry.known_before_available,
		_range_text(entry.raw_us), _range_text(entry.usable_us), entry.usable_frames_min, entry.usable_ticks_min,
		entry.uncertainty_max / 1000.0, entry.known_to_available_max / 1000.0, JSON.stringify(entry.signs),
		JSON.stringify(entry.raw_frames), JSON.stringify(entry.usable_frames), JSON.stringify(entry.raw_ticks), JSON.stringify(entry.usable_ticks),
	]


## Everything measured so far, for a report or the end of the session.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in _cases:
		lines.append(case_line(key))
	for type: String in _common:
		var entry: Dictionary = _common[type]
		lines.append("gap_common type=%s nodes=%d frames=%d available=%d runs=%d shortest=%d longest=%d" % [type, entry.nodes, entry.frames, entry.available, entry.runs, entry.shortest, entry.longest])
	for type: String in _changes:
		lines.append("gap_order type=%s changes=%s" % [type, JSON.stringify(_changes[type])])
	if cases_dropped > 0:
		lines.append("gap_cases_dropped count=%d" % cases_dropped)
	return lines


func _new_case(type: String, record: Dictionary) -> Dictionary:
	return {
		"type": type, "result": record.case_result, "tick_speed": record.tick_speed, "level": record.level,
		"damage_rate": record.damage_rate, "infection_rate": record.infection_rate, "offscreen": record.offscreen,
		"n": 0, "no_window": 0, "known_after_start": 0, "not_armed": 0, "known_before_available": 0,
		"uncertainty_max": 0, "known_to_available_max": 0, "sequences": 0, "signs": {},
		"raw_us": _new_range(), "usable_us": _new_range(), "raw_frames": {}, "usable_frames": {}, "raw_ticks": {}, "usable_ticks": {},
		"usable_frames_min": 1 << 40, "usable_ticks_min": 1 << 40,
	}


func _new_range() -> Dictionary:
	return {"min": 1 << 62, "max": 0, "sum": 0, "n": 0}


func _add_range(range_data: Dictionary, value: int) -> void:
	range_data.min = mini(range_data.min, value)
	range_data.max = maxi(range_data.max, value)
	range_data.sum += value
	range_data.n += 1


func _range_text(range_data: Dictionary) -> String:
	if range_data.n == 0:
		return "none"
	return "%.1f/%.1f/%.1f" % [range_data.min / 1000.0, float(range_data.sum) / range_data.n / 1000.0, range_data.max / 1000.0]


func _bump(counts: Dictionary, key: Variant) -> void:
	counts[key] = counts.get(key, 0) + 1


func _bucket(value: int) -> String:
	return "over" if value > MAX_BUCKET else str(value)
