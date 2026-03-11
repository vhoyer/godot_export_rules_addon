extends GutTest

const PathRule = preload('res://addons/export_rules/path_rule.gd')

var rule: PathRule


func before_each() -> void:
	rule = PathRule.new()


func after_each() -> void:
	rule = null


# --- should_include_for_tags ---

func test_empty_required_tags_returns_false() -> void:
	rule.required_tags = []
	assert_false(rule.should_include_for_tags([]))


func test_empty_required_tags_with_preset_tags_returns_false() -> void:
	rule.required_tags = []
	assert_false(rule.should_include_for_tags(['steam']))


func test_single_tag_matches_returns_true() -> void:
	rule.required_tags = ['steam']
	assert_true(rule.should_include_for_tags(['steam']))


func test_single_tag_no_match_returns_false() -> void:
	rule.required_tags = ['steam']
	assert_false(rule.should_include_for_tags(['demo']))


func test_single_tag_empty_preset_tags_returns_false() -> void:
	rule.required_tags = ['steam']
	assert_false(rule.should_include_for_tags([]))


func test_all_required_tags_present_returns_true() -> void:
	rule.required_tags = ['steam', 'hd']
	assert_true(rule.should_include_for_tags(['steam', 'hd']))


func test_partial_required_tags_match_returns_false() -> void:
	rule.required_tags = ['steam', 'hd']
	assert_false(rule.should_include_for_tags(['steam']))


func test_no_required_tags_match_returns_false() -> void:
	rule.required_tags = ['steam', 'hd']
	assert_false(rule.should_include_for_tags(['demo', 'mobile']))


func test_preset_has_extra_tags_still_returns_true() -> void:
	rule.required_tags = ['steam']
	assert_true(rule.should_include_for_tags(['steam', 'hd', 'demo']))


# --- get_status_label ---

func test_status_label_empty_tags_returns_always_excluded() -> void:
	rule.required_tags = []
	assert_eq(rule.get_status_label(), 'Always Excluded')


func test_status_label_single_tag() -> void:
	rule.required_tags = ['steam']
	assert_eq(rule.get_status_label(), 'Required: steam')


func test_status_label_multiple_tags() -> void:
	rule.required_tags = ['steam', 'hd']
	assert_eq(rule.get_status_label(), 'Required: steam, hd')
