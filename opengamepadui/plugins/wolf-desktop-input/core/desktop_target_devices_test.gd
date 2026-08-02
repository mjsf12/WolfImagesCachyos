extends GutTest

const DesktopTargetDevices := preload(
	"res://plugins/wolf-desktop-input/core/desktop_target_devices.gd"
)


func test_creates_keyboard_and_mouse_only_in_desktop_mode() -> void:
	assert_eq(
		DesktopTargetDevices.for_mode(true),
		PackedStringArray(["keyboard", "mouse"]),
	)
	assert_eq(DesktopTargetDevices.for_mode(false), PackedStringArray())


func test_scopes_virtual_targets_to_the_wolf_gamepad() -> void:
	assert_true(DesktopTargetDevices.supports("Wolf Virtual Gamepad"))
	assert_false(DesktopTargetDevices.supports("Xbox Wireless Controller"))
