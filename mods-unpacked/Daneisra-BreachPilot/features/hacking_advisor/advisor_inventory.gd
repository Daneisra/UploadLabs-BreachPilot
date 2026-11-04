extends RefCounted
## One read-only snapshot of what the game exposes, to learn what the advisor could rely on.
## It only reads properties: no game method is called and nothing is written, except to the log.

const MAX_DEPTH := 4
const MAX_ITEMS := 40
const MAX_LINE := 3000
const MAX_LINES := 800

## Never read: anything about the account, the platform or the save files.
const SENSITIVE := "token|account|steam|user|passw|secret|auth|email|cloud|save|slot|files?$"
const RELEVANT := "breach|hack|payload|crit|infect|stealth|ghost|inject|vulnerab|firewall|threat|intrusion|speciali|attack|exploit|virus|upgrade|research|perk"
## Autoloads whose content is left out: only their names are listed.
const SKIPPED_AUTOLOADS := "^(Account|Steam|Mod|_)"
## What a game window inherits from Godot or uses for display says nothing about the hacking chain.
const WINDOW_NOISE := "label|bar$|audio|panel|notifier|texture|rid|grabb|drag|select|closing|init_count|out_of_screen|is_far|help|warn_|has_lod|can_"

var _sensitive := RegEx.create_from_string("(?i)" + SENSITIVE)
var _relevant := RegEx.create_from_string("(?i)" + RELEVANT)
var _skipped := RegEx.create_from_string(SKIPPED_AUTOLOADS)
var _noise := RegEx.create_from_string("(?i)" + WINDOW_NOISE)


func describe(value: Variant, depth: int = 0) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_FLOAT:
			return String.num(value, 4)
		TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I:
			return str(value)
		TYPE_OBJECT:
			return _describe_object(value)
		TYPE_DICTIONARY:
			if depth >= MAX_DEPTH:
				return "{%d}" % value.size()
			var parts := PackedStringArray()
			for key: Variant in value:
				if parts.size() >= MAX_ITEMS:
					parts.append("+%d" % (value.size() - MAX_ITEMS))
					break
				parts.append("%s:%s" % [key, "<masked>" if is_sensitive(str(key)) else describe(value[key], depth + 1)])
			return "{%s}" % ",".join(parts)
	if value is Array or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY):
		if depth >= MAX_DEPTH:
			return "[%d]" % value.size()
		var parts := PackedStringArray()
		for item: Variant in value:
			if parts.size() >= MAX_ITEMS:
				parts.append("+%d" % (value.size() - MAX_ITEMS))
				break
			parts.append(describe(item, depth + 1))
		return "[%s]" % ",".join(parts)
	return "<%s>" % type_string(typeof(value))


func is_sensitive(name: String) -> bool:
	return _sensitive.search(name) != null


func is_relevant(name: String) -> bool:
	return _relevant.search(name) != null


## Every instance of a hacking window is detailed, and only the first one of any other type.
func snapshot(root: Node, desktop: Variant) -> PackedStringArray:
	var lines := PackedStringArray()
	_describe_autoloads(root, lines)
	_describe_hacking_details(root, lines)
	if not is_instance_valid(desktop):
		lines.append("desktop none")
		return _finished(lines)
	lines.append("desktop %s" % _script_properties(desktop, false))
	var seen_types := {}
	var windows: Variant = desktop.get("windows")
	if is_instance_valid(windows):
		for window: Node in windows.get_children():
			var type := str(window.get("window"))
			seen_types[type] = seen_types.get(type, 0) + 1
			if seen_types[type] == 1 or is_relevant(type) or _handles_relevant_resource(window):
				_describe_window(window, type, lines)
	lines.append("window_types %s" % describe(seen_types))
	return _finished(lines)


func _finished(lines: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for line: String in lines:
		if kept.size() >= MAX_LINES:
			kept.append("truncated dropped=%d" % (lines.size() - MAX_LINES))
			break
		kept.append(line.substr(0, MAX_LINE))
	return kept


func _describe_autoloads(root: Node, lines: PackedStringArray) -> void:
	for node: Node in root.get_children():
		if _skipped.search(node.name) != null or node.get_script() == null:
			lines.append("autoload %s skipped" % node.name)
			continue
		var names := PackedStringArray()
		for property: Dictionary in _script_property_list(node):
			names.append(property.name)
		lines.append("autoload %s properties=%s" % [node.name, ",".join(names)])
		for property: Dictionary in _script_property_list(node):
			if is_sensitive(property.name):
				continue
			var value: Variant = node.get(property.name)
			if value is Dictionary and not is_relevant(property.name):
				var kept := {}
				for key: Variant in value:
					if is_relevant(str(key)) and not is_sensitive(str(key)):
						kept[key] = value[key]
				if not kept.is_empty():
					lines.append("autoload %s.%s size=%d relevant=%s" % [node.name, property.name, value.size(), describe(kept)])
			elif is_relevant(property.name):
				lines.append("autoload %s.%s=%s" % [node.name, property.name, describe(value)])


## What the general walk cuts short: the upgrades' costs and effects, and the attributes' current values.
func _describe_hacking_details(root: Node, lines: PackedStringArray) -> void:
	var data: Node = root.get_node_or_null("Data")
	var attributes: Node = root.get_node_or_null("Attributes")
	if is_instance_valid(data):
		for section: String in ["upgrades", "perks"]:
			var entries: Variant = data.get(section)
			if not entries is Dictionary:
				continue
			for name: String in entries:
				if name.begins_with("hack_") or name.begins_with("optimization_breach") or name.begins_with("optimization_critical") or name == "breach_skills":
					lines.append("detail %s.%s=%s" % [section, name, describe(entries[name])])
	if is_instance_valid(attributes) and attributes.get("attributes") is Dictionary:
		for name: String in attributes.attributes:
			var attribute: Variant = attributes.attributes[name]
			if is_relevant(name) and not is_sensitive(name) and attribute is Object:
				lines.append("detail attribute.%s %s" % [name, _script_properties(attribute, false)])


func _describe_window(window: Node, type: String, lines: PackedStringArray) -> void:
	lines.append("window type=%s name=%s %s" % [type, window.name, _script_properties(window, true)])
	var containers: Variant = window.get("containers")
	if containers is Array:
		for container: Variant in containers:
			if is_instance_valid(container):
				lines.append("container of=%s %s %s" % [window.name, _describe_object(container), _script_properties(container, true)])


func _handles_relevant_resource(window: Node) -> bool:
	var containers: Variant = window.get("containers")
	if not containers is Array:
		return false
	for container: Variant in containers:
		if is_instance_valid(container) and (is_relevant(str(container.get("resource"))) or is_relevant(str(container.name))):
			return true
	return false


func _script_properties(object: Object, drop_noise: bool) -> String:
	var parts := PackedStringArray()
	for property: Dictionary in _script_property_list(object):
		var name: String = property.name
		if drop_noise and _noise.search(name) != null:
			continue
		parts.append("%s=%s" % [name, "<masked>" if is_sensitive(name) else describe(object.get(name))])
	return " ".join(parts)


func _script_property_list(object: Object) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for property: Dictionary in object.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			kept.append(property)
	return kept


## An object is only named, never entered: this is what keeps the walk bounded and shows the links.
func _describe_object(object: Object) -> String:
	if not is_instance_valid(object):
		return "<freed>"
	if object is Node:
		var owner_name := ""
		if is_instance_valid(object.get_parent()):
			owner_name = "%s/" % object.get_parent().name
		return "<%s:%s%s>" % [object.get_class(), owner_name, object.name]
	if object is Resource:
		return "<%s:%s>" % [object.get_class(), object.resource_path.get_file()]
	return "<%s>" % object.get_class()
