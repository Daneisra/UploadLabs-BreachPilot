extends RefCounted
## Measures what happens between two attacks of one Breach window. Pure: it has no access to the
## game, keeps only the attack being measured, and only returns records.
##
## Samples are dictionaries with: hook, usec, frame, tick, detected, paused, time, max_time, firewall,
## max_firewall, breached, infection_count, level, tick_speed, damage_rate, infection_rate, offscreen,
## native. The hook tells where in the frame the sample was taken.
##
## Knowing the result of an attack is not the same as the window being free: the window counts as
## available only once it shows no attack, no pause, no damage and a rearmed timer.

enum Phase { UNKNOWN, ATTACK, IDLE }

const EPSILON := 1e-6
## How long the other signs of an attack start, and its result, are awaited after the first sign.
const FOLLOW_FRAMES := 60
const STALE_RESULT_USEC := 5000000

var results_unmatched := 0
var gaps_interrupted := 0

var _phase: Phase = Phase.UNKNOWN
var _last: Dictionary = {}
var _gap: Dictionary = {}
var _starting: Dictionary = {}
var _pending_result: Dictionary = {}
var _change: Dictionary = {}
var _changes: Dictionary = {}


## Feeds one sample. Returns the records it completed.
func feed(sample: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if _last.is_empty():
		_phase = Phase.ATTACK if _busy(sample) else Phase.UNKNOWN
		_last = sample
		return records
	_note_changes(sample)
	if sample.level != _last.level:
		if not _change.is_empty():
			records.append(_close_change("superseded", {}))
		_open_change(sample)
		if not _gap.is_empty():
			_gap.level_changed = true
	if not _change.is_empty():
		_follow_change(sample)
	if not _gap.is_empty() and sample.tick_speed != _last.tick_speed:
		_gap.speed_changed = true
	if not _starting.is_empty():
		_follow_start(sample, records)
	match _phase:
		Phase.UNKNOWN:
			if _busy(sample):
				_phase = Phase.ATTACK
		Phase.ATTACK:
			if not _busy(sample):
				_open_gap(sample, false, records)
				_phase = Phase.IDLE
				_mark_available(sample)
			elif _restarted(sample):
				_open_gap(sample, true, records)
				_begin_start(sample, records)
		Phase.IDLE:
			if _busy(sample):
				_begin_start(sample, records)
				_phase = Phase.ATTACK
			else:
				_mark_available(sample)
				if _gap.pile.is_empty() and sample.infection_count != _gap.pile_idle:
					_gap.pile = _stamp(sample)
	_last = sample
	return records


## The classifier concluded an attack. stamp holds hook, usec, frame and tick.
func note_result(event_name: String, stamp: Dictionary, details: Dictionary = {}) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if event_name == "level_changed" or event_name == "invalidated":
		return records
	if not _change.is_empty():
		if event_name == "level_changed_reset":
			_change.reset_event = event_name
		else:
			records.append(_close_change(event_name, details))
	if not _gap.is_empty() and _gap.result.is_empty():
		_gap.result = event_name
		_gap.known = stamp
	elif not _starting.is_empty() and _starting.result.is_empty():
		_starting.result = event_name
		_starting.known = stamp
		_finish_start_if_ready(stamp.frame, records)
	else:
		if not _pending_result.is_empty():
			results_unmatched += 1
		_pending_result = {"result": event_name, "known": stamp}
	return records


## The window is gone or the measure stops: what is already measured is returned, the rest is dropped.
func finish() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if not _starting.is_empty():
		records.append(_gap_record(_starting))
		_starting = {}
	if not _gap.is_empty():
		gaps_interrupted += 1
		_gap = {}
	if not _change.is_empty():
		records.append(_close_change("none", {}))
	_pending_result = {}
	_last = {}
	_phase = Phase.UNKNOWN
	return records


## Is the window free right now, according to the latest sample?
func is_available() -> bool:
	return _phase == Phase.IDLE and not _last.is_empty() and _available(_last)


## Where each change was first seen, as "field@hook": count. Returned once, then counted anew.
func take_changes() -> Dictionary:
	var changes := _changes
	_changes = {}
	return changes


func _busy(sample: Dictionary) -> bool:
	return sample.detected or _dealt(sample) > EPSILON


func _dealt(sample: Dictionary) -> float:
	return sample.max_firewall - sample.firewall + sample.breached


func _available(sample: Dictionary) -> bool:
	return not _busy(sample) and not sample.paused and sample.time >= sample.max_time - EPSILON


## An attack can follow the previous one with no free state in between.
func _restarted(sample: Dictionary) -> bool:
	return sample.time > _last.time + EPSILON or _dealt(sample) < _dealt(_last) - EPSILON


func _stamp(sample: Dictionary) -> Dictionary:
	return {"hook": sample.hook, "usec": sample.usec, "frame": sample.frame, "tick": sample.tick}


func _note_changes(sample: Dictionary) -> void:
	if sample.time != _last.time:
		_count_change("time", sample.hook)
	if sample.firewall != _last.firewall or sample.breached != _last.breached:
		_count_change("damage", sample.hook)
	if sample.detected != _last.detected:
		_count_change("detected", sample.hook)
	if sample.level != _last.level:
		_count_change("level", sample.hook)
	if sample.max_time != _last.max_time:
		_count_change("max_time", sample.hook)
	if sample.infection_count != _last.infection_count:
		_count_change("pile", sample.hook)


func _count_change(field: String, hook: String) -> void:
	var key := "%s@%s" % [field, hook]
	_changes[key] = _changes.get(key, 0) + 1


func _open_gap(sample: Dictionary, no_idle: bool, records: Array[Dictionary]) -> void:
	if not _starting.is_empty():
		records.append(_gap_record(_starting))
		_starting = {}
	if not _gap.is_empty():
		gaps_interrupted += 1
	_gap = {
		"result": "", "known": {},
		"last_attack": _stamp(_last), "idle": {} if no_idle else _stamp(sample), "available": {}, "last_idle": {},
		"start": {}, "detected": {}, "damage": {}, "pile": {},
		"level": _last.level, "tick_speed": _last.tick_speed, "damage_rate": _last.damage_rate,
		"infection_rate": _last.infection_rate, "offscreen": _last.offscreen,
		"time_end": _last.time, "time_idle": sample.time, "max_time": sample.max_time,
		"firewall_idle": sample.firewall, "breached_idle": sample.breached,
		"pile_end": _last.infection_count, "pile_idle": sample.infection_count,
		"armed_at_idle": sample.time >= sample.max_time - EPSILON,
		"level_changed": false, "speed_changed": false,
	}
	if not _pending_result.is_empty():
		if sample.usec - _pending_result.known.usec <= STALE_RESULT_USEC:
			_gap.result = _pending_result.result
			_gap.known = _pending_result.known
		else:
			results_unmatched += 1
		_pending_result = {}


func _mark_available(sample: Dictionary) -> void:
	if _gap.available.is_empty() and _available(sample):
		_gap.available = _stamp(sample)


func _begin_start(sample: Dictionary, records: Array[Dictionary]) -> void:
	_gap.start = _stamp(sample)
	_gap.last_idle = _stamp(_last)
	_starting = _gap
	_gap = {}
	_follow_start(sample, records)


func _follow_start(sample: Dictionary, records: Array[Dictionary]) -> void:
	if _starting.detected.is_empty() and sample.detected:
		_starting.detected = _stamp(sample)
	if _starting.damage.is_empty() and _dealt(sample) > EPSILON:
		_starting.damage = _stamp(sample)
	if _starting.pile.is_empty() and sample.infection_count != _starting.pile_idle:
		_starting.pile = _stamp(sample)
	_finish_start_if_ready(sample.frame, records)


func _finish_start_if_ready(frame: int, records: Array[Dictionary]) -> void:
	var signs_seen: bool = not _starting.detected.is_empty() and not _starting.damage.is_empty()
	if (signs_seen and not _starting.result.is_empty()) or frame - _starting.start.frame > FOLLOW_FRAMES:
		records.append(_gap_record(_starting))
		_starting = {}


func _gap_record(gap: Dictionary) -> Dictionary:
	var record := gap.duplicate()
	record.kind = "gap"
	var result: String = gap.result if not gap.result.is_empty() else "unlabeled"
	if gap.level_changed:
		result += "+level_change"
	if gap.speed_changed:
		result += "+speed_change"
	record.case_result = result
	record.no_window = gap.available.is_empty()
	record.raw_us = 0
	record.raw_frames = 0
	record.raw_ticks = 0
	record.usable_us = 0
	record.usable_frames = 0
	record.usable_ticks = 0
	record.known_after_start = not gap.known.is_empty() and gap.known.usec > gap.start.usec
	if not record.no_window:
		record.raw_us = gap.start.usec - gap.available.usec
		record.raw_frames = gap.start.frame - gap.available.frame
		record.raw_ticks = gap.start.tick - gap.available.tick
		var from: Dictionary = gap.available
		if not gap.known.is_empty() and gap.known.usec > from.usec:
			from = gap.known
		record.usable_us = maxi(gap.start.usec - from.usec, 0)
		record.usable_frames = maxi(gap.start.frame - from.frame, 0)
		record.usable_ticks = maxi(gap.start.tick - from.tick, 0)
	# The real edges lie somewhere between two samples.
	var first_idle: Dictionary = gap.idle if not gap.idle.is_empty() else gap.start
	record.uncertainty_us = first_idle.usec - gap.last_attack.usec + gap.start.usec - gap.last_idle.usec
	record.known_to_available_us = -1
	record.known_to_available_frames = -1
	if not gap.known.is_empty() and not record.no_window:
		record.known_to_available_us = gap.available.usec - gap.known.usec
		record.known_to_available_frames = gap.available.frame - gap.known.frame
	record.start_sign = "same"
	if gap.detected.is_empty() or gap.damage.is_empty():
		record.start_sign = "damage_only" if gap.detected.is_empty() else "detected_only"
	elif gap.detected.usec < gap.damage.usec:
		record.start_sign = "detected_first"
	elif gap.damage.usec < gap.detected.usec:
		record.start_sign = "damage_first"
	return record


func _open_change(sample: Dictionary) -> void:
	var state := "unknown"
	if _phase == Phase.IDLE:
		state = "available" if _available(_last) else "idle_not_available"
	elif _phase == Phase.ATTACK:
		state = "ending" if not _pending_result.is_empty() else "attack"
	var since_known: int = sample.usec - _pending_result.known.usec if not _pending_result.is_empty() else -1
	_change = {
		"kind": "level_change", "from": _last.level, "to": sample.level, "state": state, "native": sample.native,
		"hook": sample.hook, "usec": sample.usec, "frame": sample.frame, "tick": sample.tick,
		"since_known_us": since_known, "time_before": _last.time, "detected_before": _last.detected,
		"dealt_before": _dealt(_last), "max_time_before": _last.max_time,
		"reset_frames": -1, "max_time_frames": -1, "max_firewall_frames": -1, "reset_event": "none",
	}


## How long the visible effects of a level change take, in frames.
func _follow_change(sample: Dictionary) -> void:
	var frames: int = sample.frame - _change.frame
	if _change.reset_frames < 0 and _change.state != "available" and (sample.time > _last.time + EPSILON or (_last.detected and not sample.detected)):
		_change.reset_frames = frames
	if _change.max_time_frames < 0 and sample.max_time != _last.max_time:
		_change.max_time_frames = frames
	if _change.max_firewall_frames < 0 and sample.max_firewall != _last.max_firewall:
		_change.max_firewall_frames = frames


func _close_change(next_event: String, details: Dictionary) -> Dictionary:
	var record := _change
	record.next_event = next_event
	for field: String in ["used", "complete", "volleys", "level"]:
		if details.has(field):
			record["next_%s" % field] = details[field]
	_change = {}
	return record
