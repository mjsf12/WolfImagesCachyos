extends GutTest

const QuickBarRegistration := preload(
	"res://plugins/wolf-desktop-input/core/quick_bar_registration.gd"
)


class FakeQuickBar extends Node:
	var received_menu: Control
	var received_title := ""

	func add_child_menu(
		menu: Control,
		_icon: Texture2D,
		_focus_node: Control = null,
		title: String = "",
	) -> void:
		received_menu = menu
		received_title = title


func test_procedural_section_is_not_owned() -> void:
	var menu := VBoxContainer.new()
	var section := Label.new()
	section.name = "SectionLabel"
	menu.add_child(section)

	assert_null(menu.find_child("SectionLabel"))
	assert_eq(menu.find_child("SectionLabel", true, false), section)
	menu.free()


func test_registers_with_explicit_title() -> void:
	var quick_bar := FakeQuickBar.new()
	var menu := VBoxContainer.new()

	assert_true(QuickBarRegistration.add_menu(quick_bar, menu, null))
	assert_eq(quick_bar.received_menu, menu)
	assert_eq(quick_bar.received_title, QuickBarRegistration.TITLE)
	quick_bar.free()
	menu.free()


func test_rejects_incompatible_quick_bar() -> void:
	var quick_bar := Node.new()
	var menu := VBoxContainer.new()

	assert_false(QuickBarRegistration.add_menu(quick_bar, menu, null))
	quick_bar.free()
	menu.free()
