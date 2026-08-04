extends Plugin

const ShortcutState := preload("res://plugins/wolf-desktop-input/core/shortcut_state.gd")
const InterceptPolicy := preload("res://plugins/wolf-desktop-input/core/intercept_policy.gd")
const InterceptReconciler := preload(
	"res://plugins/wolf-desktop-input/core/intercept_reconciler.gd"
)
const ProfileReconciler := preload(
	"res://plugins/wolf-desktop-input/core/profile_reconciler.gd"
)
const ProfileTransition := preload(
	"res://plugins/wolf-desktop-input/core/profile_transition.gd"
)
const DesktopModePolicy := preload(
	"res://plugins/wolf-desktop-input/core/desktop_mode_policy.gd"
)
const QuickBarRegistration := preload(
	"res://plugins/wolf-desktop-input/core/quick_bar_registration.gd"
)
const SETTINGS_SECTION := "plugin.wolf-desktop-input"
const SOURCE_PROFILE := "profiles/desktop_mouse.json"
const USER_PROFILE_DIR := "user://data/gamepad/profiles"
const USER_PROFILE := USER_PROFILE_DIR + "/wolf_desktop_mouse.json"
const DESKTOP_PROFILE_NAME := "Wolf Desktop Mouse"
const DEFAULT_GAMEPAD_PROFILE := USER_PROFILE_DIR + "/global_default.json"
const DEFAULT_TARGET_GAMEPAD := "xbox-series"
const GUIDE_ACTION := "ogui_guide_action"
const PROFILE_MAX_ATTEMPTS := 4
const PROFILE_STABLE_FRAMES := 2

var input_plumber := load("res://core/systems/input/input_plumber.tres") as InputPlumberInstance
var launch_manager := load("res://core/global/launch_manager.tres") as LaunchManager
var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager
var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
var popup_state_machine := load("res://assets/state/state_machines/popup_state_machine.tres") as StateMachine
var global_state_machine := load("res://assets/state/state_machines/global_state_machine.tres") as StateMachine
var in_game_state := load("res://assets/state/states/in_game.tres") as State

var _shortcut_state := ShortcutState.new()
var _profile_transition := ProfileTransition.new()
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
var _composite_devices := {}
var _last_intercept_mode := -1
var _trace_seq := 0
var _unloading := false


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
	_trace("plugin_ready", {
		"generic_shortcut": _generic_shortcut,
		"auto_launchers": _auto_launchers,
		"mouse_speed": _mouse_speed,
	})

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
	_set_desktop_mode(false, false, "startup")
	_install_quick_bar.call_deferred()
	logger.info("Loaded; generic shortcut: " + str(_generic_shortcut))


func unload() -> void:
	_unloading = true
	var token := _profile_transition.request(false, false, "plugin_unload")
	_sync_intercept_mode("plugin_unload:guard")
	var result := _restore_gamepad_profile("plugin_unload")
	if _profile_result_confirmed(result) and _profile_transition.commit(token):
		_desktop_mode = false
	_sync_intercept_mode("plugin_unload:committed")
	_apply_standard_guide_activation()
	_disconnect_runtime_signals()
	for target_path: String in _watched_targets.keys():
		_disconnect_target(target_path)
	if is_instance_valid(_quick_bar_panel):
		_quick_bar_panel.queue_free()
	logger.info("Unloaded and restored gamepad input")


func get_settings_menu() -> Control:
	return _build_menu(false)


func _trace(event: String, fields: Dictionary = {}) -> void:
	_trace_seq += 1
	var payload := {
		"seq": _trace_seq,
		"ticks_ms": Time.get_ticks_msec(),
		"event": event,
		"desktop_mode": _desktop_mode,
		"desktop_desired": _profile_transition.desired_desktop_mode,
		"profile_generation": _profile_transition.generation,
		"auto_owned": _auto_owned,
		"in_game": global_state_machine.has_state(in_game_state),
		"popup": _state_name(popup_state_machine.current_state()),
	}
	for key in fields:
		payload[key] = fields[key]
	logger.info("[trace] " + JSON.stringify(payload))


func _trace_devices(
		event: String,
		reason: String,
		fields: Dictionary = {},
	) -> void:
	var details := fields.duplicate(true)
	details["reason"] = reason
	var snapshots: Array[Dictionary] = []
	var devices := InterceptReconciler.collect_devices(
		input_plumber.get_composite_devices(),
		_composite_devices,
	)
	for device in devices:
		snapshots.append(_device_snapshot(device))
	details["devices"] = snapshots
	_trace(event, details)


func _device_snapshot(device) -> Dictionary:
	if not is_instance_valid(device):
		return {"valid": false}
	var targets: Array[String] = []
	for target in device.get_target_devices():
		if target is Dictionary:
			targets.append(
				str(target.get("device_type", ""))
				+ "@"
				+ str(target.get("dbus_path", ""))
			)
	return {
		"valid": true,
		"dbus_path": str(device.dbus_path),
		"name": str(device.name),
		"profile_name": str(device.profile_name),
		"intercept_mode": int(device.intercept_mode),
		"targets": targets,
	}


func _state_name(state: State) -> String:
	if not state:
		return ""
	if not state.resource_path.is_empty():
		return state.resource_path.get_file()
	return str(state)


func _app_name(app: RunningApp) -> String:
	if not app:
		return ""
	if app.launch_item:
		return app.launch_item.name
	return "appid:" + str(app.app_id)


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
	if not global_state_machine.state_changed.is_connected(_on_global_state_changed):
		global_state_machine.state_changed.connect(_on_global_state_changed)


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
	if global_state_machine.state_changed.is_connected(_on_global_state_changed):
		global_state_machine.state_changed.disconnect(_on_global_state_changed)


func _initialize_inputplumber() -> void:
	for device: CompositeDevice in input_plumber.get_composite_devices():
		_on_device_added(device)
	_configure_activation()


func _on_device_added(device: CompositeDevice) -> void:
	_composite_devices[device.dbus_path as String] = device
	_trace("device_added", {"device": _device_snapshot(device)})
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
	# Reapply the current route through the object delivered by the signal. The
	# InputPlumberInstance cache can lag behind this callback on OGUI 0.46.
	_sync_intercept_mode.bind("device_added").call_deferred()
	_queue_profile_reconcile.bind("device_added").call_deferred()


func _on_device_removed(device_path: String) -> void:
	_trace("device_removed", {"device_path": device_path})
	_composite_devices.erase(device_path)
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
	var toggled := _shortcut_state.handle_event(device_path, event, value)
	_trace("dbus_input", {
		"device_path": device_path,
		"input_event": event,
		"value": value,
		"shortcut_toggled": toggled,
	})
	if not toggled:
		return

	# Tell the official InputManager that this Guide chord performed an action.
	# Otherwise releasing Start+Select would also open the main menu.
	if is_instance_valid(_input_manager):
		_input_manager.action_press(device_path, GUIDE_ACTION)
	else:
		logger.warn("InputManager was not found; Guide release may also open the menu")

	_auto_owned = false
	# This signal is emitted while InputPlumberInstance is borrowed by its
	# GDExtension callback. Loading a profile synchronously from here attempts a
	# second borrow and Godot rejects it as "already bound". Leave the callback
	# first, then perform the profile switch on the main loop.
	var enabled := not _profile_transition.desired_desktop_mode
	_trace("shortcut_toggle_queued", {"requested_enabled": enabled})
	_set_desktop_mode.bind(enabled, true, "shortcut").call_deferred()


func _set_desktop_mode(
		enabled: bool,
		show_notification: bool = true,
		reason: String = "unspecified",
	) -> void:
	var token := _profile_transition.request(enabled, show_notification, reason)
	_trace_devices("desktop_mode_requested", reason, {
		"requested_enabled": enabled,
		"show_notification": show_notification,
		"token": token,
	})
	# Entering desktop mode blocks gamepad delivery immediately. Leaving keeps
	# that guard until the gamepad profile is confirmed by InputPlumber.
	_sync_intercept_mode(reason + ":guard")
	_refresh_menus()
	_run_profile_transition.bind(token, 0).call_deferred()


func _queue_profile_reconcile(reason: String) -> void:
	if _unloading:
		return
	var token := _profile_transition.refresh(reason)
	# Opening an OpenGamepadUI popup intentionally installs its navigation
	# profile. Invalidate older desktop verification, but wait until the popup
	# closes before restoring desktop mappings.
	if (
		_profile_transition.desired_desktop_mode
		and popup_state_machine.current_state() != null
	):
		_trace("profile_reconcile_postponed", {
			"reason": reason,
			"token": token,
			"popup": _state_name(popup_state_machine.current_state()),
		})
		_sync_intercept_mode(reason + ":popup_guard")
		return
	_trace("profile_reconcile_queued", {
		"reason": reason,
		"token": token,
		"requested_enabled": _profile_transition.desired_desktop_mode,
	})
	_sync_intercept_mode(reason + ":guard")
	_run_profile_transition.bind(token, 0).call_deferred()


func _run_profile_transition(token: int, attempt: int) -> void:
	if _unloading or not _profile_transition.is_current(token):
		_trace("profile_transition_stale", {"token": token, "attempt": attempt})
		return

	var reason := _profile_transition.reason
	var requested_enabled := _profile_transition.desired_desktop_mode
	_trace_devices("profile_transition_apply", reason, {
		"token": token,
		"attempt": attempt,
		"requested_enabled": requested_enabled,
	})
	_sync_intercept_mode(reason + ":apply_guard")
	var result: Dictionary
	if requested_enabled:
		result = _apply_desktop_profile(reason)
	else:
		result = _restore_gamepad_profile(reason)

	if not _profile_transition.is_current(token):
		_trace("profile_transition_superseded_after_apply", {
			"token": token,
			"attempt": attempt,
		})
		return

	get_tree().process_frame.connect(
		_verify_profile_transition.bind(token, attempt, 0, result),
		CONNECT_ONE_SHOT,
	)


func _verify_profile_transition(
		token: int,
		attempt: int,
		stable_frames: int,
		result: Dictionary,
	) -> void:
	if _unloading or not _profile_transition.is_current(token):
		_trace("profile_verification_stale", {
			"token": token,
			"attempt": attempt,
			"stable_frames": stable_frames,
		})
		return

	var expected_name := str(result.get("expected_profile", ""))
	var devices := InterceptReconciler.collect_devices(
		input_plumber.get_composite_devices(),
		_composite_devices,
	)
	var confirmed := ProfileReconciler.count_profile(devices, expected_name)
	var expected_count := devices.size()
	var profile_matches := (
		not expected_name.is_empty()
		and expected_count > 0
		and confirmed == expected_count
	)
	_trace_devices("profile_transition_verify", _profile_transition.reason, {
		"token": token,
		"attempt": attempt,
		"stable_frames": stable_frames,
		"expected_profile": expected_name,
		"confirmed": confirmed,
		"expected_count": expected_count,
		"profile_matches": profile_matches,
	})

	if profile_matches and stable_frames + 1 < PROFILE_STABLE_FRAMES:
		get_tree().process_frame.connect(
			_verify_profile_transition.bind(
				token,
				attempt,
				stable_frames + 1,
				result,
			),
			CONNECT_ONE_SHOT,
		)
		return

	if profile_matches:
		_commit_profile_transition(token, result)
		return

	if attempt + 1 < PROFILE_MAX_ATTEMPTS:
		_trace("profile_transition_retry", {
			"token": token,
			"next_attempt": attempt + 1,
			"expected_profile": expected_name,
		})
		_run_profile_transition.bind(token, attempt + 1).call_deferred()
		return

	_fail_profile_transition(token, result)


func _commit_profile_transition(token: int, result: Dictionary) -> void:
	if not _profile_transition.is_current(token):
		return
	var previous_mode := _desktop_mode
	var show_notification := _profile_transition.show_notification
	var reason := _profile_transition.reason
	if not _profile_transition.commit(token):
		return
	_desktop_mode = _profile_transition.applied_desktop_mode
	_refresh_menus()

	if show_notification and previous_mode != _desktop_mode:
		var text := "Desktop mouse enabled"
		if not _desktop_mode:
			text = "Gamepad profile restored"
		notification_manager.show(Notification.new(text))
	logger.info("Desktop mode: " + str(_desktop_mode))
	_trace_devices("desktop_mode_committed", reason, {
		"token": token,
		"enabled": _desktop_mode,
		"expected_profile": result.get("expected_profile", ""),
	})
	_sync_intercept_mode(reason + ":committed")


func _fail_profile_transition(token: int, result: Dictionary) -> void:
	if not _profile_transition.is_current(token):
		return
	var requested_enabled := _profile_transition.desired_desktop_mode
	var show_notification := _profile_transition.show_notification
	var reason := _profile_transition.reason
	if not _profile_transition.reject(token):
		return
	_desktop_mode = _profile_transition.applied_desktop_mode
	_refresh_menus()
	_sync_intercept_mode(reason + ":rejected")
	logger.error(
		"Profile transition failed after "
		+ str(PROFILE_MAX_ATTEMPTS)
		+ " attempts; expected "
		+ str(result.get("expected_profile", "")),
	)
	_trace_devices("profile_transition_failed", reason, {
		"token": token,
		"requested_enabled": requested_enabled,
		"expected_profile": result.get("expected_profile", ""),
	})
	if show_notification:
		var text := "Desktop mouse failed to load"
		if not requested_enabled:
			text = "Gamepad profile failed to restore"
		notification_manager.show(Notification.new(text))


func _profile_result_confirmed(result: Dictionary) -> bool:
	var expected := int(result.get("expected_count", 0))
	return expected > 0 and int(result.get("confirmed", 0)) == expected


func _apply_desktop_profile(reason: String = "unspecified") -> Dictionary:
	_trace_devices("desktop_profile_apply_before", reason)
	var devices := InterceptReconciler.collect_devices(
		input_plumber.get_composite_devices(),
		_composite_devices,
	)
	if not FileAccess.file_exists(USER_PROFILE):
		_install_desktop_profile()
	if not FileAccess.file_exists(USER_PROFILE):
		logger.error("Desktop profile is unavailable: " + USER_PROFILE)
		return {
			"profile_path": USER_PROFILE,
			"target_gamepad": DEFAULT_TARGET_GAMEPAD,
			"expected_profile": DESKTOP_PROFILE_NAME,
			"confirmed": 0,
			"expected_count": devices.size(),
		}
	launch_manager.set_gamepad_profile(USER_PROFILE)
	var confirmed := ProfileReconciler.apply_profile(
		devices,
		USER_PROFILE,
		DESKTOP_PROFILE_NAME,
	)
	if confirmed == 0:
		logger.error(
			"InputPlumber did not confirm the desktop profile; "
			+ "check profile serialization and D-Bus authorization"
		)
		_trace_devices("desktop_profile_apply_rejected", reason)
	else:
		logger.info("Desktop profile confirmed on " + str(confirmed) + " composite(s)")
		_trace_devices(
			"desktop_profile_apply_confirmed",
			reason,
			{"confirmed": confirmed},
		)
	return {
		"profile_path": USER_PROFILE,
		"target_gamepad": DEFAULT_TARGET_GAMEPAD,
		"expected_profile": DESKTOP_PROFILE_NAME,
		"confirmed": confirmed,
		"expected_count": devices.size(),
	}


func _restore_gamepad_profile(reason: String = "unspecified") -> Dictionary:
	var current_app := launch_manager.get_current_app()
	_trace_devices("gamepad_profile_restore_before", reason, {
		"current_app": _app_name(current_app),
	})
	if current_app:
		launch_manager.set_app_gamepad_profile(current_app)
	else:
		launch_manager.set_gamepad_profile("")

	# O OpenGamepadUI 0.46 pode retornar da API acima sem carregar nada quando
	# get_target_devices() não consegue resolver o tipo do alvo já existente.
	# Não aceite essa restauração silenciosa: resolva a seleção oficial e force
	# o mesmo caminho diretamente no CompositeDevice se o perfil não mudou.
	var selection := _resolve_gamepad_profile()
	var profile_path := selection["path"] as String
	var target_gamepad := selection["target"] as String
	var expected_name := ProfileReconciler.profile_name_from_path(profile_path)
	var devices := InterceptReconciler.collect_devices(
		input_plumber.get_composite_devices(),
		_composite_devices,
	)
	var confirmed := ProfileReconciler.count_profile(devices, expected_name)
	if expected_name.is_empty():
		logger.error("Unable to resolve the gamepad profile: " + profile_path)
	elif confirmed < devices.size():
		logger.warn(
			"Official gamepad restore was not confirmed; applying "
			+ profile_path
			+ " directly",
		)
		for device in devices:
			if not is_instance_valid(device):
				continue
			InputPlumber.load_target_modified_profile(
				device,
				profile_path,
				target_gamepad,
			)
		confirmed = ProfileReconciler.count_profile(devices, expected_name)
	if confirmed < devices.size():
		logger.error(
			"InputPlumber did not confirm gamepad profile restore; expected "
			+ expected_name
			+ " on "
			+ str(devices.size())
			+ " composite(s), confirmed "
			+ str(confirmed),
		)
	_trace_devices("gamepad_profile_restore_after", reason, {
		"profile_path": profile_path,
		"target_gamepad": target_gamepad,
		"expected_profile": expected_name,
		"confirmed": confirmed,
	})
	return {
		"profile_path": profile_path,
		"target_gamepad": target_gamepad,
		"expected_profile": expected_name,
		"confirmed": confirmed,
		"expected_count": devices.size(),
	}


func _resolve_gamepad_profile() -> Dictionary:
	var profile_path := ""
	var target_gamepad := ""
	var item := launch_manager.get_current_app_library_item()
	if item:
		profile_path = str(
			settings_manager.get_library_value(item, "gamepad_profile", ""),
		)
		target_gamepad = str(
			settings_manager.get_library_value(
				item,
				"gamepad_profile_target",
				"",
			),
		)
	if profile_path.is_empty():
		var default_path := DEFAULT_GAMEPAD_PROFILE
		if is_instance_valid(_input_manager):
			default_path = _input_manager.get_default_global_profile_path()
		profile_path = str(
			settings_manager.get_value("input", "gamepad_profile", default_path),
		)
	if not FileAccess.file_exists(profile_path):
		logger.warn(
			"Configured gamepad profile is unavailable; using global default: "
			+ profile_path,
		)
		profile_path = DEFAULT_GAMEPAD_PROFILE
	if target_gamepad.is_empty():
		target_gamepad = str(
			settings_manager.get_value(
				"input",
				"gamepad_profile_target",
				DEFAULT_TARGET_GAMEPAD,
			),
		)
	if target_gamepad.is_empty():
		target_gamepad = DEFAULT_TARGET_GAMEPAD
	return {
		"path": profile_path,
		"target": target_gamepad,
	}


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
	destination.store_string(ProfileReconciler.serialize(profile))
	logger.info("Installed desktop profile with speed " + str(_mouse_speed))


func _on_popup_state_changed(_from: State, to: State) -> void:
	_trace("popup_state_changed", {"to": _state_name(to)})
	# The generic Guide chord enters interception before the popup transition.
	# Reconcile after every popup change so closing an overlay returns events to
	# the appropriate InputPlumber target without exposing the physical source.
	_sync_intercept_mode.bind("popup_state_changed").call_deferred()
	# InputManager loads the global profile while a Guide menu is open. Any
	# pending desktop transaction is invalidated while it is open, then the
	# latest intention is reconciled only after the popup closes.
	if to != null:
		var token := _profile_transition.refresh("popup_open")
		_trace("profile_transition_suspended", {"token": token})
		return
	_queue_profile_reconcile.bind("popup_closed").call_deferred()


func _on_global_state_changed(from: State, to: State) -> void:
	_trace("global_state_changed", {
		"from": _state_name(from),
		"to": _state_name(to),
	})
	_sync_intercept_mode.bind("global_state_changed").call_deferred()
	if _profile_transition.desired_desktop_mode:
		_queue_profile_reconcile.bind("global_state_changed").call_deferred()


func _sync_intercept_mode(reason: String = "unspecified") -> void:
	var guarded_desktop_mode := _profile_transition.route_requires_desktop_guard()
	var foreground_state := global_state_machine.current_state()
	var game_running := global_state_machine.has_state(in_game_state)
	var game_in_foreground := foreground_state == in_game_state
	var mode := InterceptPolicy.desired_mode(
		game_running,
		game_in_foreground,
		popup_state_machine.current_state() != null,
		guarded_desktop_mode,
	)
	# Always write every live composite. OpenGamepadUI 0.46 can update the local
	# wrapper cache while the real D-Bus device remains in the previous mode.
	var devices := InterceptReconciler.collect_devices(
		input_plumber.get_composite_devices(),
		_composite_devices,
	)
	_trace_devices("intercept_sync_before", reason, {
		"desired_mode": mode,
		"desktop_guard": guarded_desktop_mode,
		"foreground_state": _state_name(foreground_state),
		"game_running": game_running,
		"game_in_foreground": game_in_foreground,
	})
	var writes := InterceptReconciler.apply_mode(
		input_plumber,
		devices,
		mode,
	)
	_trace_devices("intercept_sync_after", reason, {
		"desired_mode": mode,
		"confirmed_writes": writes,
	})
	if writes == 0:
		logger.warn(
			"InputPlumber did not confirm the route on any live composite; "
			+ "check D-Bus authorization and device discovery"
		)
	if mode == _last_intercept_mode:
		return
	_last_intercept_mode = mode
	var route_name := "OpenGamepadUI"
	if mode == InterceptPolicy.INTERCEPT_MODE_PASS:
		route_name = "gamepad target"
	elif mode == InterceptPolicy.INTERCEPT_MODE_GAMEPAD_ONLY:
		route_name = "desktop mouse target"
	logger.info(
		"Input route: "
		+ route_name
		+ " (devices: "
		+ str(writes)
		+ ")"
	)


func _on_app_launched(app: RunningApp) -> void:
	_trace("app_launched", {"app": _app_name(app)})
	_sync_intercept_mode.bind("app_launched").call_deferred()
	var desktop_launcher := _is_desktop_launcher(app)
	if DesktopModePolicy.should_restore_for_app(
		_profile_transition.desired_desktop_mode,
		desktop_launcher,
	):
		_auto_owned = false
		_set_desktop_mode(false, false, "game_launched")
		return
	if _auto_launchers and desktop_launcher:
		_auto_owned = true
		_set_desktop_mode(true, true, "desktop_launcher_launched")
		return
	if _profile_transition.desired_desktop_mode:
		_queue_profile_reconcile.bind("app_launched").call_deferred()


func _on_app_switched(from: RunningApp, to: RunningApp) -> void:
	_trace("app_switched", {
		"from": _app_name(from),
		"to": _app_name(to),
	})
	# LaunchManager applies the selected game profile after app_switched. Reassert
	# the route on the next frame so late profile work cannot retain frontend
	# interception.
	_sync_intercept_mode.bind("app_switched").call_deferred()
	# Gamescope can report a focus transition between two windows owned by the
	# same launcher/game. LaunchManager emits app_switched even though the user
	# never left the app; do not tear down desktop mode in that no-op transition.
	if DesktopModePolicy.is_same_app_name(_app_name(from), _app_name(to)):
		_trace("app_switch_same_ignored", {"app": _app_name(to)})
		if _profile_transition.desired_desktop_mode:
			_queue_profile_reconcile.bind("same_app_switched").call_deferred()
		return
	var desktop_launcher := _is_desktop_launcher(to)
	if DesktopModePolicy.should_restore_for_app(
		_profile_transition.desired_desktop_mode,
		desktop_launcher,
	):
		_auto_owned = false
		_set_desktop_mode(false, false, "game_switched")
		return
	if _auto_launchers and desktop_launcher:
		_auto_owned = true
		_set_desktop_mode(true, false, "desktop_launcher_switched")
		return
	if _auto_owned:
		_auto_owned = false
		_set_desktop_mode(false, false, "auto_launcher_left")
		return
	if _profile_transition.desired_desktop_mode:
		_queue_profile_reconcile.bind("app_switched").call_deferred()


func _on_app_stopped(app: RunningApp) -> void:
	_trace("app_stopped", {"app": _app_name(app)})
	_sync_intercept_mode.bind("app_stopped").call_deferred()
	if _auto_owned and _is_desktop_launcher(app):
		_auto_owned = false
		_set_desktop_mode(false, false, "desktop_launcher_stopped")
		return
	if _profile_transition.desired_desktop_mode:
		_queue_profile_reconcile.bind("app_stopped").call_deferred()


func _on_all_apps_stopped() -> void:
	_trace("all_apps_stopped")
	_auto_owned = false
	_set_desktop_mode(false, false, "all_apps_stopped")


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
	# nodes have no scene owner, and OGUI 0.46.0's legacy title discovery calls
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
	_set_desktop_mode(
		not _profile_transition.desired_desktop_mode,
		true,
		"quick_bar",
	)


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
		_set_desktop_mode(false, false, "automatic_launchers_disabled")
	_refresh_menus()


func _on_mouse_speed_changed(value: float) -> void:
	_mouse_speed = int(value)
	settings_manager.set_value(SETTINGS_SECTION, "mouse_speed", _mouse_speed)
	_install_desktop_profile()
	if _profile_transition.desired_desktop_mode:
		_queue_profile_reconcile("mouse_speed_changed")
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
