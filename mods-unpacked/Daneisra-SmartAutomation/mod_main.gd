extends Node

const MOD_ID := "Daneisra-SmartAutomation"
## Full version. The manifest only holds major.minor.patch, the format the mod loader documents.
const BUILD := "0.4.0"
const ApiGuard := preload("core/api_guard.gd")
const SaLog := preload("core/sa_log.gd")
const ThreatObserver := preload("features/threat_manager/threat_observer.gd")
const AdvisorInventory := preload("features/hacking_advisor/advisor_inventory.gd")
const HackingAdvisor := preload("features/hacking_advisor/hacking_advisor.gd")

var _log: SaLog
var _observer: ThreatObserver
var _advisor: HackingAdvisor
var _hotkey_enabled := false


func _init() -> void:
	# The game's autoloads load after the mod loader, so they cannot be used here.
	set_process_input(false)
	ModLoaderLog.info("Loaded build=%s" % BUILD, MOD_ID)


func _ready() -> void:
	await get_tree().process_frame
	var settings := _read_settings()
	_log = SaLog.new(settings.log_level)

	var missing := ApiGuard.missing_autoload_api(get_tree().root)
	if not missing.is_empty():
		_log.error("api_check result=failed missing=%s" % ",".join(missing))
		return
	_log.info("api_check result=ok")

	_observer = ThreatObserver.new()
	_observer.name = "ThreatObserver"
	_observer.configure(_log, settings.starvation_ratio, settings.api_dump, {
		"mode": settings.regulation_mode,
		"profile": settings.regulation_profile,
		"max_allowed_level": int(settings.max_allowed_level),
		"min_level": int(settings.min_level),
	}, settings.gap_probe)
	add_child(_observer)
	_advisor = HackingAdvisor.new()
	_advisor.name = "HackingAdvisor"
	_advisor.configure(_log, _observer)
	add_child(_advisor)
	_observer.set_advice_action(_advisor.toggle)
	if settings.threat_observer_enabled:
		_observer.start()

	_hotkey_enabled = settings.debug_toggle_hotkey
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_observer):
		return
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo or not key.ctrl_pressed or not key.alt_pressed:
		return
	# The emergency stop has no option: it must always work.
	if key.keycode == KEY_F10:
		_observer.emergency_stop()
	elif key.keycode == KEY_F9 and _hotkey_enabled:
		if _observer.is_active():
			_observer.stop()
		else:
			_observer.start()
	elif key.keycode == KEY_F8:
		if key.shift_pressed:
			_log_inventory()
		else:
			_advisor.toggle()


## Read-only, one snapshot per key press: it only serves to learn what the advisor could rely on.
func _log_inventory() -> void:
	var root := get_tree().root
	var lines := AdvisorInventory.new().snapshot(root, root.get_node("Globals").desktop)
	_log.info("advisor_inventory begin lines=%d" % lines.size())
	for line: String in lines:
		_log.info("advisor_inventory %s" % line)
	_log.info("advisor_inventory end")


func _read_settings() -> Dictionary:
	var settings := {
		"threat_observer_enabled": true,
		"log_level": "info",
		"starvation_ratio": 0.25,
		"api_dump": false,
		"debug_toggle_hotkey": false,
		"regulation_mode": "off",
		"regulation_profile": "balanced",
		"max_allowed_level": -1,
		"min_level": 0,
		"gap_probe": false,
	}
	var config: Variant = ModLoaderConfig.get_current_config(MOD_ID)
	if config != null:
		settings.merge(config.data, true)
	return settings
