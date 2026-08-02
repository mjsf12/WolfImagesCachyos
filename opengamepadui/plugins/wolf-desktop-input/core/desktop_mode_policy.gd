extends RefCounted

## Desktop input may remain active while moving between desktop launchers, but
## a game transition must start from a real gamepad profile.
static func should_restore_for_app(
		desktop_mode: bool,
		is_desktop_launcher: bool,
	) -> bool:
	return desktop_mode and not is_desktop_launcher


static func is_same_app_name(from_name: String, to_name: String) -> bool:
	return not from_name.is_empty() and from_name == to_name
