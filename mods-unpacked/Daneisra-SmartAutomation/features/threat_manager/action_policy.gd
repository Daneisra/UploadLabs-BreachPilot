extends RefCounted
## What this build may do to the game. In the repository, ACTIONS_ENABLED stays false: only
## tools/build_zip.py --trial turns it on, in the archive of an authorized trial and nowhere else.

const ACTIONS_ENABLED := false

## The only change the first active trial allows, once.
const TRIAL_ID := "government-2-to-3-v1"
const TRIAL_TYPE := "breach_government"
const TRIAL_DIRECTION := "raise"
const TRIAL_FROM := 2
const TRIAL_TO := 3
const TRIAL_PROFILE := "conservative"
const TRIAL_MAX_ACTIONS := 1
const TRIAL_VERIFY_ATTACKS := 3
## Written before the call: not even a restart can make this trial act twice. It is not part of a save.
const TRIAL_MARKER := "user://smart_automation/trial_used.json"
