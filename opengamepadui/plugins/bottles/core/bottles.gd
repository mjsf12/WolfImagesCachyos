extends Resource

var logger := Log.get_logger("Bottles", Log.LEVEL.INFO)


func get_gui_command() -> Command:
	var override := OS.get_environment("BOTTLES_BIN")
	if not override.is_empty():
		return Command.create(override, [])

	for candidate in ["/usr/sbin/bottles", "/usr/bin/bottles"]:
		if FileAccess.file_exists(candidate):
			logger.info("Detected Bottles at " + candidate)
			return Command.create(candidate, [])

	logger.warn("Bottles was not found at /usr/sbin/bottles or /usr/bin/bottles")
	return Command.create("bottles", [])


func get_cli_command() -> Command:
	var override := OS.get_environment("BOTTLES_CLI_BIN")
	if not override.is_empty():
		return Command.create(override, [])

	for candidate in ["/usr/sbin/bottles-cli", "/usr/bin/bottles-cli"]:
		if FileAccess.file_exists(candidate):
			logger.info("Detected bottles-cli at " + candidate)
			return Command.create(candidate, [])

	logger.warn(
		"bottles-cli was not found at /usr/sbin/bottles-cli or /usr/bin/bottles-cli"
	)
	return Command.create("bottles-cli", [])


func get_all_programs() -> Array[Dictionary]:
	var all_programs: Array[Dictionary] = []
	var seen: Dictionary = {}
	var bottle_names := await get_bottle_names()

	for bottle_name in bottle_names:
		var programs := await get_programs(bottle_name)
		for program in programs:
			var program_name := str(program.get("name", "")).strip_edges()
			if program_name.is_empty():
				continue

			var provider_app_id := bottle_name + "::" + program_name
			if provider_app_id in seen:
				continue
			seen[provider_app_id] = true

			var entry := program.duplicate(true)
			entry["bottle"] = bottle_name
			entry["name"] = program_name
			entry["provider_app_id"] = provider_app_id
			all_programs.append(entry)

	# OpenGamepadUI keeps one launch item per provider for a given display name.
	# Disambiguate only when the same program exists in more than one bottle.
	var name_counts: Dictionary = {}
	for program in all_programs:
		var program_name := str(program["name"])
		name_counts[program_name] = int(name_counts.get(program_name, 0)) + 1

	for program in all_programs:
		var program_name := str(program["name"])
		if int(name_counts[program_name]) > 1:
			program["display_name"] = "{0} ({1})".format(
				[program_name, program["bottle"]]
			)
		else:
			program["display_name"] = program_name

	all_programs.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["display_name"]).nocasecmp_to(str(b["display_name"])) < 0
	)
	return all_programs


func get_bottle_names() -> Array[String]:
	var names: Array[String] = []
	var parsed = await _execute_json(["--json", "list", "bottles"])
	if parsed is Dictionary:
		for value in parsed.keys():
			_append_unique_name(names, str(value))
	elif parsed is Array:
		for value in parsed:
			if value is String:
				_append_unique_name(names, value)
			elif value is Dictionary:
				for field in ["Name", "name", "Bottle", "bottle"]:
					if field in value:
						_append_unique_name(names, str(value[field]))
						break

	names.sort_custom(func(a: String, b: String) -> bool: return a.nocasecmp_to(b) < 0)
	logger.info("Found {0} bottles".format([names.size()]))
	return names


func get_programs(bottle_name: String) -> Array[Dictionary]:
	var programs: Array[Dictionary] = []
	var parsed = await _execute_json(
		["--json", "programs", "-b", bottle_name]
	)

	var values: Array = []
	if parsed is Array:
		values = parsed
	elif parsed is Dictionary and parsed.get("programs") is Array:
		values = parsed["programs"]
	elif parsed is Dictionary:
		for key in parsed:
			var value = parsed[key]
			if value is Dictionary:
				var entry: Dictionary = value.duplicate(true)
				if not "name" in entry:
					entry["name"] = str(key)
				values.append(entry)

	for value in values:
		if not value is Dictionary:
			continue
		# Bottles uses null for programs that have not been removed. Godot
		# cannot convert null with bool(), so only the literal true is removed.
		if value.get("removed", false) == true:
			continue
		if str(value.get("name", "")).strip_edges().is_empty():
			continue
		programs.append(value)

	logger.info(
		"Found {0} programs in bottle '{1}'".format([programs.size(), bottle_name])
	)
	return programs


func _append_unique_name(names: Array[String], value: String) -> void:
	var clean := value.strip_edges()
	if clean.is_empty() or clean in names:
		return
	names.append(clean)


func _execute_json(args: Array[String]) -> Variant:
	var base_cmd := get_cli_command()
	var command := Command.create(base_cmd.command, base_cmd.args.duplicate())
	command.args.append_array(args)
	await _exec_cmd(command)
	if command.code != OK:
		logger.warn(
			"bottles-cli exited with code {0}: {1}".format(
				[command.code, command.stderr]
			)
		)
		return null

	var parsed = _parse_json_output(command.stdout)
	if parsed == null:
		logger.warn("Unable to parse bottles-cli JSON output")
		logger.debug("bottles-cli stdout: " + command.stdout)
	return parsed


func _parse_json_output(output: String) -> Variant:
	var clean := output.strip_edges()
	var parsed = _try_parse_json(clean)
	if parsed != null:
		return parsed

	# Some package builds may print a startup message before the documented JSON.
	# Try opening tokens in their actual output order so an outer array is not
	# mistaken for one of the dictionaries it contains.
	var starts: Array[int] = []
	for index in range(clean.length()):
		var token := clean.substr(index, 1)
		if token == "{" or token == "[":
			starts.append(index)

	for start in starts:
		var opening := clean.substr(start, 1)
		var closing := "}" if opening == "{" else "]"
		var finish := clean.rfind(closing)
		while start >= 0 and finish > start:
			var candidate := clean.substr(start, finish - start + 1)
			parsed = _try_parse_json(candidate)
			if parsed != null:
				return parsed
			finish = clean.rfind(closing, finish - 1)
	return null


func _try_parse_json(value: String) -> Variant:
	var json := JSON.new()
	if json.parse(value) != OK:
		return null
	return json.data


func _exec_cmd(command: Command) -> void:
	logger.debug("Executing command: " + command.command + " " + " ".join(command.args))
	command.execute()
	await command.finished
	logger.debug("Command exit code: " + str(command.code))
	if not command.stderr.is_empty():
		logger.debug("Command stderr: " + command.stderr)
