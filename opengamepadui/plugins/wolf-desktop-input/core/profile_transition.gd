extends RefCounted

## Tracks profile intent independently from the profile currently confirmed on
## InputPlumber. Every request invalidates older deferred work. This gives the
## plugin latest-request-wins semantics without relying on callback ordering.

var generation := 0
var desired_desktop_mode := false
var applied_desktop_mode := false
var reason := "startup"
var show_notification := false


func request(enabled: bool, notify: bool, request_reason: String) -> int:
	generation += 1
	desired_desktop_mode = enabled
	reason = request_reason
	show_notification = notify
	return generation


func refresh(request_reason: String) -> int:
	return request(desired_desktop_mode, false, request_reason)


func is_current(token: int) -> bool:
	return token == generation


func commit(token: int) -> bool:
	if not is_current(token):
		return false
	applied_desktop_mode = desired_desktop_mode
	return true


## Keep the last confirmed mode when the latest transition cannot be applied.
## Incrementing the generation also invalidates verification callbacks that
## were already queued for the rejected transaction.
func reject(token: int) -> bool:
	if not is_current(token):
		return false
	desired_desktop_mode = applied_desktop_mode
	generation += 1
	show_notification = false
	return true


## Entering desktop mode must block gamepad delivery before loading the mouse
## profile. Leaving must remain blocked until the gamepad profile is confirmed.
func route_requires_desktop_guard() -> bool:
	return desired_desktop_mode or applied_desktop_mode
