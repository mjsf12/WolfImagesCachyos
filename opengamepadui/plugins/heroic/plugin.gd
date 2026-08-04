extends Plugin


func _ready() -> void:
	logger = Log.get_logger("HeroicPlugin", Log.LEVEL.INFO)
	logger.info("Heroic plugin loaded")
	var library := load(plugin_base + "/core/library.tscn").instantiate() as Library
	add_library(library)

