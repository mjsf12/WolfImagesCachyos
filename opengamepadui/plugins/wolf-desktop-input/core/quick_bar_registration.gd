extends RefCounted

## Registers a procedural menu without OGUI 0.45.1's legacy SectionLabel
## discovery. That path only searches owned scene nodes and dereferences null
## for controls assembled at runtime.

const TITLE := "Desktop Input"


static func add_menu(
	quick_bar: Node,
	menu: Control,
	icon: Texture2D,
) -> bool:
	if not is_instance_valid(quick_bar):
		return false
	if not quick_bar.has_method("add_child_menu"):
		return false
	quick_bar.call("add_child_menu", menu, icon, null, TITLE)
	return true
