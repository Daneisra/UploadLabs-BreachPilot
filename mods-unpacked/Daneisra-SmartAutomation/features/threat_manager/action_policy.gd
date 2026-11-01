extends RefCounted
## What this build may do to the game. In the repository, ACTIONS_ENABLED stays false: only
## tools/build_zip.py --trial turns it on, in the archive of an authorized trial and nowhere else.

const ACTIONS_ENABLED := false

## What the current active trial allows: a limited number of changes on the listed types.
const TRIAL_ID := "final-session-v2"
const TRIAL_BUILD := "trial.6"
const TRIAL_TYPES: Array[String] = ["breach_government", "breach_corps"]
const TRIAL_MIN_LEVEL := 0
## No limit of its own: the game's maximum still applies.
const TRIAL_MAX_LEVEL := -1
const TRIAL_PROFILE := "balanced"
const TRIAL_MAX_ACTIONS := 40
const TRIAL_VERIFY_ATTACKS := 3
## Seconds of the game's timer between two changes that are not certain, whatever their direction.
const TRIAL_MIN_GAP := 30.0
## The target level must be forecast this safe. A raise is judged with the profile's margin, a lower without.
const TRIAL_MIN_TARGET_SUCCESS := 0.99
## Written before the first call: a restart ends the trial, even with actions left. It is not part of
## a save. Each trial has its own: the markers of earlier trials are kept.
const TRIAL_MARKER := "user://smart_automation/trial_6_used.json"
