extends Library

const Bottles := preload("res://plugins/bottles/core/bottles.gd")

var bottles := Bottles.new()


func get_library_launch_items() -> Array[LibraryLaunchItem]:
	logger.info("Fetching Bottles library items")
	var items: Array[LibraryLaunchItem] = []

	# Keep the Bottles GUI available even when there are no configured programs.
	var gui_cmd := bottles.get_gui_command()
	var launcher := LibraryLaunchItem.new()
	launcher.name = "Bottles"
	launcher.provider_app_id = "launcher"
	launcher.command = gui_cmd.command
	launcher.args = gui_cmd.args.duplicate()
	launcher.tags = ["bottles", "launcher"]
	launcher.categories = ["Launchers"]
	launcher.installed = true
	launcher.hidden = false
	items.append(launcher)

	var cli_cmd := bottles.get_cli_command()
	var programs := await bottles.get_all_programs()
	for program in programs:
		var bottle_name := str(program.get("bottle", ""))
		var program_name := str(program.get("name", ""))
		var display_name := str(program.get("display_name", program_name))
		var provider_app_id := str(program.get("provider_app_id", ""))
		if bottle_name.is_empty() or program_name.is_empty() or provider_app_id.is_empty():
			continue

		var item_args := cli_cmd.args.duplicate()
		item_args.append_array(["run", "-b", bottle_name, "-p", program_name])

		var item := LibraryLaunchItem.new()
		item.name = display_name
		item.provider_app_id = provider_app_id
		item.command = cli_cmd.command
		item.args = item_args
		item.tags = ["bottles", bottle_name]
		item.categories = ["Games", "Bottles"]
		item.installed = true
		item.hidden = false
		item.metadata = {
			"bottle": bottle_name,
			"program": program_name,
			"path": str(program.get("path", "")),
			"executable": str(program.get("executable", "")),
			"arguments": str(program.get("arguments", "")),
		}
		items.append(item)

	logger.info(
		"Found {0} Bottles programs plus the launcher".format([items.size() - 1])
	)
	return items
