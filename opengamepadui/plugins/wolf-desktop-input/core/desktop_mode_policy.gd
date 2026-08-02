extends RefCounted

## Desktop input may remain active while moving between desktop launchers, but
## a game transition must start from a real gamepad profile.
static func should_restore_for_app(
		desktop_mode: bool,
		is_desktop_launcher: bool,
	) -> bool:
	return desktop_mode and not is_desktop_launcher
