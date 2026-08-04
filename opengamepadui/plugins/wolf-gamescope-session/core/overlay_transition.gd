extends RefCounted

## Latest-request-wins coordinator for callbacks emitted during one state-stack
## mutation. In particular, final app cleanup must invalidate the earlier
## in_game_state.state_exited reconciliation.

var generation := 0
var desired_decision: Dictionary = {}
var applied_decision: Dictionary = {}
var reason := "startup"


func request(decision: Dictionary, request_reason: String) -> int:
	generation += 1
	desired_decision = decision.duplicate(true)
	reason = request_reason
	return generation


func is_current(token: int) -> bool:
	return token == generation


func current_decision(token: int) -> Dictionary:
	if not is_current(token):
		return {}
	return desired_decision.duplicate(true)


func commit(token: int) -> bool:
	if not is_current(token):
		return false
	applied_decision = desired_decision.duplicate(true)
	return true
