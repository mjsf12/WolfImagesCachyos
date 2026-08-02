extends RefCounted

const INTERCEPT_MODE_PASS := 1
const INTERCEPT_MODE_ALL := 2
const INTERCEPT_MODE_GAMEPAD_ONLY := 3


static func desired_mode(in_game: bool, popup_open: bool, desktop_mode: bool = false) -> int:
	if in_game and not popup_open:
		if desktop_mode:
			return INTERCEPT_MODE_GAMEPAD_ONLY
		return INTERCEPT_MODE_PASS
	return INTERCEPT_MODE_ALL
