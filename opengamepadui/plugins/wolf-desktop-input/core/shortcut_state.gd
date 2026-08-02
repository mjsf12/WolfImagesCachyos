extends RefCounted

## Pure shortcut state used by the plugin and its unit tests.

const GUIDE_EVENT := "ui_guide"
const TOGGLE_EVENT := "ui_action"
const GUIDE_CAPABILITY := "Gamepad:Button:Guide"
const START_CAPABILITY := "Gamepad:Button:Start"
const SELECT_CAPABILITY := "Gamepad:Button:Select"

var _guide_pressed := {}
var _toggle_pressed := {}


static func activation_triggers(generic_shortcut: bool) -> PackedStringArray:
	if generic_shortcut:
		return PackedStringArray([
			START_CAPABILITY,
			SELECT_CAPABILITY,
		])
	return PackedStringArray([GUIDE_CAPABILITY])


static func activation_needs_restore(
	current_triggers: PackedStringArray,
	current_target: String,
	generic_shortcut: bool,
) -> bool:
	if current_target != GUIDE_CAPABILITY:
		return true
	return current_triggers != activation_triggers(generic_shortcut)


## Track InputPlumber D-Bus events and return true once for Guide + West/X.
func handle_event(device_path: String, event: String, value: float) -> bool:
	var pressed := value > 0.5

	if event == GUIDE_EVENT:
		_guide_pressed[device_path] = pressed
		if not pressed:
			_toggle_pressed[device_path] = false
		return false

	if event != TOGGLE_EVENT:
		return false

	if not pressed:
		_toggle_pressed[device_path] = false
		return false

	if not _guide_pressed.get(device_path, false):
		return false
	if _toggle_pressed.get(device_path, false):
		return false

	_toggle_pressed[device_path] = true
	return true


func forget_device(device_path: String) -> void:
	_guide_pressed.erase(device_path)
	_toggle_pressed.erase(device_path)
