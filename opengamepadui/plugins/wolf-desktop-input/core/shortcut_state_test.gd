extends GutTest

const ShortcutState := preload("res://plugins/wolf-desktop-input/core/shortcut_state.gd")


func test_uses_start_select_for_generic_controllers() -> void:
	assert_eq(
		ShortcutState.activation_triggers(true),
		PackedStringArray([
			"Gamepad:Button:Start",
			"Gamepad:Button:Select",
		]),
	)


func test_keeps_guide_for_standard_controllers() -> void:
	assert_eq(
		ShortcutState.activation_triggers(false),
		PackedStringArray(["Gamepad:Button:Guide"]),
	)


func test_guide_and_action_toggle_only_once_per_press() -> void:
	var state := ShortcutState.new()
	var path := "/controller/0"

	assert_false(state.handle_event(path, "ui_guide", 1.0))
	assert_true(state.handle_event(path, "ui_action", 1.0))
	assert_false(state.handle_event(path, "ui_action", 1.0))
	assert_false(state.handle_event(path, "ui_action", 0.0))
	assert_false(
		state.handle_event(path, "ui_action", 1.0),
		"A missing Guide release must not leave a stale shortcut",
	)
	assert_false(state.handle_event(path, "ui_action", 0.0))
	assert_false(state.handle_event(path, "ui_guide", 1.0))
	assert_true(state.handle_event(path, "ui_action", 1.0))


func test_action_without_guide_does_not_toggle() -> void:
	var state := ShortcutState.new()

	assert_false(state.handle_event("/controller/0", "ui_action", 1.0))


func test_controller_state_is_independent() -> void:
	var state := ShortcutState.new()

	state.handle_event("/controller/0", "ui_guide", 1.0)
	assert_false(state.handle_event("/controller/1", "ui_action", 1.0))
	assert_true(state.handle_event("/controller/0", "ui_action", 1.0))


func test_forgetting_controller_clears_pressed_state() -> void:
	var state := ShortcutState.new()
	var path := "/controller/0"

	state.handle_event(path, "ui_guide", 1.0)
	state.forget_device(path)
	assert_false(state.handle_event(path, "ui_action", 1.0))
