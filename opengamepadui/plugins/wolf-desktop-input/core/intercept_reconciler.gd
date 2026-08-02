extends RefCounted

## Applies the desired route to both OpenGamepadUI's defaults and every live
## InputPlumber composite. The global resource can update its cached value
## without writing an already-created D-Bus device, so live devices must always
## receive the assignment even when their local wrapper reports the same mode.


static func apply_mode(input_plumber, devices: Array, mode: int) -> int:
	input_plumber.set_intercept_mode(mode)
	var writes := 0
	for device in devices:
		if not is_instance_valid(device):
			continue
		device.intercept_mode = mode
		writes += 1
	return writes
