extends GutTest

const InterceptReconciler := preload(
	"res://plugins/wolf-desktop-input/core/intercept_reconciler.gd"
)


class FakeInputPlumber extends RefCounted:
	var modes: Array[int] = []

	func set_intercept_mode(mode: int) -> void:
		modes.append(mode)


class FakeCompositeDevice extends RefCounted:
	var writes := 0
	var intercept_mode := 0:
		set(value):
			intercept_mode = value
			writes += 1


func test_writes_the_global_and_live_composite_modes() -> void:
	var input_plumber := FakeInputPlumber.new()
	var device := FakeCompositeDevice.new()

	var writes := InterceptReconciler.apply_mode(input_plumber, [device], 1)

	assert_eq(input_plumber.modes, [1])
	assert_eq(device.intercept_mode, 1)
	assert_eq(device.writes, 1)
	assert_eq(writes, 1)


func test_rewrites_live_composite_when_its_cached_mode_already_matches() -> void:
	var input_plumber := FakeInputPlumber.new()
	var device := FakeCompositeDevice.new()
	device.intercept_mode = 1
	device.writes = 0

	InterceptReconciler.apply_mode(input_plumber, [device], 1)
	InterceptReconciler.apply_mode(input_plumber, [device], 1)

	assert_eq(device.writes, 2, "Every reconciliation must reach the real D-Bus device")
