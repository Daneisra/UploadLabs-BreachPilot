extends RefCounted
## Decides what the threat level should be, for one Breach type. Pure: it has no access to the game
## and only returns hypothetical decisions. Time values are seconds of the game's timer.

const PROFILES := {
	"conservative": {"p": 1.0, "margin": 0.20, "raise_after": 5, "raise_delay": 60.0, "block": 600.0, "probes": false, "retries_unlock": false},
	"balanced": {"p": 0.99, "margin": 0.10, "raise_after": 3, "raise_delay": 30.0, "block": 300.0, "probes": true, "retries_unlock": false},
	"aggressive": {"p": 0.95, "margin": 0.0, "raise_after": 2, "raise_delay": 15.0, "block": 120.0, "probes": true, "retries_unlock": true},
}
const WINDOW := 20
const STABILIZE_ATTACKS := 1
const LOWER_DELAY := 5.0
const MAX_BLOCK := 3600.0
const BUDGET := 6
const BUDGET_WINDOW := 600.0
const REVERSALS := 3
const REVERSAL_WINDOW := 900.0
const FREEZE := 1800.0
const SIGNIFICANCE := 0.001
## The test is repeated at every attack, so a known risk needs a few attacks before it can conclude.
const MIN_ATTACKS_WITH_RISK := 10
## A level failing against this expected risk proves the forecast wrong at this power.
const REFUTED_BELOW_RISK := 0.01
## 1.0 - 0.99 is slightly above 0.01 in floating point, and a sure success can sum to just under 1.
const RISK_EPSILON := 1e-9
## Attacks that verify an action: one when it is certain or a lower, more when it rests on doubts.
const VERIFY_CERTAIN := 1
const FAILURES_IN_ROW_TO_LOWER := 2
## Successes here before trying a level that may work but is not sure.
const PROBE_AFTER := 2
## How much better the chance of winning a level must be before a failed try to open it is made again.
const RETRY_GAIN := 0.10
const VERIFY_CAREFUL := 3
const RELIABILITY_WINDOW := 50
const MIN_RELIABILITY_EVENTS := 20
const MAX_UNEXPLAINED := 0.05
const EXPLAINED_CLUES: Array[String] = ["damage_changed", "speed_changed", "partial_cycle"]
const MIN_VERIFIED_CHECKS := 1
const MAX_OUT_OF_RANGE := 0.05

var profile_name: String
var suppressed_repeats := 0

var _profile: Dictionary
var _max_allowed: int
var _min_level: int
var _paused := false
var _native := false
var _timer := 0.0
var _level := -1
var _signature := ""
var _history: Array[bool] = []
var _consecutive := 0
var _failures_in_row := 0
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
var _undo: Dictionary = {}
var _fast_raises: bool
var _certainty_lost := false
var _raises_suspended := false
var _just_contradicted := false
var _action_busy := false
var _probed_level := -1
## The level a try to open the next one started from: the regulation compares with it to come back.
var _trial_from := -1
## The try to open a level under way: {level, chance}. Once it failed, the level waits in _failed_unlocks,
## level -> chance forecast then, until the chance of winning there is RETRY_GAIN higher.
var _unlock_try := {}
var _failed_unlocks := {}


func _init(profile: String = "balanced", max_allowed: int = -1, min_level: int = 0, fast_raises: bool = true) -> void:
	_fast_raises = fast_raises
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


func set_paused(paused: bool) -> void:
	_paused = paused


## An action is waiting or being verified, on any type: nothing new can be proposed.
func set_action_busy(busy: bool) -> void:
	_action_busy = busy


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


## The level moved. Only the caller knows why; a pause is set apart with set_paused.
func on_level_changed(level: int) -> void:
	_level = level
	_reset_window()
	_proposal = ""
	_undo = {}


## The player gave control back: the level is the new starting point and nothing may happen before
## new observations. Delays, blocks, the budget and refuted forecasts all stay.
func on_resume(level: int) -> void:
	_paused = false
	_level = level
	_reset_window()
	_stabilizing = STABILIZE_ATTACKS
	_proposal = ""
	_undo = {}


## A game was loaded: what was seen before says nothing about this one. Pauses, blocks and the budget stay.
func on_game_loaded() -> void:
	_level = -1
	_unlock_try = {}
	_failed_unlocks.clear()
	_reset_window()
	_stabilizing = STABILIZE_ATTACKS
	_proposal = ""
	_undo = {}


## Attacks seen at another game speed say nothing about the decisions to come.
func on_speed_changed() -> void:
	_reset_window()
	_stabilizing = STABILIZE_ATTACKS
	_proposal = ""
	_undo = {}


## The last proposal was not applied: it must not cost budget, delays or a block. Once the level, the
## power or the speed has moved, there is nothing to restore and the budget simply stays spent.
func cancel_last_action() -> void:
	if _undo.is_empty():
		return
	_actions.pop_back()
	_last_raise = _undo.last_raise
	_last_lower = _undo.last_lower
	_blocked = _undo.blocked
	_block_length = _undo.block_length
	_proposal = ""
	_undo = {}


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
		_undo = {}
		_certainty_lost = false
		_raises_suspended = false
		_checks_in = 0
		_checks_out = 0
		if not first:
			return _decision("hold", "power_changed", attack)
	if attack.level != _level:
		on_level_changed(attack.level)
	_note_unlock_try(attack)

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
	_failures_in_row = _failures_in_row + 1 if is_failure else 0

	if _paused:
		return _decision("hold", "manual_pause", attack)
	if _native:
		return _decision("hold", "blocked_native", attack)
	if is_unsafe():
		return _decision("hold", "classifier_unsafe", attack)
	if _timer < _frozen_until:
		return _decision("hold", "frozen", attack)
	if not is_failure:
		if attack.has("profitable_level"):
			return _try_profitable(attack)
		return _try_raise(attack, next)
	var decision := _try_lower(attack, current)
	if _just_contradicted:
		_just_contradicted = false
		decision.forecast_contradicted = true
	return decision


func _try_lower(attack: Dictionary, current: Dictionary) -> Dictionary:
	var failures := _history.count(true)
	var known: bool = current.get("status") == "reliable"
	var true_risk: float = 1.0 - current.p_success if known else 1.0
	# One failure against a sure forecast stops the raises. It takes more than that to lower.
	if known and true_risk <= REFUTED_BELOW_RISK + RISK_EPSILON and not _raises_suspended:
		_raises_suspended = true
		_certainty_lost = true
		_just_contradicted = true
	# Failing twice in a row is enough, unless the forecast knows this level to fail now and then, within
	# what the profile accepts: chance may then explain it, and the count over the window decides.
	var accepted_chance: bool = known and true_risk > RISK_EPSILON and true_risk <= 1.0 - _profile.p + RISK_EPSILON
	# Failure expected and no success seen at this level: the attack only confirms the forecast.
	var confirmed: bool = known and current.p_success <= RISK_EPSILON and _history.count(false) == 0
	var repeated: bool = (_failures_in_row >= FAILURES_IN_ROW_TO_LOWER or confirmed) and not accepted_chance
	# Chance only excuses the risk the profile accepts: a level expected to fail is not "normal".
	var risk := minf(true_risk, 1.0 - _profile.p)
	var needed := failures_needed(_history.size(), risk)
	if not repeated:
		if not known:
			return _decision("hold", "forecast_not_reliable", attack, {"failures": failures, "status": current.get("status", "none")})
		if risk > REFUTED_BELOW_RISK + RISK_EPSILON and _history.size() < MIN_ATTACKS_WITH_RISK:
			return _decision("hold", "gathering_attacks", attack, {"failures": failures})
		if failures < needed:
			return _decision("hold", "within_expected_failures", attack, {"failures": failures, "needed": needed, "risk": risk})
	if attack.level <= _min_level:
		return _decision("hold", "at_min_level", attack, {"failures": failures, "needed": needed})
	if _timer - _last_lower < LOWER_DELAY:
		return _decision("hold", "lower_delay", attack)
	_refuted = known and true_risk <= REFUTED_BELOW_RISK + RISK_EPSILON
	return _act("lower", attack, {"failures": failures, "failures_in_row": _failures_in_row, "needed": needed, "risk": risk, "true_risk": true_risk, "forecast_status": current.get("status", "none"), "forecast_refuted": _refuted, "verify_attacks": VERIFY_CERTAIN, "target": maxi(attack.get("target_down", attack.level - 1), _min_level)})


## A raise the forecast is sure of needs no waiting: one success here, and it goes up. The profile's
## delays are for doubts. A refuted forecast brings them back until the power changes.
func _is_certain(next: Dictionary) -> bool:
	if not _fast_raises or _certainty_lost or next.get("status") != "reliable" or next.get("p_success", -1.0) < 1.0 - RISK_EPSILON:
		return false
	return not next.get("infected", false) or model_trust() == "verified"


## Whether a raise could go to this level. For the search of the best one.
func can_reach(level: int) -> bool:
	return (_max_allowed < 0 or level <= _max_allowed) and _blocked.get(level, -INF) <= _timer


func required_success() -> float:
	return _profile.p


## The level the regulation stands for: the one it left to open the next level while it is up there.
func home_level(level: int) -> int:
	return _trial_from if level == _probed_level and _trial_from >= 0 else level


## Whether the profile lets a level that may fail be tried.
func allows_trials() -> bool:
	return _fast_raises and _profile.probes


## attack can name best_level and best_forecast: the highest level known to work, to go straight to it.
func _try_raise(attack: Dictionary, next: Dictionary) -> Dictionary:
	var target: int = attack.level + 1
	if attack.has("best_forecast") and _is_certain(attack.best_forecast):
		target = attack.best_level
		next = attack.best_forecast
	if _raises_suspended:
		if _consecutive < WINDOW:
			return _decision("hold", "raises_suspended", attack)
		_raises_suspended = false
	var certain := _is_certain(next)
	# Being at the maximum is worth a try: if the level fails, it goes back down and waits before trying again.
	var probing: bool = not certain and _fast_raises and _profile.probes and attack.get("probe_possible", false)
	if _consecutive < (1 if certain else (PROBE_AFTER if probing else _profile.raise_after)):
		return _decision("hold", "gathering_successes", attack, {"successes": _consecutive})
	if target > attack.max_level:
		return _decision("hold", "at_game_maximum", attack)
	if _max_allowed >= 0 and target > _max_allowed:
		return _decision("hold", "at_allowed_maximum", attack)
	if _blocked.get(target, -INF) > _timer:
		return _decision("hold", "level_blocked", attack, {"blocked_for": _blocked[target] - _timer})
	if probing:
		_probed_level = target
		_trial_from = -1
		return _act("raise", attack, {"certain": false, "probe": true, "verify_attacks": VERIFY_CERTAIN, "target": target})

	var status: String = next.get("status", "invalid")
	if next.get("infected", false) and status != "invalid" and model_trust() != "verified":
		status = "invalid" if model_trust() == "invalid" else "uncertain"
	if status == "invalid":
		return _decision("hold", "forecast_invalid", attack, {"reasons": ",".join(next.get("reasons", PackedStringArray()))})
	if status == "uncertain":
		return _decision("hold", "forecast_uncertain", attack, {"reasons": ",".join(next.get("reasons", PackedStringArray()))})
	if next.p_success < _profile.p - RISK_EPSILON:
		return _decision("hold", "forecast_too_risky", attack, {"p": next.p_success})

	if not certain and _timer - _last_raise < _profile.raise_delay:
		return _decision("hold", "raise_delay", attack)
	return _act("raise", attack, {"p": next.p_success, "expected_used": next.used_nominal, "certain": certain, "verify_attacks": VERIFY_CERTAIN if certain else VERIFY_CAREFUL, "target": target})


## attack names profitable_level, the level that brings the most, and may name unlock_level, the highest
## level unlocked, worth one win to open the next. A lower to the profitable level is a choice, not a
## failure: the level left stays open.
func _try_profitable(attack: Dictionary) -> Dictionary:
	var unlock: int = attack.get("unlock_level", -1)
	var waits: bool = unlock > attack.level and _failed_unlocks.has(unlock) and attack.get("unlock_chance", 0.0) < _failed_unlocks[unlock] + RETRY_GAIN
	if waits:
		unlock = -1
	var target: int = unlock if unlock > attack.level else attack.profitable_level
	if target < 0:
		return _decision("hold", "levels_being_measured", attack)
	if target == attack.level:
		return _decision("hold", "unlock_waits_for_better_odds" if waits else "most_profitable", attack)
	if target < attack.level:
		if _timer - _last_lower < LOWER_DELAY:
			return _decision("hold", "lower_delay", attack)
		return _act("lower", attack, {"by_choice": true, "aim": "profit", "verify_attacks": VERIFY_CERTAIN, "target": target})
	if _raises_suspended:
		if _consecutive < WINDOW:
			return _decision("hold", "raises_suspended", attack)
		_raises_suspended = false
	if _consecutive < PROBE_AFTER:
		return _decision("hold", "gathering_successes", attack, {"successes": _consecutive})
	if target > attack.max_level:
		return _decision("hold", "at_game_maximum", attack)
	if not can_reach(target):
		return _decision("hold", "level_blocked", attack)
	if target == unlock:
		_probed_level = target
		_trial_from = attack.level
		_unlock_try = {"level": target, "chance": attack.get("unlock_chance", 0.0)}
		return _act("raise", attack, {"certain": false, "probe": true, "aim": "unlock", "verify_attacks": VERIFY_CERTAIN, "target": target})
	if _timer - _last_raise < _profile.raise_delay:
		return _decision("hold", "raise_delay", attack)
	return _act("raise", attack, {"certain": false, "aim": "profit", "verify_attacks": VERIFY_CAREFUL, "target": target})


## A try left without opening the next level failed: except for the aggressive profile, it is not made
## again until the odds there are clearly better. A level opened some other way no longer waits.
func _note_unlock_try(attack: Dictionary) -> void:
	for level: int in _failed_unlocks.keys():
		if level < attack.max_level:
			_failed_unlocks.erase(level)
	if _unlock_try.is_empty() or attack.level == _unlock_try.level:
		return
	if attack.max_level <= _unlock_try.level and not _profile.retries_unlock:
		_failed_unlocks[_unlock_try.level] = _unlock_try.chance
	_unlock_try = {}


func _act(direction: String, attack: Dictionary, details: Dictionary) -> Dictionary:
	if _action_busy:
		return _decision("hold", "previous_action_unverified", attack)
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
		if _timer - action[0] <= BUDGET_WINDOW and not action[2]:
			recent += 1
		if _timer - action[0] <= REVERSAL_WINDOW and not action[3]:
			if not previous.is_empty() and action[1] != previous:
				reversals += 1
			previous = action[1]
	# A try and its way back are expected: they must not freeze the regulator.
	var tried: bool = details.get("probe", false) or (direction == "lower" and attack.level == _probed_level)
	var free: bool = details.get("certain", false) or tried
	if recent >= BUDGET and not free:
		return _decision("hold", "budget_exhausted", attack)
	if not tried and not previous.is_empty() and direction != previous:
		reversals += 1
	if reversals >= REVERSALS:
		_frozen_until = _timer + FREEZE
		return _decision("hold", "frozen_by_reversals", attack, {"reversals": reversals})

	_undo = {"last_raise": _last_raise, "last_lower": _last_lower, "blocked": _blocked.duplicate(), "block_length": _block_length.duplicate()}
	_proposal = key
	_actions.append([_timer, direction, free, tried])
	if direction == "raise":
		_last_raise = _timer
	else:
		_last_lower = _timer
		if not details.get("by_choice", false):
			_block(attack.level)
	var assumed: int = details.get("target", attack.level + (1 if direction == "raise" else -1))
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
	_failures_in_row = 0


func _decision(kind: String, reason: String, attack: Dictionary, details: Dictionary = {}) -> Dictionary:
	var decision := {
		"decision": kind, "reason": reason, "real_level": attack.level, "profile": profile_name, "hypothetical": true,
		"margin": _profile.margin, "window_attacks": _history.size(), "window_failures": _history.count(true), "successes_in_row": _consecutive,
	}
	decision.merge(details)
	return decision
