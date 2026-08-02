extends RefCounted

## Schedules a short burst of activation reapplications. OpenGamepadUI's Card
## UI writes directly to each CompositeDevice during startup, bypassing the
## global InputPlumberInstance state, so comparing only that state is not enough.

const INTERVAL := 0.25
const ACTIVE_WINDOW := 10.0

var _elapsed := 0.0
var _remaining := 0.0


func arm() -> void:
	_elapsed = 0.0
	_remaining = ACTIVE_WINDOW


func advance(delta: float) -> bool:
	if _remaining <= 0.0:
		return false
	_remaining = maxf(0.0, _remaining - delta)
	_elapsed += delta
	if _elapsed < INTERVAL:
		return false
	_elapsed = 0.0
	return true


func is_active() -> bool:
	return _remaining > 0.0
