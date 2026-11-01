extends SceneTree
## Checks a trial archive itself, unpacked in a throwaway copy of the project. Nothing here opens a lock:
## these are the archive's own scripts. Run with:
## Godot_console.exe --headless --path <copy> --script res://tests/trial_archive_check.gd

const MOD := "res://mods-unpacked/Daneisra-SmartAutomation/"
const Actuator := preload(MOD + "features/threat_manager/threat_actuator.gd")
const Observer := preload(MOD + "features/threat_manager/threat_observer.gd")
const SaLog := preload(MOD + "core/sa_log.gd")
const MARKER := "user://smart_automation_archive_check/trial_used.json"

var _failures := 0
var _checks := 0


class FakeResource:
	var production := 30.0
	var count := 0.0


class FakeWindow extends Node:
	var data := {"level": 2.0, "max_level": 7.0}
	var detected := false
	var paused := false
	var time := 6.0
	var max_time := 6.0
	var firewall := 50.0
	var max_firewall := 50.0
	var breached := 0.0
	var breach_damage := FakeResource.new()
	var infection_damage := FakeResource.new()
	var vulnerability := FakeResource.new()
	var calls: Array[String] = []

	func level_up(steps: int) -> void:
		calls.append("up:%d" % steps)
		data.level += steps

	func level_down(steps: int) -> void:
		calls.append("down:%d" % steps)
		data.level -= steps


class FakeSettings extends Node:
	var auto_level_breach := false
	var tick_speed := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAILED: %s" % label)


func _attempt(window: FakeWindow, settings: FakeSettings, type: String, direction: String, level: int) -> Dictionary:
	var actuator := Actuator.new(true, {"attributes": settings, "data": settings}, {"action_limit": 12, "action_types": Actuator.Policy.TRIAL_TYPES + ["breach_bank"], "marker_path": MARKER})
	actuator.request(type, direction, level, {"damage_rate": 30.0, "infection_rate": 30.0, "vulnerability": 0.0}, {"status": "reliable", "p_success": 1.0}, {})
	return actuator.attempt(type, window, "1|1", 1, true, true, false)


func _run() -> void:
	DirAccess.remove_absolute(MARKER)
	_check(Actuator.Policy.ACTIONS_ENABLED, "this archive opens the lock")
	for old: Dictionary in [{}, {"mode": "active"}, {"mode": "dry_run"}, {"active_trial": "true"}, {"active_trial": false}]:
		var observer := Observer.new()
		observer.configure(SaLog.new("warning"), 0.25, false, old)
		_check(observer.regulation_mode() != "active", "no active mode from %s" % str(old))
		observer.free()
	var trial := Observer.new()
	trial.configure(SaLog.new("warning"), 0.25, false, {"active_trial": true, "profile": "aggressive", "action_limit": 9})
	_check(trial.regulation_mode() == "active", "the explicit option arms the trial")
	_check(trial._regulation.profile == "balanced" and trial._regulation.action_limit == 12 and trial._regulation.action_types == Actuator.Policy.TRIAL_TYPES, "and the trial sets its own limits")
	trial.free()

	var settings := FakeSettings.new()
	var window := FakeWindow.new()
	for entry: Array in [["breach_bank", "raise", 2]]:
		_check(_attempt(window, settings, entry[0], entry[1], entry[2]).reason == "outside_trial", "refused: %s" % str(entry))
	_check(window.calls.is_empty(), "nothing outside the trial is called")
	var done := _attempt(window, settings, "breach_government", "raise", 2)
	_check(done.outcome == "acted" and window.calls == ["up:1"] and window.data.level == 3.0, "the one change is made")
	window.data.level = 2.0
	_check(_attempt(window, settings, "breach_government", "raise", 2).reason == "trial_already_used", "a restart ends the trial")
	_check(window.calls.size() == 1, "one call in all")
	window.free()
	settings.free()
	DirAccess.remove_absolute(MARKER)
	print("archive check: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
