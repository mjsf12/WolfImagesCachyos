extends GutTest

const ProfileReconciler := preload(
	"res://plugins/wolf-desktop-input/core/profile_reconciler.gd"
)


class AcceptedDevice extends RefCounted:
	var profile_name := "OpenGamepadUI Default"
	var loaded_paths: Array[String] = []

	func load_profile_path(path: String) -> void:
		loaded_paths.append(path)
		profile_name = "Wolf Desktop Mouse"


class DeniedDevice extends RefCounted:
	var profile_name := "OpenGamepadUI Default"
	var attempts := 0

	func load_profile_path(_path: String) -> void:
		attempts += 1


func test_serializes_yaml_compatible_json_with_an_integer_version() -> void:
	var parsed = JSON.parse_string('{"version":1,"name":"Test","mapping":[]}')
	assert_eq(typeof(parsed["version"]), TYPE_FLOAT)

	var encoded := ProfileReconciler.serialize(parsed)

	assert_false("\t" in encoded)
	assert_true('"version": 1' in encoded)
	assert_false('"version": 1.0' in encoded)


func test_confirms_a_profile_loaded_by_the_live_composite() -> void:
	var device := AcceptedDevice.new()

	var confirmed := ProfileReconciler.apply_profile(
		[device],
		"user://wolf_desktop_mouse.json",
		"Wolf Desktop Mouse",
	)

	assert_eq(device.loaded_paths, ["user://wolf_desktop_mouse.json"])
	assert_eq(confirmed, 1)


func test_does_not_report_a_silently_rejected_profile_as_loaded() -> void:
	var device := DeniedDevice.new()

	var confirmed := ProfileReconciler.apply_profile(
		[device],
		"user://wolf_desktop_mouse.json",
		"Wolf Desktop Mouse",
	)

	assert_eq(device.attempts, 1)
	assert_eq(confirmed, 0)


func test_counts_only_devices_with_the_confirmed_profile() -> void:
	var accepted := AcceptedDevice.new()
	var denied := DeniedDevice.new()

	assert_eq(
		ProfileReconciler.count_profile(
			[accepted, denied],
			"OpenGamepadUI Default",
		),
		2,
	)
	accepted.profile_name = "Wolf Desktop Mouse"
	assert_eq(
		ProfileReconciler.count_profile(
			[accepted, denied],
			"OpenGamepadUI Default",
		),
		1,
	)


func test_reads_profile_name_from_json() -> void:
	assert_eq(
		ProfileReconciler.profile_name_from_path(
			"res://assets/gamepad/profiles/default.json",
		),
		"OpenGamepadUI Default",
	)
	assert_eq(ProfileReconciler.profile_name_from_path("user://missing.json"), "")
