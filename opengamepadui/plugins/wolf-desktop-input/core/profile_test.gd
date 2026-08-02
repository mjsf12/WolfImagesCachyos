extends GutTest

const PROFILE_PATH := "res://plugins/wolf-desktop-input/profiles/desktop_mouse.json"


func test_desktop_profile_has_required_mouse_mappings() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert_not_null(file)
	var profile = JSON.parse_string(file.get_as_text())
	assert_typeof(profile, TYPE_DICTIONARY)
	assert_eq(profile["target_devices"], ["xbox-series", "mouse", "keyboard"])

	var targets := {}
	for mapping: Dictionary in profile["mapping"]:
		targets[mapping["name"]] = mapping["target_events"]

	assert_true(targets.has("Joystick Mouse"))
	assert_eq(
		targets["Joystick Mouse"][0]["mouse"]["motion"]["speed_pps"],
		800.0,
	)
	assert_eq(targets["A Left Click"][0]["mouse"]["button"], "Left")
	assert_eq(targets["B Right Click"][0]["mouse"]["button"], "Right")
	assert_eq(targets["Right Trigger Left Click"][0]["mouse"]["button"], "Left")
	assert_eq(targets["Left Trigger Right Click"][0]["mouse"]["button"], "Right")
	assert_eq(targets["Right Bumper Scroll Up"][0]["mouse"]["button"], "WheelUp")
	assert_eq(targets["Left Bumper Scroll Down"][0]["mouse"]["button"], "WheelDown")
	assert_true(targets["Block Left Stick"].is_empty())
	assert_true(targets["Block North"].is_empty())


func test_desktop_profile_preserves_global_shortcuts() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var profile = JSON.parse_string(file.get_as_text())
	var targets := {}
	var source_buttons: Array[String] = []
	for mapping: Dictionary in profile["mapping"]:
		targets[mapping["name"]] = mapping["target_events"]
		var source: Dictionary = mapping.get("source_event", {})
		var gamepad: Dictionary = source.get("gamepad", {})
		if gamepad.has("button"):
			source_buttons.append(gamepad["button"] as String)

	assert_eq(targets["Guide"][0]["dbus"], "ui_guide")
	assert_eq(targets["Quick Access"][0]["dbus"], "ui_quick")
	assert_eq(
		targets["Desktop Toggle"][0]["dbus"],
		"ui_action",
		"The same chord must be able to leave desktop mode",
	)
	assert_false("Start" in source_buttons, "Start must remain available to the Guide chord")
	assert_false("Select" in source_buttons, "Select must remain available to the Guide chord")
