extends Resource

const DEFAULT_HEROIC_CONFIG := "heroic"
const EXTRACTED_HELPER := "user://plugins/heroic/plugins/heroic/scripts/heroic-list.py"
const SOURCE_HELPER := "res://plugins/heroic/scripts/heroic-list.py"

var logger := Log.get_logger("Heroic", Log.LEVEL.INFO)


func get_heroic_command() -> Command:
	var override := OS.get_environment("HEROIC_BIN")
	if not override.is_empty():
		return Command.create(override, [])

	for candidate in ["/usr/sbin/heroic", "/usr/bin/heroic"]:
		if FileAccess.file_exists(candidate):
			logger.info("Detected Heroic at " + candidate)
			return Command.create(candidate, [])

	logger.warn("Heroic binary was not found at /usr/sbin/heroic or /usr/bin/heroic")
	return Command.create("heroic", [])


func get_games() -> Array[Dictionary]:
	var games: Array[Dictionary] = []
	var helper := _get_helper_path()
	if helper.is_empty():
		logger.warn("Unable to locate heroic-list.py")
		return games

	var python := _get_python_command()
	var config_dir := _get_config_dir()
	var command := Command.create(python, [helper, "--json", config_dir])
	await _exec_cmd(command)
	if command.code != OK:
		logger.warn(
			"Unable to list Heroic games. Exited with code {0}: {1}".format(
				[command.code, command.stderr]
			)
		)
		return games

	var parsed = JSON.parse_string(command.stdout)
	if not parsed is Array:
		logger.warn("Unable to parse Heroic games output as a JSON array")
		logger.debug("Heroic helper output: " + command.stdout)
		return games

	for value in parsed:
		if value is Dictionary:
			games.append(value)
	return games


func _get_config_dir() -> String:
	var override := OS.get_environment("HEROIC_CONFIG_DIR")
	if not override.is_empty():
		return override

	var xdg_config := OS.get_environment("XDG_CONFIG_HOME")
	if not xdg_config.is_empty():
		return xdg_config.path_join(DEFAULT_HEROIC_CONFIG)

	var home := OS.get_environment("HOME")
	return home.path_join(".config").path_join(DEFAULT_HEROIC_CONFIG)


func _get_helper_path() -> String:
	var extracted := ProjectSettings.globalize_path(EXTRACTED_HELPER)
	if FileAccess.file_exists(extracted):
		return extracted

	var source := ProjectSettings.globalize_path(SOURCE_HELPER)
	if FileAccess.file_exists(source):
		return source
	return ""


func _get_python_command() -> String:
	for candidate in ["/usr/bin/python3", "/usr/bin/python"]:
		if FileAccess.file_exists(candidate):
			return candidate
	return "python3"


func _exec_cmd(command: Command) -> void:
	logger.debug("Executing command: " + command.command + " " + " ".join(command.args))
	command.execute()
	await command.finished
	logger.debug("Command exit code: " + str(command.code))
	if not command.stderr.is_empty():
		logger.debug("Command stderr: " + command.stderr)

