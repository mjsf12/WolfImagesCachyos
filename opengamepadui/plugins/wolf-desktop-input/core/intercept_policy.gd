extends RefCounted

const INTERCEPT_MODE_PASS := 1
const INTERCEPT_MODE_ALL := 2
const INTERCEPT_MODE_GAMEPAD_ONLY := 3


static func desired_mode(
		game_running: bool,
		game_in_foreground: bool,
		popup_open: bool,
		desktop_mode: bool = false,
	) -> int:
	# A running game can remain underneath a normal frontend page in the global
	# state stack. Pass input only when that game is also the foreground state.
	if game_running and game_in_foreground and not popup_open:
		if desktop_mode:
			return INTERCEPT_MODE_GAMEPAD_ONLY
		return INTERCEPT_MODE_PASS
	return INTERCEPT_MODE_ALL
