## E2E test: verifies the actual stages/ scenes are routed to the correct
## export presets, using the real export_rules.json and export_presets.cfg.
##
## Loads both config files from disk, applies the rules in memory (no write),
## and asserts inclusion/exclusion for each scene in each preset.
extends GutTest

const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')
const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')

const SCENE_DEMO    := 'res://stages/level_demo/scene.tscn'
const SCENE_FULL    := 'res://stages/level_full/scene.tscn'
const SCENE_MENU    := 'res://stages/main_menu/scene.tscn'
const PRESET_DEMO   := 'preset.0'  # windows_demo — custom_features="demo"
const PRESET_FULL   := 'preset.1'  # windows_full — custom_features="full"

var updater: ExportPresetsUpdater
var config: ExportRulesConfig
var cfg: ConfigFile


func before_each() -> void:
	updater = ExportPresetsUpdater.new()

	config = ExportRulesConfig.new()
	config.load_from_json()

	cfg = ConfigFile.new()
	cfg.load('res://export_presets.cfg')

	updater._apply_rules(config, cfg)


func _export_files(section: String) -> PackedStringArray:
	return cfg.get_value(section, 'export_files', PackedStringArray())


# --- windows_demo preset (tag: "demo") ---

func test_level_demo_included_in_demo_preset() -> void:
	assert_true(
		_export_files(PRESET_DEMO).has(SCENE_DEMO),
		'level_demo should be included in the demo preset'
	)


func test_level_full_excluded_from_demo_preset() -> void:
	assert_false(
		_export_files(PRESET_DEMO).has(SCENE_FULL),
		'level_full should be excluded from the demo preset'
	)


func test_main_menu_included_in_demo_preset() -> void:
	assert_true(
		_export_files(PRESET_DEMO).has(SCENE_MENU),
		'main_menu has no rule and should be included in the demo preset'
	)


# --- windows_full preset (tag: "full") ---

func test_level_full_included_in_full_preset() -> void:
	assert_true(
		_export_files(PRESET_FULL).has(SCENE_FULL),
		'level_full should be included in the full preset'
	)


func test_level_demo_excluded_from_full_preset() -> void:
	assert_false(
		_export_files(PRESET_FULL).has(SCENE_DEMO),
		'level_demo should be excluded from the full preset'
	)


func test_main_menu_included_in_full_preset() -> void:
	assert_true(
		_export_files(PRESET_FULL).has(SCENE_MENU),
		'main_menu has no rule and should be included in the full preset'
	)
