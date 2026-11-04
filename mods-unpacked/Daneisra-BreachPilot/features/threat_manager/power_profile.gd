extends RefCounted
## What an attack brings to bear. Two attacks are only comparable when their signatures match.
## The game speed is left out: it changes how fast the timer runs, not what fits inside it.

const HIT_TOLERANCE := 0.95


static func from_event(event: Dictionary, last_interval: float = 0.0) -> Dictionary:
	var interval: float = snappedf(event.get("interval", 0.0), 0.05)
	if interval <= 0.0:
		interval = last_interval
	var profile := {
		"damage_rate": event.get("damage_rate", 0.0),
		"announced_rate": event.get("damage_rate", 0.0),
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


## What the game announces can be far from the hits it deals: critical hits raise the announced figure
## while most hits stay low. A forecast must count on the lowest hits really seen. The signature stays.
static func apply_observed_hits(profile: Dictionary, lowest: float, highest: float) -> void:
	var announced: float = profile.damage_rate * profile.interval
	if lowest <= 0.0:
		profile.hits_unseen = true
		return
	if announced <= 0.0:
		return
	if lowest < floorf(announced) * HIT_TOLERANCE:
		profile.damage_rate = lowest / profile.interval
		profile.hit_spread = true
	elif highest > ceilf(announced) / HIT_TOLERANCE:
		profile.hit_spread = true


static func signature(profile: Dictionary) -> String:
	return "%.3f|%.3f|%.3f|%d|%d" % [profile.damage_rate, profile.infection_rate, profile.vulnerability, profile.breach_variation, profile.infection_variation]


static func has_infection(profile: Dictionary) -> bool:
	return profile.infection_rate > 0.0
