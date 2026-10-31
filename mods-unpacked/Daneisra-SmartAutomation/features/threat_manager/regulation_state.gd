extends RefCounted
## Manual ceilings, one per Breach type. A manual change sets the ceiling to the new level, up or
## down; only an explicit action removes it.
##
## Ceilings belong to one save slot. Without a reliable slot identifier they stay in memory for the
## current game only, and nothing is written: a global ceiling could affect another save.

var _path: String
var _slot := ""
var _ceilings: Dictionary = {}
var _stored: Dictionary = {}


func _init(path: String = "") -> void:
	_path = path
	if not _path.is_empty() and FileAccess.file_exists(_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if parsed is Dictionary:
			_stored = parsed


func is_persistent() -> bool:
	return not _slot.is_empty() and not _path.is_empty()


## Called when a game is loaded. An empty identifier means the slot is unknown.
func set_slot(slot: String) -> void:
	_slot = slot
	_ceilings = {}
	if is_persistent():
		var saved: Variant = _stored.get("slots", {}).get(slot, {})
		if saved is Dictionary:
			_ceilings = saved.duplicate()


func ceiling(type: String) -> int:
	return int(_ceilings.get(type, -1))


func apply_manual(type: String, level: int) -> void:
	_ceilings[type] = level
	_save()


func clear_all() -> void:
	_ceilings = {}
	_save()


## The settings hold a number: changing it is the explicit action that removes the ceilings.
func apply_clear_token(token: int) -> bool:
	if not is_persistent():
		return false
	var slot_data: Dictionary = _stored.get("tokens", {})
	var seen: int = int(slot_data.get(_slot, 0))
	if token == seen:
		return false
	slot_data[_slot] = token
	_stored["tokens"] = slot_data
	clear_all()
	return true


func _save() -> void:
	if not is_persistent():
		return
	var slots: Dictionary = _stored.get("slots", {})
	slots[_slot] = _ceilings.duplicate()
	_stored["slots"] = slots
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_stored))
