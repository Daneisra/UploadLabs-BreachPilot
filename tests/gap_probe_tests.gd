extends RefCounted
## Gap measures, tested without the game. The scenarios are built from what the logs showed: the
## orders tested here are possibilities, and only the in-game measure tells which ones really happen.

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/features/threat_manager/"
const GapProbe := preload(MOD + "gap_probe.gd")
const GapStats := preload(MOD + "gap_stats.gd")

const FRAME_USEC := 16000

var _check_call: Callable
var _frame := 100
var _tick := 10


func run(check: Callable) -> void:
	_check_call = check
	_test_success_gap()
	_test_result_before_reset()
	_test_failure_known_late()
	_test_no_window()
	_test_not_rearmed_and_paused()
	_test_level_changes()
	_test_finish()
	_test_stats()
	_test_common_windows()
	_test_cost()


func _check(condition: bool, label: String) -> void:
	_check_call.call(condition, label)


func _sample(overrides: Dictionary = {}) -> Dictionary:
	var sample := {
		"hook": "F", "usec": _frame * FRAME_USEC, "frame": _frame, "tick": _tick, "detected": false, "paused": false,
		"time": 6.0, "max_time": 6.0, "firewall": 68.0, "max_firewall": 68.0, "breached": 0.0, "infection_count": 0.0,
		"level": 3, "tick_speed": 0.05, "damage_rate": 35.0, "infection_rate": 0.0, "offscreen": false, "native": false,
	}
	sample.merge(overrides, true)
	return sample


func _attacking(overrides: Dictionary = {}) -> Dictionary:
	var values := {"detected": true, "time": 3.0, "firewall": 0.0, "breached": 40.0}
	values.merge(overrides, true)
	return _sample(values)


func _next_frame(ticks: int = 0) -> void:
	_frame += 1
	_tick += ticks


func _stamp(hook: String = "T") -> Dictionary:
	return {"hook": hook, "usec": _frame * FRAME_USEC, "frame": _frame, "tick": _tick}


## Attack, then a free window for the given frames, then the next attack with both signs at once.
func _run_gap(probe: GapProbe, idle_frames: int, result: String = "success") -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	probe.feed(_attacking())
	_next_frame(1)
	probe.feed(_attacking({"time": 2.95}))
	if result == "success":
		probe.note_result(result, _stamp("B"))
	_next_frame()
	records.append_array(probe.feed(_sample()))
	for i: int in idle_frames:
		_next_frame(1 if i % 3 == 0 else 0)
		records.append_array(probe.feed(_sample()))
	_next_frame(1)
	records.append_array(probe.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0})))
	return records


func _test_success_gap() -> void:
	var probe := GapProbe.new()
	var records := _run_gap(probe, 10)
	_check(records.size() == 1 and records[0].kind == "gap", "one gap record per attack end")
	var gap := records[0]
	_check(gap.case_result == "success", "the gap keeps the result of the attack before it")
	_check(not gap.no_window and gap.raw_frames == 11, "the window lasts from the first free sample to the next attack")
	_check(gap.raw_us == 11 * FRAME_USEC, "the window is timed in microseconds")
	_check(gap.raw_ticks == 5, "the window is counted in ticks")
	_check(gap.uncertainty_us == 2 * FRAME_USEC, "the error on both edges is reported")
	_check(gap.start_sign == "same", "signs seen together are not ordered")


## The signal comes before the reset: knowing the result must not open the window.
func _test_result_before_reset() -> void:
	var probe := GapProbe.new()
	probe.feed(_attacking())
	_next_frame(1)
	probe.feed(_attacking({"time": 2.95}))
	probe.note_result("success", _stamp("B"))
	_check(not probe.is_available(), "a known result does not make the window available")
	probe.feed(_attacking({"hook": "D", "time": 2.95}))
	_check(not probe.is_available(), "a deferred call before the reset does not either")
	_next_frame(3)
	probe.feed(_sample())
	_check(probe.is_available(), "the reset makes it available")
	_next_frame(1)
	var records := probe.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0}))
	_check(records[0].known_to_available_frames == 1, "the delay between the result and the reset is measured")
	_check(records[0].usable_frames == 1, "the usable window starts once the window is free")


## A failure is only deduced after the reset, so part of the window is already gone.
func _test_failure_known_late() -> void:
	var probe := GapProbe.new()
	probe.feed(_attacking({"time": 0.05}))
	_next_frame(1)
	probe.feed(_sample())
	for i: int in 3:
		_next_frame()
		probe.feed(_sample())
	probe.note_result("failure_power", _stamp())
	for i: int in 2:
		_next_frame()
		probe.feed(_sample())
	_next_frame(1)
	var gap := probe.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0}))[0]
	_check(gap.case_result == "failure_power", "the failure labels its gap")
	_check(gap.raw_frames == 6 and gap.usable_frames == 3, "only what is left after the deduction is usable")

	var late := GapProbe.new()
	late.feed(_attacking({"time": 0.05}))
	_next_frame(1)
	late.feed(_sample())
	_next_frame(1)
	var signs_only := late.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0}))
	_check(signs_only.is_empty(), "the gap waits for its result")
	_next_frame()
	var labeled := late.note_result("failure_power", _stamp())
	_check(labeled.size() == 1 and labeled[0].known_after_start and labeled[0].usable_frames == 0, "a result known after the next start leaves no usable window")


func _test_no_window() -> void:
	var probe := GapProbe.new()
	probe.feed(_attacking({"time": 0.05}))
	_next_frame(1)
	probe.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0}))
	_next_frame(1)
	var records := probe.note_result("failure_power", _stamp())
	_check(records.size() == 1 and records[0].no_window, "a restart without a free state is a missing window")
	_check(records[0].raw_us == 0 and records[0].usable_us == 0, "a missing window measures zero")


func _test_not_rearmed_and_paused() -> void:
	var probe := GapProbe.new()
	probe.feed(_attacking())
	_next_frame(1)
	probe.feed(_sample({"time": 2.0}))
	_check(not probe.is_available(), "an unarmed timer is not available")
	_next_frame()
	probe.feed(_sample({"paused": true}))
	_check(not probe.is_available(), "a paused window is not available")
	_next_frame()
	probe.feed(_sample())
	_check(probe.is_available(), "it becomes available once armed and running")
	_next_frame(1)
	probe.note_result("success", _stamp())
	var gap := probe.feed(_attacking({"time": 6.0, "firewall": 33.0, "breached": 0.0}))[0]
	_check(not gap.armed_at_idle and gap.raw_frames == 1, "the window only counts from the available state")


func _test_level_changes() -> void:
	var probe := GapProbe.new()
	_run_gap(probe, 2)
	_next_frame(1)
	probe.feed(_attacking({"time": 4.0}))
	_next_frame(1)
	probe.feed(_attacking({"time": 3.95, "level": 4}))
	_next_frame()
	probe.feed(_sample({"level": 4, "max_time": 6.0}))
	_check(probe.note_result("level_changed_reset", _stamp(), {}).is_empty(), "the interrupted attack does not close the change")
	_next_frame(1)
	probe.feed(_attacking({"level": 4, "time": 6.0, "firewall": 33.0, "breached": 0.0}))
	_next_frame()
	var mid := probe.note_result("success", _stamp("B"), {"used": 5.0, "complete": true, "level": 4})
	_check(mid.size() == 1 and mid[0].kind == "level_change", "a level change is reported with what followed")
	_check(mid[0].state == "attack" and mid[0].from == 3 and mid[0].to == 4, "a change during an attack is told apart")
	_check(mid[0].reset_frames == 1 and mid[0].reset_event == "level_changed_reset", "its reset is timed")
	_check(mid[0].next_event == "success" and mid[0].next_complete and is_equal_approx(mid[0].next_used, 5.0), "the attack after it is reported")

	var calm := GapProbe.new()
	calm.feed(_attacking())
	_next_frame(1)
	calm.note_result("success", _stamp("B"))
	calm.feed(_sample())
	_next_frame()
	calm.feed(_sample({"level": 4, "max_time": 12.0, "time": 12.0, "native": true}))
	_next_frame(1)
	calm.feed(_attacking({"level": 4, "max_time": 12.0, "time": 12.0, "firewall": 33.0, "breached": 0.0}))
	_next_frame()
	var quiet := calm.note_result("failure_power", _stamp())
	var change_seen := false
	for record: Dictionary in quiet:
		if record.kind == "level_change":
			change_seen = record.state == "available" and record.native and record.reset_frames == -1 and record.max_time_frames == 0
	_check(change_seen, "a change while available shows no reset, and its max time moves at once")

	var ending := GapProbe.new()
	ending.feed(_attacking())
	_next_frame(1)
	ending.note_result("success", _stamp("B"))
	_next_frame()
	ending.feed(_attacking({"level": 4}))
	_next_frame()
	var records := ending.finish()
	_check(records.size() == 1 and records[0].state == "ending" and records[0].next_event == "none", "a change between the result and the reset is told apart")


func _test_finish() -> void:
	var probe := GapProbe.new()
	probe.feed(_attacking())
	_next_frame(1)
	probe.feed(_sample())
	_check(probe.finish().is_empty() and probe.gaps_interrupted == 1, "an unfinished gap is counted, not measured")
	_check(not probe.is_available(), "nothing is available after finish")
	probe.note_result("success", _stamp())
	probe.note_result("success", _stamp())
	_check(probe.results_unmatched == 1, "results without a gap are counted")

	var changes := GapProbe.new()
	changes.feed(_attacking())
	_next_frame(1)
	changes.feed(_attacking({"hook": "T", "time": 2.95}))
	changes.feed(_sample({"hook": "L"}))
	var counted := changes.take_changes()
	_check(counted.get("time@T") == 1 and counted.get("detected@L") == 1, "the hook that first saw each change is counted")
	_check(changes.take_changes().is_empty(), "changes are handed over once")


func _test_stats() -> void:
	var stats := GapStats.new()
	var probe := GapProbe.new()
	var outcome := {}
	var sequences := 0
	for i: int in 100:
		for record: Dictionary in _run_gap(probe, i % 5 + 2):
			outcome = stats.add("breach_corps", record)
			sequences += 1 if outcome.sequence else 0
	_check(sequences == GapStats.SEQUENCES_PER_CASE, "only the first attacks of a case keep their sequence")
	_check(outcome.report != "", "a case is reported every %d attacks" % GapStats.REPORT_EVERY)
	var line := stats.case_line(outcome.report)
	_check(line.contains("n=100") and line.contains("no_window=0"), "the totals are counted")
	_check(line.contains("raw_ms=") and line.contains("\"3\":20"), "the distribution is kept, not only the mean")
	_check(line.contains("usable_frames_min=3"), "the minimum is kept")

	var bounded := GapStats.new()
	var record: Dictionary = _run_gap(GapProbe.new(), 2)[0]
	for i: int in GapStats.MAX_CASES + 10:
		record.level = i
		bounded.add("breach_corps", record)
	_check(bounded._cases.size() == GapStats.MAX_CASES and bounded.cases_dropped == 10, "the number of cases is bounded")
	_check(bounded.summary_lines().size() == GapStats.MAX_CASES + 1, "dropped cases are reported")
	record.level = 3
	record.raw_frames = 100000
	bounded = GapStats.new()
	bounded.add("breach_corps", record)
	_check(bounded.case_line(bounded._cases.keys()[0]).contains("over"), "very long windows share one bucket")

	var capped := GapStats.new()
	var logged := 0
	for i: int in GapStats.MAX_CASES:
		record.level = i
		for j: int in GapStats.SEQUENCES_PER_CASE:
			logged += 1 if capped.add("breach_corps", record).sequence else 0
	_check(logged == GapStats.MAX_SEQUENCES, "the number of logged sequences is bounded")


func _test_common_windows() -> void:
	var stats := GapStats.new()
	for free: bool in [true, true, false, true, false, false, true]:
		stats.note_common("breach_corps", 2, free)
	var line: String = stats.summary_lines()[0]
	_check(line.contains("nodes=2 frames=7 available=4 runs=2 shortest=1 longest=2"), "windows free at the same time are measured")


func _test_cost() -> void:
	var probe := GapProbe.new()
	var samples: Array[Dictionary] = []
	for i: int in 1000:
		_next_frame(1 if i % 3 == 0 else 0)
		samples.append(_attacking({"time": 6.0 - i * 0.001}))
	var started := Time.get_ticks_usec()
	for sample: Dictionary in samples:
		probe.feed(sample)
	var cost := (Time.get_ticks_usec() - started) / 1000.0
	print("gap probe: %.1f us per sample" % cost)
	_check(cost < 100.0, "a sample costs well under one percent of a frame")
