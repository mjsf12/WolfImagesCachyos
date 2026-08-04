extends Library

const Heroic := preload("res://plugins/heroic/core/heroic.gd")

var heroic := Heroic.new()


func get_library_launch_items() -> Array[LibraryLaunchItem]:
	logger.info("Fetching Heroic library items")
	var items: Array[LibraryLaunchItem] = []
	var heroic_cmd := heroic.get_heroic_command()

	# Keep the launcher itself in the library even when no games are installed.
	var launcher := LibraryLaunchItem.new()
	launcher.name = "Heroic Games Launcher"
	launcher.provider_app_id = "launcher"
	launcher.command = heroic_cmd.command
	launcher.args = heroic_cmd.args.duplicate()
	launcher.tags = ["heroic", "launcher"]
	launcher.categories = ["Launchers"]
	launcher.installed = true
	launcher.hidden = false
	items.append(launcher)

	var games := await heroic.get_games()
	for game in games:
		var app_id := str(game.get("provider_app_id", ""))
		var title := str(game.get("name", ""))
		var uri := str(game.get("uri", ""))
		var store := str(game.get("store", ""))
		if app_id.is_empty() or title.is_empty() or uri.is_empty():
			continue

		var item_args := heroic_cmd.args.duplicate()
		item_args.append("--no-gui")
		item_args.append(uri)

		var item := LibraryLaunchItem.new()
		item.name = title
		item.provider_app_id = app_id
		item.command = heroic_cmd.command
		item.args = item_args
		item.tags = ["heroic", store]
		item.categories = ["Games", "Heroic"]
		item.installed = true
		item.hidden = false
		item.metadata = {
			"store": store,
			"app_id": str(game.get("app_id", "")),
			"uri": uri,
			"install_path": str(game.get("install_path", "")),
		}
		items.append(item)

	logger.info(
		"Found {0} Heroic games plus the launcher".format([items.size() - 1])
	)
	return items

