extends RefCounted
## State machine classifying what happens to one Breach window. It has no dependency on the game.
##
## The game emits no failure event, so failures are deduced: failure_power only appears when every
## clue agrees, and anything uncertain becomes reset_unknown.
##
## Samples are dictionaries with: instance_id, level, max_level, time, max_time, detected, paused,
## firewall, max_firewall, breached, max_breach, damage_rate, vulnerability, tick_speed, now_usec.
## time, max_time and tick_speed are all in seconds of the window's timer.

enum State { UNBOUND, IDLE, ATTACKING, SUSPENDED }

const THRESHOLD_TICKS := 2.0
const THRESHOLD_STEPS := 1.5
const CONTINUOUS_MARGIN := 1.5
const EPSILON_DAMAGE := 1e-6

var state: State = State.UNBOUND

var _starvation_ratio: float
var _previous: Dictionary = {}
var _cycle: Dictionary = {}
var _next_cycle_id := 1


func _init(starvation_ratio: float = 0.25) -> void:
	_starvation_ratio = starvation_ratio


## Feeds the snapshot of one tick. Returns the events it completed.
func observe(sample: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _previous.is_empty():
		if sample.detected:
			_open_cycle(sample, true)
		_finish_observe(sample)
		return events
	if sample.instance_id != _previous.instance_id:
		events.append_array(invalidate("instance_replaced"))
		if sample.detected:
			_open_cycle(sample, true)
		_finish_observe(sample)
		return events

	if not _cycle.is_empty() and _is_reset(sample):
		events.append(_classify_reset(sample))
		_cycle = {}
		if sample.detected:
			_open_cycle(sample, false)
	elif not _cycle.is_empty():
		_update_cycle(sample)
	elif sample.detected:
		_open_cycle(sample, false)

	if sample.level != _previous.level and events.is_empty():
		events.append({"event": "level_changed", "from": _previous.level, "to": sample.level})
	_finish_observe(sample)
	return events


## Must be called from the breached signal, while the window still holds the values of the attack.
func on_breached(sample: Dictionary) -> Array[Dictionary]:
	var observed_start := not _cycle.is_empty()
	if not observed_start:
		_open_cycle(sample, true)
		_cycle.observed_start = false
	if _is_volley(sample, _dealt(sample) - _cycle.last_progress):
		_cycle.volleys += 1
	_record_hit(sample)
	_cycle.infection_end = sample.infection_count
	if sample.damage_rate != _cycle.damage_rate:
		_cycle.damage_changed = true
	var used: float = sample.max_time - sample.time
	var event := _base_event("success", sample)
	event.time_left = sample.time
	event.used = used
	event.ratio = used / sample.max_time if sample.max_time > 0.0 else 0.0
	event.complete = not _cycle.partial and not _cycle.paused_seen and not _cycle.level_mismatch and not _cycle.damage_changed
	event.level_after = sample.level
	_set_hits(event)
	_cycle = {}
	return [event]


## The window disappeared or the desktop was rebuilt: nothing can be concluded about the open cycle.
func invalidate(reason: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _cycle.is_empty():
		events.append({"event": "invalidated", "cycle_id": _cycle.id, "reason": reason})
	_cycle = {}
	_previous = {}
	state = State.UNBOUND
	return events


func _finish_observe(sample: Dictionary) -> void:
	_previous = sample
	if sample.paused:
		state = State.SUSPENDED
	elif _cycle.is_empty():
		state = State.IDLE
	else:
		state = State.ATTACKING


## An attack can restart in the tick after a reset, so a rising timer is a reset as well.
func _is_reset(sample: Dictionary) -> bool:
	return not sample.detected or sample.time > _previous.time


func _classify_reset(sample: Dictionary) -> Dictionary:
	if sample.level != _cycle.level:
		var changed := _base_event("level_changed_reset", _previous)
		changed.level_after = sample.level
		return changed

	var threshold := maxf(THRESHOLD_TICKS * sample.tick_speed, THRESHOLD_STEPS * _cycle.max_step)
	var clues := PackedStringArray()
	if _previous.time > threshold:
		clues.append("time_not_expired")
	if sample.time < sample.max_time - threshold:
		clues.append("time_not_rearmed")
	if not clues.is_empty():
		return _unknown_reset(clues)

	if _cycle.paused_seen or sample.paused:
		return _base_event("failure_paused", _previous)
	var progress_age: float = _cycle.last_progress_time - _previous.time
	if not _cycle.progressed or progress_age > _starvation_ratio * _previous.max_time:
		var starved := _base_event("failure_starved", _previous)
		starved.progress_age = progress_age
		return starved

	if _cycle.partial:
		clues.append("partial_cycle")
	if _cycle.level_mismatch:
		clues.append("level_mismatch")
	if _cycle.damage_changed:
		clues.append("damage_changed")
	if not clues.is_empty():
		return _unknown_reset(clues)
	var failure := _base_event("failure_power", _previous)
	failure.threshold = threshold
	failure.complete = true
	_set_hits(failure)
	return failure


func _unknown_reset(clues: PackedStringArray) -> Dictionary:
	var unknown := _base_event("reset_unknown", _previous)
	unknown.clues = ",".join(clues)
	return unknown


func _open_cycle(sample: Dictionary, partial: bool) -> void:
	var threshold: float = THRESHOLD_TICKS * sample.tick_speed
	_cycle = {
		"id": _next_cycle_id,
		"level": sample.level,
		"observed_start": not partial,
		"partial": partial or sample.time < sample.max_time - threshold,
		"paused_seen": sample.paused,
		"level_mismatch": false,
		"progressed": false,
		"volleys": 0,
		"damage_rate": sample.damage_rate,
		"damage_changed": false,
		"min_hit": -1.0,
		"max_hit": -1.0,
		"last_breached": sample.breached,
		"breach_variation": sample.breach_variation,
		"infection_variation": sample.infection_variation,
		"infection_start": sample.infection_count,
		"infection_end": sample.infection_count,
		"infection_integral": 0.0,
		"last_progress": _dealt(sample),
		"last_progress_time": sample.time,
		"max_step": 0.0,
		"step_sum": 0.0,
		"steps": 0,
		"started_usec": sample.now_usec,
	}
	if _dealt(sample) > 0.0:
		_cycle.progressed = true
		if _is_volley(sample, _dealt(sample)):
			_cycle.volleys = 1
	_next_cycle_id += 1


func _update_cycle(sample: Dictionary) -> void:
	var step: float = _previous.time - sample.time
	if step > 0.0:
		_cycle.max_step = maxf(_cycle.max_step, step)
		_cycle.step_sum += step
		_cycle.steps += 1
		_cycle.infection_integral += sample.infection_count * step
	_cycle.breach_variation |= sample.breach_variation
	_cycle.infection_variation |= sample.infection_variation
	_cycle.infection_end = sample.infection_count
	if sample.paused:
		_cycle.paused_seen = true
	if sample.level != _cycle.level:
		_cycle.level_mismatch = true
	if sample.damage_rate != _cycle.damage_rate:
		_cycle.damage_changed = true
	_record_hit(sample)
	var dealt := _dealt(sample)
	if dealt > _cycle.last_progress:
		_cycle.progressed = true
		if _is_volley(sample, dealt - _cycle.last_progress):
			_cycle.volleys += 1
		_cycle.last_progress = dealt
		_cycle.last_progress_time = sample.time


func _dealt(sample: Dictionary) -> float:
	return sample.max_firewall - sample.firewall + sample.breached


## What infection should deal during one tick. It is an estimate until measured in the game.
func _continuous_damage(sample: Dictionary) -> float:
	return sample.infection_count * (1.0 + sample.vulnerability) * sample.tick_speed


## Separates volleys from damage over time, which also raises the bars at every tick.
func _is_volley(sample: Dictionary, delta: float) -> bool:
	if sample.infection_count <= 0.0:
		return delta > 0.0
	return delta > CONTINUOUS_MARGIN * _continuous_damage(sample) + EPSILON_DAMAGE


## Hits on the breach bar show the real damage: unlike firewall hits, they are not cut short.
func _record_hit(sample: Dictionary) -> void:
	var delta: float = sample.breached - _cycle.last_breached
	_cycle.last_breached = sample.breached
	if not _is_volley(sample, delta):
		return
	var hit := delta - _continuous_damage(sample)
	_cycle.min_hit = hit if _cycle.min_hit < 0.0 else minf(_cycle.min_hit, hit)
	_cycle.max_hit = maxf(_cycle.max_hit, hit)


func _set_hits(event: Dictionary) -> void:
	if _cycle.max_hit >= 0.0:
		event.min_hit = _cycle.min_hit
		event.max_hit = _cycle.max_hit


func _base_event(event_name: String, sample: Dictionary) -> Dictionary:
	var event := _core_event(event_name, sample)
	if _cycle.breach_variation != 0:
		event.breach_variation = _cycle.breach_variation
	if _cycle.infection_variation != 0:
		event.infection_variation = _cycle.infection_variation
	if _cycle.infection_integral > 0.0 or _cycle.infection_start > 0.0 or _cycle.infection_end > 0.0:
		event.infection_start = _cycle.infection_start
		event.infection_end = _cycle.infection_end
		event.infection_integral = _cycle.infection_integral
		event.dealt_total = _dealt(sample)
	return event


func _core_event(event_name: String, sample: Dictionary) -> Dictionary:
	var steps: int = _cycle.steps
	return {
		"event": event_name,
		"cycle_id": _cycle.id,
		"level": _cycle.level,
		"max_level": sample.max_level,
		"max_time": sample.max_time,
		"max_firewall": sample.max_firewall,
		"max_breach": sample.max_breach,
		"damage_rate": sample.damage_rate,
		"vulnerability": sample.vulnerability,
		"observed_start": _cycle.observed_start,
		"complete": false,
		"volleys": _cycle.volleys,
		"steps": steps,
		"max_step": _cycle.max_step,
		"mean_step": _cycle.step_sum / steps if steps > 0 else 0.0,
		"real_seconds": (sample.now_usec - _cycle.started_usec) / 1000000.0,
	}
