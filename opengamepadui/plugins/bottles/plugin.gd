extends Plugin


func _ready() -> void:
	logger = Log.get_logger("BottlesPlugin", Log.LEVEL.INFO)
	logger.info("Bottles plugin loaded")
	var library := load(plugin_base + "/core/library.tscn").instantiate() as Library
	add_library(library)
