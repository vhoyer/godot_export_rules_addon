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


# _is_godot_resource delegates to ResourceLoader.exists(), which Godot uses
# internally to determine if a path is a loadable resource. Integration-level
# coverage (real project files) is more meaningful than unit tests here.


# --- _is_ignored_dir ---

func test_regular_dir_is_not_ignored() -> void:
	assert_false(updater._is_ignored_dir('res://scenes'))


func test_gdignore_dir_is_ignored() -> void:
	# .godot/ contains a .gdignore (and is itself dot-prefixed, so doubly ignored)
	assert_true(updater._is_ignored_dir('res://.godot'))


func test_regular_dir_with_gdignore_is_ignored() -> void:
	assert_true(updater._is_ignored_dir('res://test/fixtures/gdignored'))


