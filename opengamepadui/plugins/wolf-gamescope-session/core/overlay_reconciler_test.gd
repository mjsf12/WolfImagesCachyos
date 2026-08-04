extends GutTest

const OverlayPolicy := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_policy.gd"
)
const OverlayReconciler := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_reconciler.gd"
)


class FakeOgui extends RefCounted:
	var calls: Array[Array] = []
	var response := OK

	func set_overlay(window_id: int, value: int) -> int:
		calls.append([window_id, value])
		return response


class FakePrimary extends RefCounted:
	var remove_calls := 0
	var baselayer_apps := PackedInt64Array()

	func remove_baselayer_window() -> void:
		remove_calls += 1


func test_applies_overlay_value_to_discovered_ogui_window() -> void:
	var ogui := FakeOgui.new()
	var primary := FakePrimary.new()
	var decision := OverlayPolicy.decision(true, false, 413091, 769)

	var result := OverlayReconciler.apply(primary, ogui, 1234, decision)

	assert_eq(ogui.calls, [[1234, 1]])
	assert_true(result["overlay_applied"])
	assert_eq(primary.remove_calls, 0)


func test_final_cleanup_clears_window_and_stale_app_ids() -> void:
	var ogui := FakeOgui.new()
	var primary := FakePrimary.new()
	var decision := OverlayPolicy.decision(false, true, 413091, 769)

	var result := OverlayReconciler.apply(primary, ogui, 1234, decision)

	assert_eq(ogui.calls, [[1234, 0]])
	assert_eq(primary.remove_calls, 1)
	assert_eq(primary.baselayer_apps, PackedInt64Array([413091, 769]))
	assert_true(result["baselayer_reset"])


func test_does_not_claim_success_without_an_overlay_window() -> void:
	var ogui := FakeOgui.new()
	var decision := OverlayPolicy.decision(true, false, 413091, 769)

	var result := OverlayReconciler.apply(null, ogui, 0, decision)

	assert_true(ogui.calls.is_empty())
	assert_false(result["overlay_applied"])


func test_propagates_gamescope_atom_write_failure() -> void:
	var ogui := FakeOgui.new()
	ogui.response = FAILED
	var decision := OverlayPolicy.decision(true, false, 413091, 769)

	var result := OverlayReconciler.apply(null, ogui, 1234, decision)

	assert_false(result["overlay_applied"])
