extends RefCounted

## Serializes profiles in the subset accepted by InputPlumber's YAML parser.
## Godot parses every JSON number as a float and tab-indented JSON is valid
## JSON, but InputPlumber 0.78 rejects both a `version` of 1.0 and YAML tabs.
static func serialize(profile: Dictionary) -> String:
	var normalized := profile.duplicate(true) as Dictionary
	normalized["version"] = int(normalized.get("version", 1))
	return JSON.stringify(normalized, "  ") + "\n"


## Write every live composite and count only D-Bus-confirmed profile loads.
## OpenGamepadUI's Rust wrapper discards LoadProfilePath errors.
static func apply_profile(
		devices: Array,
		path: String,
		expected_name: String,
	) -> int:
	var confirmed := 0
	for device in devices:
		if not is_instance_valid(device):
			continue
		device.load_profile_path(path)
		if str(device.profile_name) == expected_name:
			confirmed += 1
	return confirmed
