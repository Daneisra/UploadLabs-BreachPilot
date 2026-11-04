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
## How far the timer may be from full for an attack to have started and ended within one tick.
const WHOLE_TICK_TOLERANCE := 0.001
const TRACE_POINTS := 64
const TRACE_STEP := 0.25
## Ticks needed to tell how the infection moves by itself.
const MIN_GROWTH_STEPS := 10
## What the infection must gain beyond its own growth, in points and as a share of itself, to be a shot's doing.
const GAIN_FLOOR := 1.0
const GAIN_NOISE := 0.002

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
		# A target that falls within the tick its attack starts: the tick before was seen idle and the timer
		# has not moved, so nothing of the attack was missed.
		var whole: bool = not _previous.is_empty() and not sample.paused and sample.time >= sample.max_time - WHOLE_TICK_TOLERANCE
		_open_cycle(sample, not whole)
		_cycle.observed_start = whole
	if _is_volley(sample, _dealt(sample) - _cycle.last_progress):
		_note_volley(sample)
	_record_hit(sample)
	_cycle.infection_end = sample.infection_count
	_check_conditions(sample)
	var used: float = sample.max_time - sample.time
	var event := _base_event("success", sample)
	event.time_left = sample.time
	event.used = used
	event.ratio = used / sample.max_time if sample.max_time > 0.0 else 0.0
	event.complete = not _cycle.partial and not _cycle.paused_seen and not _cycle.level_mismatch and not _cycle.damage_changed and not _cycle.speed_changed
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
	if _cycle.speed_changed:
		clues.append("speed_changed")
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
		"first_volley_time": -1.0,
		"last_volley_time": -1.0,
		"start_time": sample.time,
		"infection_rate": sample.infection_rate,
		"vulnerability": sample.vulnerability,
		"infection_offset": 0.0 if sample.infection_count > 0.0 else -1.0,
		"damage_rate": sample.damage_rate,
		"damage_changed": false,
		"tick_speed": sample.tick_speed,
		"speed_changed": false,
		"trace": PackedStringArray(),
		"trace_next_time": sample.time,
		"min_hit": -1.0,
		"max_hit": -1.0,
		"low_hit": -1.0,
		"hits": PackedFloat32Array(),
		"last_breached": sample.breached,
		"breach_variation": sample.breach_variation,
		"infection_variation": sample.infection_variation,
		"infection_start": sample.infection_count,
		"infection_end": sample.infection_count,
		"infection_integral": 0.0,
		"infection_counts": PackedFloat64Array([sample.infection_count]),
		"infection_steps": PackedFloat64Array([0.0]),
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
			_note_volley(sample)
	_next_cycle_id += 1


func _update_cycle(sample: Dictionary) -> void:
	var step: float = _previous.time - sample.time
	if step > 0.0:
		_cycle.max_step = maxf(_cycle.max_step, step)
		_cycle.step_sum += step
		_cycle.steps += 1
		_cycle.infection_integral += sample.infection_count * step
		_cycle.infection_counts.append(sample.infection_count)
		_cycle.infection_steps.append(step)
	_cycle.breach_variation |= sample.breach_variation
	_cycle.infection_variation |= sample.infection_variation
	_cycle.infection_end = sample.infection_count
	if sample.paused:
		_cycle.paused_seen = true
	if sample.level != _cycle.level:
		_cycle.level_mismatch = true
	_check_conditions(sample)
	if _cycle.infection_offset < 0.0 and sample.infection_count > 0.0:
		_cycle.infection_offset = _cycle.start_time - sample.time
	_record_trace(sample)
	_record_hit(sample)
	var dealt := _dealt(sample)
	if dealt > _cycle.last_progress:
		_cycle.progressed = true
		if _is_volley(sample, dealt - _cycle.last_progress):
			_note_volley(sample)
		_cycle.last_progress = dealt
		_cycle.last_progress_time = sample.time


func _dealt(sample: Dictionary) -> float:
	return sample.max_firewall - sample.firewall + sample.breached


## Power, damage or speed moving during an attack make it useless as a measure.
func _check_conditions(sample: Dictionary) -> void:
	if sample.damage_rate != _cycle.damage_rate or sample.infection_rate != _cycle.infection_rate or sample.vulnerability != _cycle.vulnerability:
		_cycle.damage_changed = true
	if sample.tick_speed != _cycle.tick_speed:
		_cycle.speed_changed = true


func _note_volley(sample: Dictionary) -> void:
	_cycle.volleys += 1
	if _cycle.first_volley_time < 0.0:
		_cycle.first_volley_time = sample.time
	_cycle.last_volley_time = sample.time


## What the infection really does, whatever the node behind it: how fast it moves by itself, and what shots add.
## Most ticks see no shot, so the low quarter of the changes is the infection left to itself.
func _set_infection_measure(event: Dictionary) -> void:
	var counts: PackedFloat64Array = _cycle.infection_counts
	var steps: PackedFloat64Array = _cycle.infection_steps
	var rates := PackedFloat64Array()
	for index: int in range(1, counts.size()):
		if counts[index - 1] > 0.0 and counts[index] > 0.0:
			rates.append(log(counts[index] / counts[index - 1]) / steps[index])
	if rates.size() < MIN_GROWTH_STEPS:
		return
	rates.sort()
	var growth: float = rates[rates.size() / 4]
	var gains := PackedFloat32Array()
	if counts[0] > 0.0 and not _cycle.partial:
		gains.append(counts[0])
	var total: float = counts[0] if counts[0] > 0.0 and not _cycle.partial else 0.0
	for index: int in range(1, counts.size()):
		var kept: float = counts[index - 1] * exp(growth * steps[index])
		if counts[index] - kept > GAIN_FLOOR + GAIN_NOISE * kept:
			gains.append(counts[index] - kept)
			total += counts[index] - kept
	event.infection_growth = growth
	event.infection_gains = gains
	event.infection_pulses = gains.size()
	if not gains.is_empty():
		event.infection_gain = total / gains.size()


## Keeps time:infection:firewall:breached points, to compare infection with a model afterwards.
func _record_trace(sample: Dictionary) -> void:
	if sample.infection_count <= 0.0 or sample.time > _cycle.trace_next_time or _cycle.trace.size() >= TRACE_POINTS:
		return
	_cycle.trace.append("%.2f:%.2f:%.2f:%.2f" % [sample.time, sample.infection_count, sample.firewall, sample.breached])
	_cycle.trace_next_time = sample.time - TRACE_STEP


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
	# Infection still eating the firewall is not on the breach bar: the whole rise is the hit.
	var on_firewall: bool = sample.firewall > 0.0 and not _previous.is_empty() and sample.firewall < _previous.firewall
	var hit: float = delta if on_firewall else delta - _continuous_damage(sample)
	_cycle.min_hit = hit if _cycle.min_hit < 0.0 else minf(_cycle.min_hit, hit)
	_cycle.max_hit = maxf(_cycle.max_hit, hit)
	# A hit that empties the bar is cut to what was left: it says nothing about the hit's real size.
	if sample.breached < sample.max_breach - EPSILON_DAMAGE:
		_cycle.low_hit = hit if _cycle.low_hit < 0.0 else minf(_cycle.low_hit, hit)
		_cycle.hits.append(hit)


func _set_hits(event: Dictionary) -> void:
	if _cycle.max_hit >= 0.0:
		event.min_hit = _cycle.min_hit
		event.max_hit = _cycle.max_hit
	if _cycle.low_hit >= 0.0:
		event.low_hit = _cycle.low_hit
		event.hits = _cycle.hits


func _base_event(event_name: String, sample: Dictionary) -> Dictionary:
	var event := _core_event(event_name, sample)
	event.infection_rate = sample.infection_rate
	event.tick_speed = sample.tick_speed
	if _cycle.volleys >= 2:
		event.interval = (_cycle.first_volley_time - _cycle.last_volley_time) / (_cycle.volleys - 1)
	if _cycle.infection_offset >= 0.0:
		event.infection_offset = _cycle.infection_offset
	if _cycle.breach_variation != 0:
		event.breach_variation = _cycle.breach_variation
	if _cycle.infection_variation != 0:
		event.infection_variation = _cycle.infection_variation
	if _cycle.infection_integral > 0.0 or _cycle.infection_start > 0.0 or _cycle.infection_end > 0.0:
		event.infection_start = _cycle.infection_start
		event.infection_end = _cycle.infection_end
		event.infection_integral = _cycle.infection_integral
		event.dealt_total = _dealt(sample)
		_set_infection_measure(event)
	if not _cycle.trace.is_empty():
		event.trace = ";".join(_cycle.trace)
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
