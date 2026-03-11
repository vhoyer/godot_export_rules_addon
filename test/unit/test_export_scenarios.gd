## Integration-style scenarios: given a set of rules and an export_presets.cfg,
## verify the correct files are excluded for each preset.
##
## Uses ConfigFile.parse() to build in-memory presets — no disk I/O needed.
## File paths used in rules must exist in the project so _expand_path resolves them.
extends GutTest

const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')
const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PathRule = preload('res://addons/export_rules/path_rule.gd')

# Real files that exist in this project, used as stable test fixtures.
const FILE_A := 'res://icon.svg'
const FILE_B := 'res://project.godot'

var updater: ExportPresetsUpdater


func before_each() -> void:
	updater = ExportPresetsUpdater.new()


# --- helpers ---

func _make_rule(path: String, tags: Array[String]) -> PathRule:
	var rule := PathRule.new()
	rule.path = path
	rule.required_tags = tags
	return rule


func _make_config(rules: Array) -> ExportRulesConfig:
	var config := ExportRulesConfig.new()
	config.rules = rules
	return config


func _parse_presets(ini_text: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.parse(ini_text)
	return cfg


func _excluded(cfg: ConfigFile, section: String) -> PackedStringArray:
	return cfg.get_value(section, 'export_files', PackedStringArray())


# --- No rules ---

func test_no_rules_produces_empty_exclusions() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam"
custom_features="steam"
""")
	updater._apply_rules(_make_config([]), cfg)
	assert_eq(_excluded(cfg, 'preset.0').size(), 0)


# --- Always-excluded rules (empty required_tags) ---

func test_always_excluded_rule_appears_in_every_preset() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam"
custom_features="steam"

[preset.1]
name="Demo"
custom_features="demo"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, [])]), cfg)
	assert_true(_excluded(cfg, 'preset.0').has(FILE_A))
	assert_true(_excluded(cfg, 'preset.1').has(FILE_A))


func test_always_excluded_rule_appears_in_preset_without_tags() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Generic"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, [])]), cfg)
	assert_true(_excluded(cfg, 'preset.0').has(FILE_A))


# --- Tag-required rules ---

func test_tag_required_rule_excluded_from_preset_missing_tag() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Demo"
custom_features="demo"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, ['steam'])]), cfg)
	assert_true(_excluded(cfg, 'preset.0').has(FILE_A))


func test_tag_required_rule_included_in_matching_preset() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam"
custom_features="steam"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, ['steam'])]), cfg)
	assert_false(_excluded(cfg, 'preset.0').has(FILE_A))


func test_rule_included_when_preset_has_matching_tag_plus_extras() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam HD Demo"
custom_features="steam,hd,demo"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, ['steam'])]), cfg)
	assert_false(_excluded(cfg, 'preset.0').has(FILE_A))


func test_tag_required_rule_excluded_from_preset_without_any_tags() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Generic"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, ['steam'])]), cfg)
	assert_true(_excluded(cfg, 'preset.0').has(FILE_A))


# --- Multi-tag rules ---

func test_multi_tag_rule_included_only_when_all_tags_present() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam HD"
custom_features="steam,hd"

[preset.1]
name="Steam Only"
custom_features="steam"

[preset.2]
name="HD Only"
custom_features="hd"

[preset.3]
name="Demo"
custom_features="demo"
""")
	updater._apply_rules(_make_config([_make_rule(FILE_A, ['steam', 'hd'])]), cfg)
	assert_false(_excluded(cfg, 'preset.0').has(FILE_A), 'steam+hd preset should include the file')
	assert_true(_excluded(cfg, 'preset.1').has(FILE_A), 'steam-only preset should exclude the file')
	assert_true(_excluded(cfg, 'preset.2').has(FILE_A), 'hd-only preset should exclude the file')
	assert_true(_excluded(cfg, 'preset.3').has(FILE_A), 'demo preset should exclude the file')


# --- Mixed rules across multiple presets ---

func test_mixed_rules_each_preset_gets_correct_exclusions() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam"
custom_features="steam"

[preset.1]
name="Demo"
custom_features="demo"
""")
	var config := _make_config([
		_make_rule(FILE_A, ['steam']),  # included only in steam preset
		_make_rule(FILE_B, []),         # always excluded
	])
	updater._apply_rules(config, cfg)

	# Steam preset: FILE_A included, FILE_B excluded
	assert_false(_excluded(cfg, 'preset.0').has(FILE_A))
	assert_true(_excluded(cfg, 'preset.0').has(FILE_B))

	# Demo preset: both excluded
	assert_true(_excluded(cfg, 'preset.1').has(FILE_A))
	assert_true(_excluded(cfg, 'preset.1').has(FILE_B))


# --- Output properties ---

func test_apply_rules_sets_export_filter_to_exclude_on_all_presets() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Steam"
custom_features="steam"
export_filter="all_resources"

[preset.1]
name="Demo"
custom_features="demo"
export_filter="all_resources"
""")
	updater._apply_rules(_make_config([]), cfg)
	assert_eq(cfg.get_value('preset.0', 'export_filter', ''), 'exclude')
	assert_eq(cfg.get_value('preset.1', 'export_filter', ''), 'exclude')


func test_exclusion_list_is_sorted() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Generic"
""")
	# Rules in reverse alphabetical order — output must still be sorted.
	var config := _make_config([
		_make_rule(FILE_B, []),  # res://project.godot
		_make_rule(FILE_A, []),  # res://icon.svg
	])
	updater._apply_rules(config, cfg)
	var excluded := _excluded(cfg, 'preset.0')
	assert_eq(excluded.size(), 2)
	assert_true(excluded[0] < excluded[1], 'excluded files must be in sorted order')


func test_duplicate_rules_for_same_file_produce_no_duplicates() -> void:
	var cfg := _parse_presets("""
[preset.0]
name="Generic"
""")
	var config := _make_config([_make_rule(FILE_A, []), _make_rule(FILE_A, [])])
	updater._apply_rules(config, cfg)
	assert_eq(_excluded(cfg, 'preset.0').size(), 1)


# --- Non-preset sections ---

func test_non_preset_sections_are_not_modified() -> void:
	var cfg := _parse_presets("""
[general]
some_key="some_value"

[preset.0]
name="Steam"
custom_features="steam"
""")
	updater._apply_rules(_make_config([]), cfg)
	assert_false(cfg.has_section_key('general', 'export_files'))
	assert_false(cfg.has_section_key('general', 'export_filter'))
