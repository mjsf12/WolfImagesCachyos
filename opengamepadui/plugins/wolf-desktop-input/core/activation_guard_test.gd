extends GutTest

const ActivationGuard := preload("res://plugins/wolf-desktop-input/core/activation_guard.gd")


func test_reapplies_at_intervals_during_the_active_window() -> void:
	var guard := ActivationGuard.new()
	guard.arm()

	assert_true(guard.is_active())
	assert_false(guard.advance(0.10))
	assert_true(guard.advance(0.15))
	assert_false(guard.advance(0.20))
	assert_true(guard.advance(0.05))


func test_stops_after_the_active_window() -> void:
	var guard := ActivationGuard.new()
	guard.arm()

	assert_true(guard.advance(ActivationGuard.ACTIVE_WINDOW))
	assert_false(guard.is_active())
	assert_false(guard.advance(ActivationGuard.INTERVAL))


func test_can_be_rearmed_for_a_new_device() -> void:
	var guard := ActivationGuard.new()
	guard.arm()
	guard.advance(ActivationGuard.ACTIVE_WINDOW)

	guard.arm()
	assert_true(guard.is_active())
	assert_true(guard.advance(ActivationGuard.INTERVAL))
