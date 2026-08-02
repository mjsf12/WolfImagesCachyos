extends Plugin

const ShortcutState := preload("res://plugins/wolf-desktop-input/core/shortcut_state.gd")
const QuickBarRegistration := preload(
	"res://plugins/wolf-desktop-input/core/quick_bar_registration.gd"
)
const SETTINGS_SECTION := "plugin.wolf-desktop-input"
const SOURCE_PROFILE := "profiles/desktop_mouse.json"
const USER_PROFILE_DIR := "user://data/gamepad/profiles"
const USER_PROFILE := USER_PROFILE_DIR + "/wolf_desktop_mouse.json"
const GUIDE_ACTION := "ogui_guide_action"

var input_plumber := load("res://core/systems/input/input_plumber.tres") as InputPlumberInstance
var launch_manager := load("res://core/global/launch_manager.tres") as LaunchManager
var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager
var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
var popup_state_machine := load("res://assets/state/state_machines/popup_state_machine.tres") as StateMachine

var _shortcut_state := ShortcutState.new()
var _generic_shortcut := true
var _auto_launchers := false
var _mouse_speed := 800
var _desktop_mode := false
var _auto_owned := false
var _input_manager: InputManager
var _quick_bar_panel: Control
var _menus: Array[Dictionary] = []
var _watched_targets := {}
var _target_connections := {}
var _target_devices := {}


func _ready() -> void:
	logger = Log.get_logger("WolfDesktopInput", Log.LEVEL.INFO)
	_generic_shortcut = settings_manager.get_value(
		SETTINGS_SECTION,
		"generic_shortcut",
		true,
	) as bool
	_auto_launchers = settings_manager.get_value(
		SETTINGS_SECTION,
		"auto_launchers",
		false,
	) as bool
	_mouse_speed = settings_manager.get_value(
		SETTINGS_SECTION,
		"mouse_speed",
		800,
	) as int

	_install_desktop_profile()
	_input_manager = _find_input_manager(get_tree().root)
	if is_instance_valid(_input_manager):
		logger.info("Connected to the official InputManager")
	else:
		logger.warn("Official InputManager was not found during plugin startup")
	_connect_runtime_signals()
	_initialize_inputplumber()
	# Card UI also configures Guide interception during startup. Reapply once
	# after the current frame; the session helper remains authoritative for Wolf
	# virtual gamepads because Card UI bypasses this global resource.
	_configure_activation.call_deferred()

	# Never carry desktop mode across a frontend restart or plugin update.
	_desktop_mode = false
	_restore_gamepad_profile.call_deferred()
	_install_quick_bar.call_deferred()
	logger.info("Loaded; generic shortcut: " + str(_generic_shortcut))


func unload() -> void:
	_set_desktop_mode(false, false)
	_apply_standard_guide_activation()
	_disconnect_runtime_signals()
	for target_path: String in _watched_targets.keys():
		_disconnect_target(target_path)
	if is_instance_valid(_quick_bar_panel):
		_quick_bar_panel.queue_free()
	logger.info("Unloaded and restored gamepad input")


func get_settings_menu() -> Control:
	return _build_menu(false)


func _connect_runtime_signals() -> void:
	if not input_plumber.composite_device_added.is_connected(_on_device_added):
		input_plumber.composite_device_added.connect(_on_device_added)
	if not input_plumber.composite_device_removed.is_connected(_on_device_removed):
		input_plumber.composite_device_removed.connect(_on_device_removed)
	if not input_plumber.started.is_connected(_initialize_inputplumber):
		input_plumber.started.connect(_initialize_inputplumber)
	if not launch_manager.app_launched.is_connected(_on_app_launched):
		launch_manager.app_launched.connect(_on_app_launched)
	if not launch_manager.app_switched.is_connected(_on_app_switched):
		launch_manager.app_switched.connect(_on_app_switched)
	if not launch_manager.app_stopped.is_connected(_on_app_stopped):
		launch_manager.app_stopped.connect(_on_app_stopped)
	if not launch_manager.all_apps_stopped.is_connected(_on_all_apps_stopped):
		launch_manager.all_apps_stopped.connect(_on_all_apps_stopped)
	if not popup_state_machine.state_changed.is_connected(_on_popup_state_changed):
		popup_state_machine.state_changed.connect(_on_popup_state_changed)


func _disconnect_runtime_signals() -> void:
	if input_plumber.composite_device_added.is_connected(_on_device_added):
		input_plumber.composite_device_added.disconnect(_on_device_added)
	if input_plumber.composite_device_removed.is_connected(_on_device_removed):
		input_plumber.composite_device_removed.disconnect(_on_device_removed)
	if input_plumber.started.is_connected(_initialize_inputplumber):
		input_plumber.started.disconnect(_initialize_inputplumber)
	if launch_manager.app_launched.is_connected(_on_app_launched):
		launch_manager.app_launched.disconnect(_on_app_launched)
	if launch_manager.app_switched.is_connected(_on_app_switched):
		launch_manager.app_switched.disconnect(_on_app_switched)
	if launch_manager.app_stopped.is_connected(_on_app_stopped):
		launch_manager.app_stopped.disconnect(_on_app_stopped)
	if launch_manager.all_apps_stopped.is_connected(_on_all_apps_stopped):
		launch_manager.all_apps_stopped.disconnect(_on_all_apps_stopped)
	if popup_state_machine.state_changed.is_connected(_on_popup_state_changed):
		popup_state_machine.state_changed.disconnect(_on_popup_state_changed)


func _initialize_inputplumber() -> void:
	for device: CompositeDevice in input_plumber.get_composite_devices():
		_on_device_added(device)
	_configure_activation()


func _on_device_added(device: CompositeDevice) -> void:
	_apply_activation(device)
	_apply_activation.bind(device).call_deferred()
	for target in device.dbus_devices:
		var target_path := target.dbus_path as String
		if _watched_targets.has(target_path):
			continue
		var callback := _on_dbus_input_event.bind(device.dbus_path as String)
		target.input_event.connect(callback)
		_watched_targets[target_path] = target
		_target_connections[target_path] = callback
		_target_devices[target_path] = device.dbus_path as String
		logger.info("Watching InputPlumber target " + target_path)


func _on_device_removed(device_path: String) -> void:
	_shortcut_state.forget_device(device_path)
	var stale_targets: Array[String] = []
	for target_path: String in _watched_targets.keys():
		if _target_devices.get(target_path, "") == device_path:
			stale_targets.append(target_path)
	for target_path: String in stale_targets:
		_disconnect_target(target_path)


func _disconnect_target(target_path: String) -> void:
	var target = _watched_targets.get(target_path)
	var callback: Callable = _target_connections.get(target_path, Callable())
	if is_instance_valid(target) and callback.is_valid():
		if target.input_event.is_connected(callback):
			target.input_event.disconnect(callback)
	_watched_targets.erase(target_path)
	_target_connections.erase(target_path)
	_target_devices.erase(target_path)


func _apply_activation(device: CompositeDevice) -> void:
	var triggers := ShortcutState.activation_triggers(_generic_shortcut)
	device.set_intercept_activation(triggers, ShortcutState.GUIDE_CAPABILITY)
	logger.info(
		"Configured " + (device.name as String) + " system shortcut: " + str(triggers),
	)


func _configure_activation() -> void:
	var triggers := ShortcutState.activation_triggers(_generic_shortcut)
	input_plumber.set_intercept_activation(triggers, ShortcutState.GUIDE_CAPABILITY)


func _apply_standard_guide_activation() -> void:
	input_plumber.set_intercept_activation(
		PackedStringArray([ShortcutState.GUIDE_CAPABILITY]),
		ShortcutState.GUIDE_CAPABILITY,
	)


func _on_dbus_input_event(event: String, value: float, device_path: String) -> void:
	if not _shortcut_state.handle_event(device_path, event, value):
		return

	# Tell the official InputManager that this Guide chord performed an action.
	# Otherwise releasing Start+Select would also open the main menu.
	if is_instance_valid(_input_manager):
		_input_manager.action_press(device_path, GUIDE_ACTION)
	else:
		logger.warn("InputManager was not found; Guide release may also open the menu")

	_auto_owned = false
	_set_desktop_mode(not _desktop_mode, true)


func _set_desktop_mode(enabled: bool, show_notification: bool = true) -> void:
	if _desktop_mode == enabled:
		if enabled:
			_apply_desktop_profile()
		_refresh_menus()
		return

	_desktop_mode = enabled
	if enabled:
		_apply_desktop_profile()
	else:
		_restore_gamepad_profile()
	_refresh_menus()

	if show_notification:
		var text := "Desktop mouse enabled"
		if not enabled:
			text = "Gamepad profile restored"
		notification_manager.show(Notification.new(text))
	logger.info("Desktop mode: " + str(enabled))


func _apply_desktop_profile() -> void:
	if not FileAccess.file_exists(USER_PROFILE):
		_install_desktop_profile()
	if not FileAccess.file_exists(USER_PROFILE):
		logger.error("Desktop profile is unavailable: " + USER_PROFILE)
		return
	launch_manager.set_gamepad_profile(USER_PROFILE)


func _restore_gamepad_profile() -> void:
	var current_app := launch_manager.get_current_app()
	if current_app:
		launch_manager.set_app_gamepad_profile(current_app)
		return
	launch_manager.set_gamepad_profile("")


func _install_desktop_profile() -> void:
	var source_path := plugin_base + "/" + SOURCE_PROFILE
	var source := FileAccess.open(source_path, FileAccess.READ)
	if not source:
		logger.error("Unable to read packaged desktop profile: " + source_path)
		return
	var profile = JSON.parse_string(source.get_as_text())
	if not profile is Dictionary:
		logger.error("Packaged desktop profile is invalid JSON")
		return

	for mapping: Dictionary in profile.get("mapping", []):
		if mapping.get("name", "") != "Joystick Mouse":
			continue
		mapping["target_events"][0]["mouse"]["motion"]["speed_pps"] = _mouse_speed

	var absolute_dir := ProjectSettings.globalize_path(USER_PROFILE_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		logger.error("Unable to create gamepad profile directory: " + absolute_dir)
		return
	var destination := FileAccess.open(USER_PROFILE, FileAccess.WRITE)
	if not destination:
		logger.error("Unable to write desktop profile: " + USER_PROFILE)
		return
	destination.store_string(JSON.stringify(profile, "\t") + "\n")
	logger.info("Installed desktop profile with speed " + str(_mouse_speed))


func _on_popup_state_changed(_from: State, to: State) -> void:
	# InputManager loads the global profile while a Guide menu is open. Restore
	# desktop input only after the popup closes so its UI remains navigable.
	if to == null and _desktop_mode:
		_apply_desktop_profile.call_deferred()


func _on_app_launched(app: RunningApp) -> void:
	if not _auto_launchers or not _is_desktop_launcher(app):
		return
	_auto_owned = true
	_set_desktop_mode(true, true)


func _on_app_switched(_from: RunningApp, to: RunningApp) -> void:
	if _auto_launchers and _is_desktop_launcher(to):
		_auto_owned = true
		_set_desktop_mode(true, false)
		return
	if _auto_owned:
		_auto_owned = false
		_set_desktop_mode(false, false)
		return
	if _desktop_mode:
		_apply_desktop_profile.call_deferred()


func _on_app_stopped(app: RunningApp) -> void:
	if _auto_owned and _is_desktop_launcher(app):
		_auto_owned = false
		_set_desktop_mode(false, false)


func _on_all_apps_stopped() -> void:
	_auto_owned = false
	_set_desktop_mode(false, false)


func _is_desktop_launcher(app: RunningApp) -> bool:
	if not app or not app.launch_item:
		return false
	var item := app.launch_item
	if item.metadata.get("desktop_input", false):
		return true
	if not item.args.is_empty():
		return false
	var command := item.command.get_file().to_lower()
	return command in ["bottles", "heroic", "lutris"]


func _find_input_manager(node: Node) -> InputManager:
	if node is InputManager:
		return node as InputManager
	for child: Node in node.get_children():
		var found := _find_input_manager(child)
		if found:
			return found
	return null


func _install_quick_bar() -> void:
	if is_instance_valid(_quick_bar_panel):
		return
	var quick_bar := get_tree().get_first_node_in_group("quick-bar")
	if not quick_bar:
		get_tree().create_timer(0.5).timeout.connect(_install_quick_bar)
		return
	_quick_bar_panel = _build_menu(true)
	var icon := load("res://assets/icons/mouse-pointer.svg") as Texture2D
	if not QuickBarRegistration.add_menu(quick_bar, _quick_bar_panel, icon):
		logger.error("Quick Bar does not provide add_child_menu")
		_quick_bar_panel.queue_free()
		_quick_bar_panel = null
		return
	logger.info("Added Desktop Input controls to the quick bar")


func _build_menu(compact: bool) -> Control:
	var menu := VBoxContainer.new()
	menu.name = "WolfDesktopInputMenu"
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The Quick Bar receives an explicit title during registration. Procedural
	# nodes have no scene owner, and OGUI 0.45.1's legacy title discovery calls
	# null.get("text") when it cannot find an owned SectionLabel.
	if not compact:
		var section := Label.new()
		section.name = "SectionLabel"
		section.text = "Desktop Input"
		menu.add_child(section)

	var status := Label.new()
	menu.add_child(status)

	var toggle := Button.new()
	menu.add_child(toggle)
	toggle.pressed.connect(_on_toggle_pressed)

	var generic := CheckButton.new()
	generic.text = "Generic shortcut: Start + Select"
	generic.set_pressed_no_signal(_generic_shortcut)
	menu.add_child(generic)
	generic.toggled.connect(_on_generic_shortcut_toggled)

	var automatic := CheckButton.new()
	automatic.text = "Automatic for desktop launchers"
	automatic.set_pressed_no_signal(_auto_launchers)
	menu.add_child(automatic)
	automatic.toggled.connect(_on_auto_launchers_toggled)

	var speed_label: Label
	var speed: HSlider
	if not compact:
		speed_label = Label.new()
		menu.add_child(speed_label)
		speed = HSlider.new()
		speed.min_value = 300
		speed.max_value = 1600
		speed.step = 100
		speed.set_value_no_signal(_mouse_speed)
		menu.add_child(speed)
		speed.value_changed.connect(_on_mouse_speed_changed)

	var help := Label.new()
	help.text = "Start + Select + X toggles mouse mode"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(help)

	var focus_group := FocusGroup.new()
	menu.add_child(focus_group)
	_menus.append({
		"root": menu,
		"status": status,
		"toggle": toggle,
		"generic": generic,
		"automatic": automatic,
		"speed_label": speed_label,
		"speed": speed,
	})
	_refresh_menus()
	return menu


func _on_toggle_pressed() -> void:
	_auto_owned = false
	_set_desktop_mode(not _desktop_mode, true)


func _on_generic_shortcut_toggled(enabled: bool) -> void:
	_generic_shortcut = enabled
	settings_manager.set_value(SETTINGS_SECTION, "generic_shortcut", enabled)
	_configure_activation()
	_refresh_menus()


func _on_auto_launchers_toggled(enabled: bool) -> void:
	_auto_launchers = enabled
	settings_manager.set_value(SETTINGS_SECTION, "auto_launchers", enabled)
	if not enabled and _auto_owned:
		_auto_owned = false
		_set_desktop_mode(false, false)
	_refresh_menus()


func _on_mouse_speed_changed(value: float) -> void:
	_mouse_speed = int(value)
	settings_manager.set_value(SETTINGS_SECTION, "mouse_speed", _mouse_speed)
	_install_desktop_profile()
	if _desktop_mode:
		_apply_desktop_profile()
	_refresh_menus()


func _refresh_menus() -> void:
	var active_menus: Array[Dictionary] = []
	for controls: Dictionary in _menus:
		if not is_instance_valid(controls.get("root")):
			continue
		active_menus.append(controls)
		var status: Label = controls["status"]
		var toggle: Button = controls["toggle"]
		var generic: CheckButton = controls["generic"]
		var automatic: CheckButton = controls["automatic"]
		status.text = "Mode: " + ("Desktop Mouse" if _desktop_mode else "Gamepad")
		toggle.text = "Restore Gamepad" if _desktop_mode else "Enable Desktop Mouse"
		generic.set_pressed_no_signal(_generic_shortcut)
		automatic.set_pressed_no_signal(_auto_launchers)
		var speed_label = controls.get("speed_label")
		if is_instance_valid(speed_label):
			speed_label.text = "Pointer speed: " + str(_mouse_speed)
		var speed = controls.get("speed")
		if is_instance_valid(speed):
			speed.set_value_no_signal(_mouse_speed)
	_menus = active_menus
