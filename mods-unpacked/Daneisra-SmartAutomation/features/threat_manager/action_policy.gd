extends RefCounted
## What this build may do to the game. In the repository, ACTIONS_ENABLED stays false: only
## tools/build_zip.py --trial turns it on, in the archive of an authorized trial and nowhere else.

const ACTIONS_ENABLED := false

## What the current active trial allows: a few changes of one type, between two levels.
const TRIAL_ID := "government-0-to-4-v1"
const TRIAL_BUILD := "trial.3"
const TRIAL_TYPE := "breach_government"
const TRIAL_MIN_LEVEL := 0
const TRIAL_MAX_LEVEL := 4
const TRIAL_PROFILE := "conservative"
const TRIAL_MAX_ACTIONS := 4
const TRIAL_VERIFY_ATTACKS := 3
## Seconds of the game's timer between two changes, whatever their direction.
const TRIAL_MIN_GAP := 60.0
## The target level must be forecast this safe. A raise is judged with the profile's margin, a lower without.
const TRIAL_MIN_TARGET_SUCCESS := 1.0
## Written before the first call: a restart ends the trial, even with actions left. It is not part of
## a save. Each trial has its own: the markers of earlier trials are kept.
const TRIAL_MARKER := "user://smart_automation/trial_3_used.json"
