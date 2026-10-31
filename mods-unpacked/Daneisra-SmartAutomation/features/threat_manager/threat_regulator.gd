extends RefCounted
## Decides what the threat level should be, for one Breach type. Pure: it has no access to the game
## and only returns hypothetical decisions. Time values are seconds of the game's timer.

const PROFILES := {
	"conservative": {"p": 1.0, "margin": 0.20, "raise_after": 5, "raise_delay": 60.0, "block": 600.0},
	"balanced": {"p": 0.99, "margin": 0.10, "raise_after": 3, "raise_delay": 30.0, "block": 300.0},
	"aggressive": {"p": 0.95, "margin": 0.0, "raise_after": 2, "raise_delay": 15.0, "block": 120.0},
}
const WINDOW := 20
const STABILIZE_ATTACKS := 2
const LOWER_DELAY := 10.0
const MAX_BLOCK := 3600.0
const BUDGET := 6
const BUDGET_WINDOW := 600.0
const REVERSALS := 3
const REVERSAL_WINDOW := 900.0
const FREEZE := 1800.0
const UNKNOWN_RISK := 0.05
const SIGNIFICANCE := 0.001
## The test is repeated at every attack, so a known risk needs a few attacks before it can conclude.
const MIN_ATTACKS_WITH_RISK := 10
## A level failing against this expected risk proves the forecast wrong at this power.
const REFUTED_BELOW_RISK := 0.01
const RELIABILITY_WINDOW := 50
const MIN_RELIABILITY_EVENTS := 20
const MAX_UNEXPLAINED := 0.05
const EXPLAINED_CLUES: Array[String] = ["damage_changed", "speed_changed", "partial_cycle"]
const MIN_VERIFIED_CHECKS := 10
const MAX_OUT_OF_RANGE := 0.05

var profile_name: String
var suppressed_repeats := 0

var _profile: Dictionary
var _max_allowed: int
var _min_level: int
var _ceiling := -1
var _native := false
var _timer := 0.0
var _level := -1
var _signature := ""
var _history: Array[bool] = []
var _consecutive := 0
var _stabilizing := 0
var _proposal := ""
var _actions: Array[Array] = []
var _last_raise := -INF
var _last_lower := -INF
var _frozen_until := -INF
var _blocked: Dictionary = {}
var _block_length: Dictionary = {}
var _recent_events: Array[bool] = []
var _refuted := false
var _checks_in := 0
var _checks_out := 0


func _init(profile: String = "balanced", max_allowed: int = -1, min_level: int = 0) -> void:
	profile_name = profile if PROFILES.has(profile) else "balanced"
	_profile = PROFILES[profile_name]
	_max_allowed = max_allowed
	_min_level = min_level


func margin() -> float:
	return _profile.margin


func advance(seconds: float) -> void:
	_timer += seconds


func set_native(active: bool) -> void:
	_native = active


func set_ceiling(level: int) -> void:
	_ceiling = level


## Failures the window must hold before chance stops being a fair explanation.
static func failures_needed(attacks: int, risk: float) -> int:
	if risk <= 0.0:
		return 2
	var tail := 1.0
	var term := pow(1.0 - risk, attacks)
	for k: int in range(0, attacks + 1):
		if k >= 2 and tail < SIGNIFICANCE:
			return k
		tail -= term
		term *= float(attacks - k) / float(k + 1) * risk / (1.0 - risk)
	return attacks + 1


## Every classified event feeds this, comparable or not. Unexplained resets make the classifier unsafe.
func note_event(event_name: String, clues: String = "") -> void:
	var unexplained := false
	if event_name == "reset_unknown":
		unexplained = true
		for clue: String in EXPLAINED_CLUES:
			if clues.contains(clue):
				unexplained = false
	_recent_events.append(unexplained)
	if _recent_events.size() > RELIABILITY_WINDOW:
		_recent_events.pop_front()


func is_unsafe() -> bool:
	if _recent_events.size() < MIN_RELIABILITY_EVENTS:
		return false
	return float(_recent_events.count(true)) / _recent_events.size() > MAX_UNEXPLAINED


func note_forecast_check(in_range: bool) -> void:
	if in_range:
		_checks_in += 1
	else:
		_checks_out += 1


## "verified", "unverified" or "invalid": can the infection model be believed at this power?
func model_trust() -> String:
	var total := _checks_in + _checks_out
	if total > 0 and float(_checks_out) / total > MAX_OUT_OF_RANGE and _checks_out >= 2:
		return "invalid"
	if _checks_in < MIN_VERIFIED_CHECKS:
		return "unverified"
	return "verified"


## The level moved. Only the caller knows why; ceilings are set apart with set_ceiling.
func on_level_changed(level: int) -> void:
	_level = level
	_reset_window()
	_proposal = ""


## attack: event, complete, level, max_level, signature. current and next are forecasts of the
## current and next levels (next computed with margin()). Returns the hypothetical decision.
func on_attack(attack: Dictionary, current: Dictionary, next: Dictionary) -> Dictionary:
	if attack.signature != _signature:
		var first := _signature.is_empty()
		_signature = attack.signature
		_reset_window()
		_stabilizing = STABILIZE_ATTACKS
		_proposal = ""
		_blocked.clear()
		_block_length.clear()
		_checks_in = 0
		_checks_out = 0
		if not first:
			return _decision("hold", "power_changed", attack)
	if attack.level != _level:
		on_level_changed(attack.level)

	var is_failure: bool = attack.event == "failure_power"
	if not attack.complete or not (is_failure or attack.event == "success"):
		return _decision("hold", "not_comparable", attack)
	if _stabilizing > 0:
		_stabilizing -= 1
		return _decision("hold", "stabilizing", attack)

	_history.append(is_failure)
	if _history.size() > WINDOW:
		_history.pop_front()
	_consecutive = 0 if is_failure else _consecutive + 1

	if _native:
		return _decision("hold", "blocked_native", attack)
	if is_unsafe():
		return _decision("hold", "classifier_unsafe", attack)
	if _timer < _frozen_until:
		return _decision("hold", "frozen", attack)
	return _try_lower(attack, current) if is_failure else _try_raise(attack, next)


func _try_lower(attack: Dictionary, current: Dictionary) -> Dictionary:
	var risk := UNKNOWN_RISK
	if current.get("status") == "reliable":
		risk = 1.0 - current.p_success
	var failures := _history.count(true)
	var needed := failures_needed(_history.size(), risk)
	if risk > REFUTED_BELOW_RISK and _history.size() < MIN_ATTACKS_WITH_RISK:
		return _decision("hold", "gathering_attacks", attack, {"failures": failures})
	if failures < needed:
		return _decision("hold", "within_expected_failures", attack, {"failures": failures, "needed": needed, "risk": risk})
	if attack.level <= _min_level:
		return _decision("hold", "at_min_level", attack, {"failures": failures, "needed": needed})
	if _timer - _last_lower < LOWER_DELAY:
		return _decision("hold", "lower_delay", attack)
	_refuted = risk <= REFUTED_BELOW_RISK
	return _act("lower", attack, {"failures": failures, "needed": needed, "risk": risk, "forecast_refuted": _refuted})


func _try_raise(attack: Dictionary, next: Dictionary) -> Dictionary:
	var target: int = attack.level + 1
	if _consecutive < _profile.raise_after:
		return _decision("hold", "gathering_successes", attack, {"successes": _consecutive})
	if target > attack.max_level:
		return _decision("hold", "at_game_maximum", attack)
	if _max_allowed >= 0 and target > _max_allowed:
		return _decision("hold", "at_allowed_maximum", attack)
	if _blocked.get(target, -INF) > _timer:
		return _decision("hold", "level_blocked", attack, {"blocked_for": _blocked[target] - _timer})

	var status: String = next.get("status", "invalid")
	if next.get("infected", false) and status != "invalid" and model_trust() != "verified":
		status = "invalid" if model_trust() == "invalid" else "uncertain"
	if status == "invalid":
		return _decision("hold", "forecast_invalid", attack, {"reasons": ",".join(next.get("reasons", PackedStringArray()))})
	if status == "uncertain":
		return _decision("hold", "forecast_uncertain", attack, {"reasons": ",".join(next.get("reasons", PackedStringArray()))})
	if next.p_success < _profile.p:
		return _decision("hold", "forecast_too_risky", attack, {"p": next.p_success})

	# Respecting the player comes last, so the log still shows what the model would have wanted.
	if _ceiling >= 0 and target > _ceiling:
		return _decision("hold", "at_manual_ceiling", attack, {"ceiling": _ceiling, "p": next.p_success})
	if _timer - _last_raise < _profile.raise_delay:
		return _decision("hold", "raise_delay", attack)
	return _act("raise", attack, {"p": next.p_success, "expected_used": next.used_nominal})


func _act(direction: String, attack: Dictionary, details: Dictionary) -> Dictionary:
	var key := "%s|%d|%s" % [direction, attack.level, _signature]
	if key == _proposal:
		suppressed_repeats += 1
		return _decision("hold", "already_proposed", attack, {"proposed": direction})
	while not _actions.is_empty() and _timer - _actions[0][0] > max(BUDGET_WINDOW, REVERSAL_WINDOW):
		_actions.pop_front()
	var recent := 0
	var reversals := 0
	var previous := ""
	for action: Array in _actions:
		if _timer - action[0] <= BUDGET_WINDOW:
			recent += 1
		if _timer - action[0] <= REVERSAL_WINDOW:
			if not previous.is_empty() and action[1] != previous:
				reversals += 1
			previous = action[1]
	if recent >= BUDGET:
		return _decision("hold", "budget_exhausted", attack)
	if not previous.is_empty() and direction != previous:
		reversals += 1
	if reversals >= REVERSALS:
		_frozen_until = _timer + FREEZE
		return _decision("hold", "frozen_by_reversals", attack, {"reversals": reversals})

	_proposal = key
	_actions.append([_timer, direction])
	if direction == "raise":
		_last_raise = _timer
	else:
		_last_lower = _timer
		_block(attack.level)
	var assumed: int = attack.level + (1 if direction == "raise" else -1)
	var extra := details.duplicate()
	extra.assumed_level = assumed
	return _decision(direction, "conditions_met", attack, extra)


## A refuted level stays blocked until the power changes, which clears every block.
func _block(level: int) -> void:
	if _refuted:
		_blocked[level] = INF
		return
	var length: float = _block_length.get(level, _profile.block / 2.0) * 2.0
	length = minf(length, MAX_BLOCK)
	_block_length[level] = length
	_blocked[level] = _timer + length


func _reset_window() -> void:
	_history.clear()
	_consecutive = 0


func _decision(kind: String, reason: String, attack: Dictionary, details: Dictionary = {}) -> Dictionary:
	var decision := {"decision": kind, "reason": reason, "real_level": attack.level, "profile": profile_name, "hypothetical": true}
	decision.merge(details)
	return decision
