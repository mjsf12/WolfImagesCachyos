extends RefCounted

## Pure target-device policy for Wolf's Moonlight-provided virtual gamepad.

const WOLF_VIRTUAL_GAMEPAD := "Wolf Virtual Gamepad"


static func supports(device_name: String) -> bool:
	return device_name == WOLF_VIRTUAL_GAMEPAD


static func for_mode(desktop_mode: bool) -> PackedStringArray:
	if desktop_mode:
		return PackedStringArray(["keyboard", "mouse"])
	return PackedStringArray()
