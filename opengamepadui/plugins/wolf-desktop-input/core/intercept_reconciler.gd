extends RefCounted

## Applies the desired route to both OpenGamepadUI's defaults and every live
## InputPlumber composite. The global resource can update its cached value
## without writing an already-created D-Bus device, so live devices must always
## receive the assignment even when their local wrapper reports the same mode.
## Count only assignments confirmed by a fresh D-Bus property read: the OGUI
## 0.46 Rust wrapper discards setter errors, including polkit authorization.


static func apply_mode(input_plumber, devices: Array, mode: int) -> int:
	input_plumber.set_intercept_mode(mode)
	var writes := 0
	for device in devices:
		if not is_instance_valid(device):
			continue
		device.intercept_mode = mode
		if device.intercept_mode == mode:
			writes += 1
	return writes


## Prefer objects captured from composite_device_added. In OpenGamepadUI 0.46,
## get_composite_devices() can temporarily be empty even though the added signal
## already supplied a usable CompositeDevice. Merge both sources by D-Bus path.
static func collect_devices(cached_devices: Array, tracked_devices: Dictionary) -> Array:
	var devices: Array = []
	var seen_paths := {}
	for device in tracked_devices.values():
		_append_device(device, devices, seen_paths)
	for device in cached_devices:
		_append_device(device, devices, seen_paths)
	return devices


static func _append_device(device, devices: Array, seen_paths: Dictionary) -> void:
	if not is_instance_valid(device):
		return
	var path := str(device.dbus_path)
	if seen_paths.has(path):
		return
	seen_paths[path] = true
	devices.append(device)
