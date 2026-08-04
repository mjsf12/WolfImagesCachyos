extends RefCounted

## Pure policy equivalent to the former overlay-return, overlay-menu and
## final-overlay-cleanup patches.

const OVERLAY_DISABLED := 0
const OVERLAY_ENABLED := 1


static func decision(
		game_state_present: bool,
		final_cleanup: bool,
		extra_unknown_app_id: int,
		overlay_app_id: int,
	) -> Dictionary:
	var overlay_value := OVERLAY_ENABLED if game_state_present else OVERLAY_DISABLED
	if final_cleanup:
		overlay_value = OVERLAY_DISABLED
	return {
		"overlay_value": overlay_value,
		"reset_baselayer": final_cleanup,
		"baselayer_apps": PackedInt64Array([
			extra_unknown_app_id,
			overlay_app_id,
		]),
	}
