extends GutTest

const InterceptPolicy := preload("res://plugins/wolf-desktop-input/core/intercept_policy.gd")


func test_passes_input_to_an_active_game_without_a_popup() -> void:
	assert_eq(InterceptPolicy.desired_mode(true, false), 1)


func test_intercepts_input_while_an_in_game_popup_is_open() -> void:
	assert_eq(InterceptPolicy.desired_mode(true, true), 2)


func test_intercepts_input_on_the_frontend() -> void:
	assert_eq(InterceptPolicy.desired_mode(false, false), 2)
