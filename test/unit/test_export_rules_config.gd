extends GutTest

const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PathRule = preload('res://addons/export_rules/path_rule.gd')

var config: ExportRulesConfig


func before_each() -> void:
	# Double the config so we can stub save() and avoid writing to disk.
	config = partial_double(ExportRulesConfig).new()
	stub(config, 'save').to_do_nothing()


func after_each() -> void:
	config = null


# --- get_rule_for_path ---

func test_get_rule_for_path_empty_rules_returns_null() -> void:
	assert_null(config.get_rule_for_path('res://some/path'))


func test_get_rule_for_path_finds_existing_rule() -> void:
	var rule := PathRule.new()
	rule.path = 'res://stages/levels'
	config.rules.append(rule)
	assert_eq(config.get_rule_for_path('res://stages/levels'), rule)


func test_get_rule_for_path_no_match_returns_null() -> void:
	var rule := PathRule.new()
	rule.path = 'res://stages/levels'
	config.rules.append(rule)
	assert_null(config.get_rule_for_path('res://other/path'))


# --- add_rule ---

func test_add_rule_creates_new_rule() -> void:
	var rule := config.add_rule('res://stages/levels')
	assert_not_null(rule)
	assert_eq(rule.path, 'res://stages/levels')


func test_add_rule_strips_trailing_slash() -> void:
	var rule := config.add_rule('res://stages/levels/')
	assert_eq(rule.path, 'res://stages/levels')


func test_add_rule_trailing_slash_matches_existing_rule() -> void:
	var first := config.add_rule('res://stages/levels')
	var second := config.add_rule('res://stages/levels/')
	assert_eq(first, second)
	assert_eq(config.rules.size(), 1)


func test_add_rule_appends_to_rules() -> void:
	config.add_rule('res://stages/levels')
	assert_eq(config.rules.size(), 1)


func test_add_rule_returns_existing_if_duplicate() -> void:
	var first := config.add_rule('res://stages/levels')
	var second := config.add_rule('res://stages/levels')
	assert_eq(first, second)
	assert_eq(config.rules.size(), 1)


func test_add_multiple_distinct_rules() -> void:
	config.add_rule('res://stages/levels')
	config.add_rule('res://assets/steam')
	assert_eq(config.rules.size(), 2)


# --- remove_rule ---

func test_remove_rule_removes_matching_rule() -> void:
	config.add_rule('res://stages/levels')
	config.remove_rule('res://stages/levels')
	assert_eq(config.rules.size(), 0)


func test_remove_rule_nonexistent_path_does_nothing() -> void:
	config.add_rule('res://stages/levels')
	config.remove_rule('res://other/path')
	assert_eq(config.rules.size(), 1)


func test_remove_rule_only_removes_matching() -> void:
	config.add_rule('res://stages/levels')
	config.add_rule('res://assets/steam')
	config.remove_rule('res://stages/levels')
	assert_eq(config.rules.size(), 1)
	assert_not_null(config.get_rule_for_path('res://assets/steam'))


# --- mark_path_known / is_path_known ---

func test_new_path_is_not_known() -> void:
	assert_false(config.is_path_known('res://stages/new_level'))


func test_marked_path_is_known() -> void:
	config.mark_path_known('res://stages/new_level')
	assert_true(config.is_path_known('res://stages/new_level'))


func test_mark_path_known_does_not_add_duplicates() -> void:
	config.mark_path_known('res://stages/new_level')
	config.mark_path_known('res://stages/new_level')
	assert_eq(config.known_paths.size(), 1)


func test_mark_distinct_paths_as_known() -> void:
	config.mark_path_known('res://stages/level_a')
	config.mark_path_known('res://stages/level_b')
	assert_eq(config.known_paths.size(), 2)
	assert_true(config.is_path_known('res://stages/level_a'))
	assert_true(config.is_path_known('res://stages/level_b'))
