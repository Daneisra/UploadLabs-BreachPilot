extends RefCounted

const SIGNALS := ["tick", "breached", "window_created", "window_initialized", "window_deleted", "desktop_ready", "setting_set"]
const BREACH_PROPERTIES := [
	"window", "data", "time", "max_time", "detected", "firewall", "max_firewall",
	"breached", "max_breach", "paused", "breach_damage", "infection_damage", "vulnerability",
]


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
	return missing


static func _require_property(root: Node, autoload: String, property: String, missing: PackedStringArray) -> void:
	var node := root.get_node_or_null(autoload)
	if node == null:
		missing.append(autoload)
	elif not property in node:
		missing.append("%s.%s" % [autoload, property])
