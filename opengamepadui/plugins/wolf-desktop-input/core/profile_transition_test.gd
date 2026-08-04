extends GutTest

const ProfileTransition := preload(
	"res://plugins/wolf-desktop-input/core/profile_transition.gd"
)


func test_new_request_invalidates_older_deferred_work() -> void:
	var transition := ProfileTransition.new()
	var desktop_token := transition.request(true, true, "desktop")
	var gamepad_token := transition.request(false, false, "game")

	assert_false(transition.is_current(desktop_token))
	assert_true(transition.is_current(gamepad_token))
	assert_false(transition.commit(desktop_token))
	assert_true(transition.commit(gamepad_token))
	assert_false(transition.applied_desktop_mode)


func test_rapid_toggle_commits_only_the_last_intention() -> void:
	var transition := ProfileTransition.new()
	transition.request(true, false, "on-1")
	transition.request(false, false, "off")
	var final_token := transition.request(true, false, "on-2")

	assert_true(transition.commit(final_token))
	assert_true(transition.applied_desktop_mode)


func test_refresh_preserves_intent_but_supersedes_pending_verification() -> void:
	var transition := ProfileTransition.new()
	var original := transition.request(true, true, "shortcut")
	var refreshed := transition.refresh("popup_closed")

	assert_false(transition.is_current(original))
	assert_true(transition.is_current(refreshed))
	assert_true(transition.desired_desktop_mode)
	assert_false(transition.show_notification)


func test_exit_keeps_desktop_guard_until_gamepad_commit() -> void:
	var transition := ProfileTransition.new()
	var enter_token := transition.request(true, false, "enter")
	transition.commit(enter_token)
	var exit_token := transition.request(false, false, "exit")

	assert_true(transition.route_requires_desktop_guard())
	transition.commit(exit_token)
	assert_false(transition.route_requires_desktop_guard())


func test_failed_transition_returns_to_last_confirmed_mode() -> void:
	var transition := ProfileTransition.new()
	var enter_token := transition.request(true, true, "enter")

	assert_true(transition.reject(enter_token))
	assert_false(transition.desired_desktop_mode)
	assert_false(transition.applied_desktop_mode)
	assert_false(transition.is_current(enter_token))


func test_failed_gamepad_restore_keeps_desktop_guarded() -> void:
	var transition := ProfileTransition.new()
	var enter_token := transition.request(true, false, "enter")
	transition.commit(enter_token)
	var exit_token := transition.request(false, true, "exit")

	assert_true(transition.reject(exit_token))
	assert_true(transition.desired_desktop_mode)
	assert_true(transition.applied_desktop_mode)
	assert_true(transition.route_requires_desktop_guard())
