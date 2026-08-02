extends RefCounted

const INTERCEPT_MODE_PASS := 1
const INTERCEPT_MODE_ALL := 2


static func desired_mode(in_game: bool, popup_open: bool) -> int:
	if in_game and not popup_open:
		return INTERCEPT_MODE_PASS
	return INTERCEPT_MODE_ALL
