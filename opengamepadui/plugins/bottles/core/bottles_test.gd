extends GutTest

const Bottles := preload("res://plugins/bottles/core/bottles.gd")


func test_parses_documented_json_array() -> void:
	var bottles := Bottles.new()
	var actual = bottles._parse_json_output('[{"name":"Game"}]')

	assert_true(actual is Array)
	assert_eq(actual[0]["name"], "Game")


func test_parses_json_after_a_launcher_banner() -> void:
	var bottles := Bottles.new()
	var actual = bottles._parse_json_output(
		'Bottles startup message\n[{"name":"Game","removed":null}]'
	)

	assert_true(actual is Array)
	assert_eq(actual[0]["removed"], null)


func test_rejects_non_json_output() -> void:
	var bottles := Bottles.new()

	assert_eq(bottles._parse_json_output("not json"), null)
