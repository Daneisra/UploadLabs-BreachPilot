class_name ModLoaderLog
extends RefCounted
## Stands in for the mod loader's logger when the tests run without the game.

static var messages: PackedStringArray = []


static func info(message: String, _mod: String) -> void:
	messages.append(message)


static func warning(message: String, _mod: String) -> void:
	messages.append("WARNING " + message)


static func error(message: String, _mod: String) -> void:
	messages.append("ERROR " + message)
