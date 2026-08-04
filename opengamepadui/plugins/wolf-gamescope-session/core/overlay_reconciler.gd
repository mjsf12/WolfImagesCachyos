extends RefCounted

## Applies a pure overlay decision to the two public Gamescope XWayland
## objects. Kept separate so the complete mutation can be tested with fakes.


static func apply(
		xwayland_primary,
		xwayland_ogui,
		overlay_window_id: int,
		decision: Dictionary,
	) -> Dictionary:
	var result := {
		"overlay_applied": false,
		"baselayer_reset": false,
	}
	if xwayland_ogui != null and overlay_window_id > 0:
		result["overlay_applied"] = (
			xwayland_ogui.set_overlay(
				overlay_window_id,
				int(decision["overlay_value"]),
			) == OK
		)

	if decision.get("reset_baselayer", false) and xwayland_primary != null:
		xwayland_primary.remove_baselayer_window()
		xwayland_primary.baselayer_apps = decision["baselayer_apps"]
		result["baselayer_reset"] = true
	return result
