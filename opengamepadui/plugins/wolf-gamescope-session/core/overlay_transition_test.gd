extends GutTest

const OverlayPolicy := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_policy.gd"
)
const OverlayTransition := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_transition.gd"
)


func test_final_cleanup_supersedes_state_exit_from_same_stack_mutation() -> void:
	var transition := OverlayTransition.new()
	var state_exit := transition.request(
		OverlayPolicy.decision(true, false, 413091, 769),
		"in_game_exited",
	)
	var final_cleanup := transition.request(
		OverlayPolicy.decision(false, true, 413091, 769),
		"all_apps_stopped",
	)

	assert_false(transition.is_current(state_exit))
	assert_eq(transition.current_decision(state_exit), {})
	assert_false(transition.commit(state_exit))
	assert_true(transition.commit(final_cleanup))
	assert_eq(transition.applied_decision["overlay_value"], 0)
	assert_true(transition.applied_decision["reset_baselayer"])


func test_new_game_entry_supersedes_pending_idle_cleanup() -> void:
	var transition := OverlayTransition.new()
	var cleanup := transition.request(
		OverlayPolicy.decision(false, true, 413091, 769),
		"all_apps_stopped",
	)
	var new_game := transition.request(
		OverlayPolicy.decision(true, false, 413091, 769),
		"in_game_entered",
	)

	assert_false(transition.commit(cleanup))
	assert_true(transition.commit(new_game))
	assert_eq(transition.applied_decision["overlay_value"], 1)
	assert_false(transition.applied_decision["reset_baselayer"])
