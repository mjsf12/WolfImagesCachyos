extends GutTest

const DesktopModePolicy := preload(
	"res://plugins/wolf-desktop-input/core/desktop_mode_policy.gd"
)


func test_restores_gamepad_when_a_game_starts_from_desktop_mode() -> void:
	assert_true(DesktopModePolicy.should_restore_for_app(true, false))


func test_keeps_desktop_mode_for_a_desktop_launcher() -> void:
	assert_false(DesktopModePolicy.should_restore_for_app(true, true))


func test_does_nothing_when_desktop_mode_is_already_disabled() -> void:
	assert_false(DesktopModePolicy.should_restore_for_app(false, false))


func test_recognizes_gamescope_focus_switch_inside_the_same_app() -> void:
	assert_true(DesktopModePolicy.is_same_app_name("DOOM Eternal", "DOOM Eternal"))
	assert_false(DesktopModePolicy.is_same_app_name("DOOM Eternal", "Heroic"))
	assert_false(DesktopModePolicy.is_same_app_name("", ""))
