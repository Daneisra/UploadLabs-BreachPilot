extends Node

const MOD_ID := "Daneisra-SmartAutomation"
## Full version. The manifest only holds major.minor.patch, the format the mod loader documents.
const BUILD := "0.2.0-beta.1-dev.2"
const ApiGuard := preload("core/api_guard.gd")
const SaLog := preload("core/sa_log.gd")
const ThreatObserver := preload("features/threat_manager/threat_observer.gd")

var _log: SaLog
var _observer: ThreatObserver
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
		# Whatever the file says: the only way to active is the trial option, in a trial archive.
		"mode": "dry_run" if settings.regulation_mode == "dry_run" else "off",
		"active_trial": settings.active_trial,
		"profile": settings.regulation_profile,
		"max_allowed_level": int(settings.max_allowed_level),
		"min_level": int(settings.min_level),
	}, settings.gap_probe)
	add_child(_observer)
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
		"active_trial": false,
	}
	var config: Variant = ModLoaderConfig.get_current_config(MOD_ID)
	if config != null:
		settings.merge(config.data, true)
	return settings
