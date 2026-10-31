extends RefCounted

const LOG_NAME := "Daneisra-SmartAutomation"
const LEVELS := {"debug": 0, "info": 1, "warning": 2}

var _threshold := 1


func _init(level: String = "info") -> void:
	_threshold = LEVELS.get(level, 1)


func debug(message: String) -> void:
	if _threshold <= 0:
		ModLoaderLog.info(message, LOG_NAME)


func info(message: String) -> void:
	if _threshold <= 1:
		ModLoaderLog.info(message, LOG_NAME)


func warning(message: String) -> void:
	ModLoaderLog.warning(message, LOG_NAME)


func error(message: String) -> void:
	ModLoaderLog.error(message, LOG_NAME)
