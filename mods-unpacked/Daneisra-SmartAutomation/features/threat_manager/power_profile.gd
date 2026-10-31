extends RefCounted
## What an attack brings to bear. Two attacks are only comparable when their signatures match.
## The game speed is left out: it changes how fast the timer runs, not what fits inside it.


static func from_event(event: Dictionary, last_interval: float = 0.0) -> Dictionary:
	var interval: float = snappedf(event.get("interval", 0.0), 0.05)
	if interval <= 0.0:
		interval = last_interval
	var profile := {
		"damage_rate": event.get("damage_rate", 0.0),
		"infection_rate": event.get("infection_rate", 0.0),
		"vulnerability": event.get("vulnerability", 0.0),
		"breach_variation": event.get("breach_variation", 0),
		"infection_variation": event.get("infection_variation", 0),
		"interval": interval,
		"tick_speed": event.get("tick_speed", 0.05),
		"infection_offset": event.get("infection_offset", -1.0),
	}
	profile.signature = signature(profile)
	return profile


static func signature(profile: Dictionary) -> String:
	return "%.3f|%.3f|%.3f|%d|%d" % [profile.damage_rate, profile.infection_rate, profile.vulnerability, profile.breach_variation, profile.infection_variation]


static func has_infection(profile: Dictionary) -> bool:
	return profile.infection_rate > 0.0
