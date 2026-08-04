extends GutTest

const InterceptPolicy := preload("res://plugins/wolf-desktop-input/core/intercept_policy.gd")


func test_passes_input_to_an_active_game_without_a_popup() -> void:
	assert_eq(InterceptPolicy.desired_mode(true, true, false, false), 1)


func test_desktop_mode_intercepts_gamepad_but_passes_mouse_and_keyboard() -> void:
	assert_eq(InterceptPolicy.desired_mode(true, true, false, true), 3)


func test_intercepts_input_while_an_in_game_popup_is_open() -> void:
	assert_eq(InterceptPolicy.desired_mode(true, false, true, true), 2)


func test_intercepts_input_on_the_frontend() -> void:
	assert_eq(InterceptPolicy.desired_mode(false, false, false, false), 2)


func test_intercepts_frontend_menu_above_a_running_game() -> void:
	assert_eq(
		InterceptPolicy.desired_mode(true, false, false, false),
		2,
		"A background game must not receive input while a frontend page is on top",
	)
