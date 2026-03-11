extends GutTest

const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')

var updater: ExportPresetsUpdater


func before_each() -> void:
	updater = ExportPresetsUpdater.new()


# --- _is_preset_section ---

func test_preset_section_index_zero() -> void:
	assert_true(updater._is_preset_section('preset.0'))


func test_preset_section_large_index() -> void:
	assert_true(updater._is_preset_section('preset.42'))


func test_not_preset_prefix() -> void:
	assert_false(updater._is_preset_section('general'))


func test_preset_without_number_suffix() -> void:
	assert_false(updater._is_preset_section('preset.options'))


func test_empty_string_is_not_preset_section() -> void:
	assert_false(updater._is_preset_section(''))


func test_preset_dot_only_is_not_valid() -> void:
	assert_false(updater._is_preset_section('preset.'))


# --- parse_packed_string_array ---

func test_parse_empty_packed_string_array() -> void:
	var result := updater.parse_packed_string_array('PackedStringArray()')
	assert_eq(result, [])


func test_parse_missing_packed_string_array_marker() -> void:
	var result := updater.parse_packed_string_array('something else entirely')
	assert_eq(result, [])


func test_parse_single_element() -> void:
	var result: Array[String] = updater.parse_packed_string_array('PackedStringArray("res://file.gd")')
	assert_eq(result.size(), 1)
	assert_eq(result[0], 'res://file.gd')


func test_parse_two_elements() -> void:
	var result: Array[String] = updater.parse_packed_string_array('PackedStringArray("res://a.gd", "res://b.gd")')
	assert_eq(result.size(), 2)
	assert_eq(result[0], 'res://a.gd')
	assert_eq(result[1], 'res://b.gd')


func test_parse_three_elements() -> void:
	var result: Array[String] = updater.parse_packed_string_array('PackedStringArray("res://a.gd", "res://b.gd", "res://c.gd")')
	assert_eq(result.size(), 3)
	assert_eq(result[2], 'res://c.gd')

