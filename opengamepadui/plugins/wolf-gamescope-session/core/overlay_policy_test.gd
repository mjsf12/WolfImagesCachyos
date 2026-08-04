extends GutTest

const OverlayPolicy := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_policy.gd"
)


func test_game_entry_enables_overlay_like_overlay_return_patch() -> void:
	var actual := OverlayPolicy.decision(true, false, 413091, 769)

	assert_eq(actual["overlay_value"], 1)
	assert_false(actual["reset_baselayer"])


func test_true_game_exit_disables_overlay_like_overlay_return_patch() -> void:
	var actual := OverlayPolicy.decision(false, false, 413091, 769)

	assert_eq(actual["overlay_value"], 0)
	assert_false(actual["reset_baselayer"])


func test_menu_push_keeps_overlay_like_overlay_menu_patch() -> void:
	var actual := OverlayPolicy.decision(true, false, 413091, 769)

	assert_eq(actual["overlay_value"], 1)


func test_final_cleanup_always_disables_overlay() -> void:
	var actual := OverlayPolicy.decision(true, true, 413091, 769)

	assert_eq(actual["overlay_value"], 0)


func test_final_cleanup_restores_exact_idle_baselayer_apps() -> void:
	var actual := OverlayPolicy.decision(false, true, 413091, 769)

	assert_true(actual["reset_baselayer"])
	assert_eq(actual["baselayer_apps"], PackedInt64Array([413091, 769]))
