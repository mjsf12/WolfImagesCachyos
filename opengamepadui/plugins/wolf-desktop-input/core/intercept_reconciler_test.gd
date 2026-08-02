extends GutTest

const InterceptReconciler := preload(
	"res://plugins/wolf-desktop-input/core/intercept_reconciler.gd"
)


class FakeInputPlumber extends RefCounted:
	var modes: Array[int] = []

	func set_intercept_mode(mode: int) -> void:
		modes.append(mode)


class FakeCompositeDevice extends RefCounted:
	var dbus_path := "/org/shadowblip/InputPlumber/CompositeDevice0"
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


func test_uses_signal_tracked_device_when_ogui_cache_is_empty() -> void:
	var device := FakeCompositeDevice.new()

	var devices := InterceptReconciler.collect_devices(
		[],
		{device.dbus_path: device},
	)

	assert_eq(devices, [device])


func test_deduplicates_tracked_and_cached_device_by_dbus_path() -> void:
	var tracked := FakeCompositeDevice.new()
	var cached := FakeCompositeDevice.new()

	var devices := InterceptReconciler.collect_devices(
		[cached],
		{tracked.dbus_path: tracked},
	)

	assert_eq(devices, [tracked])
