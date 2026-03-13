extends GutTest

const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PANEL_SCENE = preload('res://addons/export_rules/export_rules_panel/export_rules_panel.tscn')

var _panel


func before_each() -> void:
	_panel = PANEL_SCENE.instantiate()
	add_child_autofree(_panel)
	_panel.setup(ExportRulesConfig.new(), null)


# --- RulesTree: .gdignore folders ---

func test_gdignored_folder_not_in_rules_tree() -> void:
	assert_null(
		_panel._find_tree_item_by_path('res://test/fixtures/gdignored'),
		'folder with .gdignore must not appear in the rules tree'
	)
