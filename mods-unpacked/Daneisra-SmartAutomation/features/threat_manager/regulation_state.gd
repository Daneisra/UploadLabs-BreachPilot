extends RefCounted
## Manual pauses, one per Breach type: the level is shared by type, so the pause is too. They last for
## the session, loads included, and nothing is written: only the player's click ends one.

var _paused: Dictionary = {}


func is_paused(type: String) -> bool:
	return _paused.has(type)


func reason(type: String) -> String:
	return _paused.get(type, "")


## Returns whether this is a new pause.
func pause(type: String, why: String) -> bool:
	if _paused.has(type):
		return false
	_paused[type] = why
	return true


## Returns whether a pause was lifted.
func resume(type: String) -> bool:
	return _paused.erase(type)
