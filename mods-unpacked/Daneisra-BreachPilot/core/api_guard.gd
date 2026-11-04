extends RefCounted

const SIGNALS := ["tick", "breached", "window_created", "window_initialized", "window_deleted", "desktop_ready", "setting_set"]
const BREACH_PROPERTIES := [
	"window", "data", "time", "max_time", "detected", "firewall", "max_firewall",
	"breached", "max_breach", "paused", "breach_damage", "infection_damage", "vulnerability",
]
## The slots a target reads, and what the observer reads in each.
const SLOT_FIELDS := {
	"breach_damage": ["production", "variation"],
	"infection_damage": ["count", "production", "variation"],
	"vulnerability": ["count"],
}


## The mod's former identifier: both copies at once would regulate the same nodes twice.
const FORMER_IDS := ["Daneisra-SmartAutomation"]


## The former copy of this mod still loaded, or "". The Mod Loader names each mod's main node after its id.
static func former_install(root: Node) -> String:
	var loader := root.get_node_or_null("ModLoader")
	if loader == null:
		return ""
	for id: String in FORMER_IDS:
		if loader.get_node_or_null(NodePath(id)) != null:
			return id
	return ""


static func missing_autoload_api(root: Node) -> PackedStringArray:
	var missing := PackedStringArray()
	var signals := root.get_node_or_null("Signals")
	if signals == null:
		missing.append("Signals")
	else:
		for signal_name: String in SIGNALS:
			if not signals.has_signal(signal_name):
				missing.append("Signals.%s" % signal_name)
	_require_property(root, "Globals", "desktop", missing)
	_require_property(root, "Attributes", "tick_speed", missing)
	_require_property(root, "Data", "auto_level_breach", missing)
	return missing


## The attack nodes of the game, and any other with the same slots.
static func is_breach_like(window: Node) -> bool:
	return "breach_damage" in window and "infection_damage" in window and "max_firewall" in window


static func missing_breach_api(window: Node) -> PackedStringArray:
	var missing := PackedStringArray()
	for property: String in BREACH_PROPERTIES:
		if not property in window:
			missing.append(property)
	if not missing.is_empty():
		return missing
	# A node of another mod may look alike but hold nothing behind these names: it is left alone.
	var data: Variant = window.get("data")
	for key: String in ["level", "max_level"]:
		if not (data is Dictionary or data is Object) or not key in data:
			missing.append("data.%s" % key)
	for slot_name: String in SLOT_FIELDS:
		var slot: Variant = window.get(slot_name)
		for field: String in SLOT_FIELDS[slot_name]:
			if not is_instance_valid(slot) or not field in slot:
				missing.append("%s.%s" % [slot_name, field])
	return missing


static func _require_property(root: Node, autoload: String, property: String, missing: PackedStringArray) -> void:
	var node := root.get_node_or_null(autoload)
	if node == null:
		missing.append(autoload)
	elif not property in node:
		missing.append("%s.%s" % [autoload, property])
