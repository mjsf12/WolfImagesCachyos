extends Plugin

const OverlayPolicy := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_policy.gd"
)
const OverlayReconciler := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_reconciler.gd"
)
const OverlayTransition := preload(
	"res://plugins/wolf-gamescope-session/core/overlay_transition.gd"
)
const WINDOW_DISCOVERY_ATTEMPTS := 10

var gamescope := load("res://core/systems/gamescope/gamescope.tres") as GamescopeInstance
var launch_manager := load("res://core/global/launch_manager.tres") as LaunchManager
var state_machine := load(
	"res://assets/state/state_machines/global_state_machine.tres"
) as StateMachine
var in_game_state := load("res://assets/state/states/in_game.tres") as State

var _xwayland_primary
var _xwayland_ogui
var _overlay_window_id := 0
var _transition := OverlayTransition.new()
var _original_should_manage_overlay := true
var _owns_overlay := false
var _unloading := false


func _ready() -> void:
	logger = Log.get_logger("WolfGamescopeSession", Log.LEVEL.INFO)
	_xwayland_primary = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_PRIMARY)
	_xwayland_ogui = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_OGUI)
	_original_should_manage_overlay = launch_manager.should_manage_overlay
	_owns_overlay = _original_should_manage_overlay
	if not _owns_overlay:
		logger.info("Native overlay management was already disabled; leaving ownership unchanged")
		return

	# The stock LaunchManager callback writes STEAM_OVERLAY=1 on both enter and
	# exit. Disable only that public policy switch and reproduce the corrected
	# lifecycle through public state signals.
	launch_manager.should_manage_overlay = false
	_connect_runtime_signals()
	_request_reconcile(
		state_machine.has_state(in_game_state),
		false,
		"startup",
	)
	logger.info("Loaded and assumed Gamescope overlay lifecycle ownership")


func unload() -> void:
	_unloading = true
	_disconnect_runtime_signals()
	if _owns_overlay:
		# Leave Gamescope in the state the native LaunchManager expects before it
		# resumes ownership. Idle cleanup also removes stale game AppIDs.
		var game_present := state_machine.has_state(in_game_state)
		var decision := OverlayPolicy.decision(
			game_present,
			not game_present,
			gamescope.EXTRA_UNKNOWN_GAME_ID,
			gamescope.OVERLAY_GAME_ID,
		)
		OverlayReconciler.apply(
			_xwayland_primary,
			_xwayland_ogui,
			_discover_overlay_window(),
			decision,
		)
		launch_manager.should_manage_overlay = _original_should_manage_overlay
	logger.info("Unloaded and returned overlay lifecycle ownership")


func _connect_runtime_signals() -> void:
	if not in_game_state.state_entered.is_connected(_on_in_game_entered):
		in_game_state.state_entered.connect(_on_in_game_entered)
	if not in_game_state.state_exited.is_connected(_on_in_game_exited):
		in_game_state.state_exited.connect(_on_in_game_exited)
	if not launch_manager.all_apps_stopped.is_connected(_on_all_apps_stopped):
		launch_manager.all_apps_stopped.connect(_on_all_apps_stopped)


func _disconnect_runtime_signals() -> void:
	if in_game_state.state_entered.is_connected(_on_in_game_entered):
		in_game_state.state_entered.disconnect(_on_in_game_entered)
	if in_game_state.state_exited.is_connected(_on_in_game_exited):
		in_game_state.state_exited.disconnect(_on_in_game_exited)
	if launch_manager.all_apps_stopped.is_connected(_on_all_apps_stopped):
		launch_manager.all_apps_stopped.disconnect(_on_all_apps_stopped)


func _on_in_game_entered(_from: State) -> void:
	_request_reconcile(true, false, "in_game_entered")


func _on_in_game_exited(_to: State) -> void:
	# State.state_exited fires when an in-game menu is pushed even though the
	# in-game state remains lower in the stack. Query the complete stack just as
	# the former overlay-menu patch did.
	_request_reconcile(
		state_machine.has_state(in_game_state),
		false,
		"in_game_exited",
	)


func _on_all_apps_stopped() -> void:
	# LaunchManager emits this after removing both in-game states. This final
	# request must supersede the state_exited callback queued moments earlier.
	_request_reconcile(false, true, "all_apps_stopped")


func _request_reconcile(
		game_present: bool,
		final_cleanup: bool,
		reason: String,
	) -> void:
	if _unloading or not _owns_overlay:
		return
	var decision := OverlayPolicy.decision(
		game_present,
		final_cleanup,
		gamescope.EXTRA_UNKNOWN_GAME_ID,
		gamescope.OVERLAY_GAME_ID,
	)
	var token := _transition.request(decision, reason)
	# Match the former patches synchronously whenever the window is already
	# known. The coroutine yields only during startup window discovery.
	_apply_reconcile(token, 0)


func _apply_reconcile(token: int, attempt: int) -> void:
	if _unloading or not _transition.is_current(token):
		return
	_refresh_xwaylands()
	var window_id := _discover_overlay_window()
	if window_id <= 0 and attempt < WINDOW_DISCOVERY_ATTEMPTS:
		await get_tree().process_frame
		_apply_reconcile(token, attempt + 1)
		return

	var decision := _transition.current_decision(token)
	if decision.is_empty():
		return
	var result := OverlayReconciler.apply(
		_xwayland_primary,
		_xwayland_ogui,
		window_id,
		decision,
	)
	if not result.get("overlay_applied", false):
		logger.error(
			"Unable to set STEAM_OVERLAY for transition "
			+ _transition.reason
			+ " (window="
			+ str(window_id)
			+ ")"
		)
		return
	_transition.commit(token)
	logger.info(
		"Overlay reconciled: "
		+ _transition.reason
		+ " overlay="
		+ str(decision["overlay_value"])
		+ " idle_cleanup="
		+ str(decision["reset_baselayer"])
	)


func _discover_overlay_window() -> int:
	if not _xwayland_ogui:
		return 0
	var windows: PackedInt64Array = _xwayland_ogui.get_windows_for_pid(
		OS.get_process_id()
	)
	if not windows.is_empty():
		_overlay_window_id = int(windows[0])
	return _overlay_window_id


func _refresh_xwaylands() -> void:
	if not _xwayland_primary:
		_xwayland_primary = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_PRIMARY)
	if not _xwayland_ogui:
		_xwayland_ogui = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_OGUI)
