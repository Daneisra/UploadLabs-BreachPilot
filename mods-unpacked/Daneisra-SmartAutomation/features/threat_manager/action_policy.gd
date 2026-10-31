extends RefCounted
## What this build may do to the game. In the repository, ACTIONS_ENABLED stays false: only
## tools/build_zip.py --trial turns it on, in the archive of an authorized trial and nowhere else.

const ACTIONS_ENABLED := false

## The only change the current active trial allows, once.
const TRIAL_ID := "government-5-to-4-v1"
const TRIAL_BUILD := "trial.2"
const TRIAL_TYPE := "breach_government"
const TRIAL_DIRECTION := "lower"
const TRIAL_FROM := 5
const TRIAL_TO := 4
const TRIAL_PROFILE := "conservative"
const TRIAL_MAX_ACTIONS := 1
const TRIAL_VERIFY_ATTACKS := 3
## The target level must be forecast this safe, without the margin that only applies to raises.
const TRIAL_MIN_TARGET_SUCCESS := 1.0
## Written before the call: not even a restart can make this trial act twice. It is not part of a save.
## Each trial has its own: the marker of an earlier trial is kept.
const TRIAL_MARKER := "user://smart_automation/trial_2_used.json"
