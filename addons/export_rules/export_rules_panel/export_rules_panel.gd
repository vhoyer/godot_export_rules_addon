@tool
extends VBoxContainer

const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')
const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PathRule = preload('res://addons/export_rules/path_rule.gd')
const HIDDEN_FILES: Array[String] = ['project.godot', 'export_presets.cfg', 'export_rules.json']

var _config: ExportRulesConfig
var _plugin: EditorPlugin
var _selected_rule: Resource  # PathRule or null
var _selected_path: String = ''
var _pending_new_path: String = ''
var _known_folders_cache: Array[String] = []
var _folder_colors: Dictionary = {}  # res://path/ -> color name, from project.godot
var _expanded_paths: Dictionary = {}  # res://path -> bool (true = expanded)

@export_group('Folder Colors')
@export var color_red: Color     = Color(0.8784314, 0.23921569, 0.23921569, 1)
@export var color_orange: Color  = Color(0.8784314, 0.49411765, 0.23921569, 1)
@export var color_yellow: Color  = Color(0.8784314, 0.78039217, 0.23921569, 1)
@export var color_green: Color   = Color(0.4392157, 0.8784314, 0.23921569, 1)
@export var color_teal: Color    = Color(0.23921569, 0.8784314, 0.5568628, 1)
@export var color_blue: Color    = Color(0.23921569, 0.7411765, 0.8784314, 1)
@export var color_purple: Color  = Color(0.4392157, 0.23921569, 0.8784314, 1)
@export var color_pink: Color    = Color(0.8784314, 0.23921569, 0.5176471, 1)
@export var color_gray: Color    = Color(0.5411765, 0.5411765, 0.5411765, 1)
@export var color_default: Color = Color(0, 0, 0, 0)
@export_group('')

@onready
var _rules_tree: Tree = %RulesTree
@onready
var _rule_editor = %RuleEditor
@onready
var _preset_preview = %PresetPreview
@onready
var _status_label: Label = %StatusLabel
@onready
var _new_folder_policy_option: OptionButton = %NewFolderPolicyOption
@onready
var _ask_dialog: ConfirmationDialog = %AskDialog
@onready
var _ignored_globs_edit: LineEdit = %LineEdit


func _ready() -> void:
	%UpdateButton.pressed.connect(_on_update_pressed)
	%ScanButton.pressed.connect(_on_scan_pressed)
	_rules_tree.item_selected.connect(_on_rule_selected)
	_new_folder_policy_option.item_selected.connect(_on_policy_changed)
	_ask_dialog.confirmed.connect(_on_ask_dialog_confirmed)
	_ask_dialog.canceled.connect(_on_ask_dialog_canceled)
	_rule_editor.rules_changed.connect(_on_rule_editor_rules_changed)
	_rule_editor.rule_delete_requested.connect(_on_remove_rule_pressed)
	_rule_editor.preview_refresh_needed.connect(_preset_preview.refresh)

	_rules_tree.set_column_title(0, 'Name')
	_rules_tree.set_column_title(1, 'Status')
	_rules_tree.set_column_titles_visible(true)
	_rules_tree.set_column_expand(0, true)
	_rules_tree.set_column_expand(1, false)
	_rules_tree.set_column_custom_minimum_width(1, 240)
	_rules_tree.item_edited.connect(_on_tree_item_edited)

	_new_folder_policy_option.clear()
	_new_folder_policy_option.add_item('Auto Include', ExportRulesConfig.NewFolderPolicy.AUTO_INCLUDE)
	_new_folder_policy_option.add_item('Auto Exclude', ExportRulesConfig.NewFolderPolicy.AUTO_EXCLUDE)
	_new_folder_policy_option.add_item('Ask', ExportRulesConfig.NewFolderPolicy.ASK)

	_ignored_globs_edit.text_submitted.connect(_on_ignored_globs_changed)
	_ignored_globs_edit.focus_exited.connect(func() -> void: _on_ignored_globs_changed(_ignored_globs_edit.text))
	%GlobRefreshButton.pressed.connect(_on_scan_pressed)


func setup(config: Resource, plugin: EditorPlugin) -> void:
	_config = config
	_plugin = plugin
	_new_folder_policy_option.selected = _config.new_folder_policy
	_ignored_globs_edit.text = ', '.join(_config.ignored_globs)
	_snapshot_known_folders()
	refresh_file_tree()


func _on_rule_editor_rules_changed() -> void:
	_selected_rule = _config.get_rule_for_path(_selected_path)
	refresh_file_tree()


func refresh_file_tree() -> void:
	if not _rules_tree or not _config:
		return
	_snapshot_expanded_state()
	_folder_colors = ProjectSettings.get_setting('file_customization/folder_colors', {}) as Dictionary
	_rules_tree.clear()
	var root := _rules_tree.create_item()
	_build_tree_from_filesystem('res://', root)
	_apply_expanded_state()
	if not _selected_path.is_empty():
		var item := _find_tree_item_by_path(_selected_path)
		if item:
			item.select(0)


func _snapshot_expanded_state() -> void:
	var root := _rules_tree.get_root()
	if not root:
		return
	var item := root.get_first_child()
	while item:
		_snapshot_expanded_recursive(item)
		item = item.get_next()


func _snapshot_expanded_recursive(item: TreeItem) -> void:
	var path := item.get_metadata(0) as String
	if not path.is_empty():
		_expanded_paths[path] = not item.is_collapsed()
	var child := item.get_first_child()
	while child:
		_snapshot_expanded_recursive(child)
		child = child.get_next()


func _apply_expanded_state() -> void:
	var root := _rules_tree.get_root()
	if not root:
		return
	var item := root.get_first_child()
	while item:
		_apply_expanded_recursive(item)
		item = item.get_next()


func _apply_expanded_recursive(item: TreeItem) -> void:
	var path := item.get_metadata(0) as String
	if not path.is_empty() and _expanded_paths.has(path):
		item.set_collapsed(not _expanded_paths[path])
	var child := item.get_first_child()
	while child:
		_apply_expanded_recursive(child)
		child = child.get_next()


## Recursively builds the tree from the actual project filesystem.
## disabled=true means a parent folder has a rule and governs this subtree.
## inherited_bg is the background colour passed down from the nearest ancestor
## folder that has a colour defined in file_customization/folder_colors.
## Returns true if any rule exists in this subtree (used for collapse logic).
func _build_tree_from_filesystem(dir_path: String, parent_item: TreeItem, disabled: bool = false, inherited_bg: Color = Color.TRANSPARENT) -> bool:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return false

	var subdirs: Array[String] = []
	var files: Array[String] = []

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != '':
		if not entry.begins_with('.'):
			if dir.current_is_dir():
				subdirs.append(entry)
			elif not entry.ends_with('.import') and not entry.ends_with('.uid') and not entry in HIDDEN_FILES:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	subdirs.sort_custom(func(a: String, b: String) -> bool: return _natural_less_than(a, b))
	files.sort_custom(func(a: String, b: String) -> bool: return _natural_less_than(a, b))

	var subtree_has_rules := false

	for d in subdirs:
		var res_path := dir_path + d
		var rule := _config.get_rule_for_path(res_path)
		var is_excluded: bool = not disabled and rule != null and rule.required_tags.is_empty()

		# Own colour overrides inherited; otherwise pass the inherited colour down.
		var own_key := res_path + '/'
		var effective_bg := inherited_bg
		if _folder_colors.has(own_key):
			effective_bg = Color(_folder_color_from_name(_folder_colors[own_key] as String), 0.15)

		var item := _rules_tree.create_item(parent_item)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, d + '/')
		item.set_metadata(0, res_path)
		item.set_tooltip_text(0, res_path)
		if effective_bg.a > 0:
			item.set_custom_bg_color(0, effective_bg)
			item.set_custom_bg_color(1, effective_bg)

		if disabled:
			_apply_disabled_style(item)
		else:
			item.set_editable(0, true)
			_set_rule_columns(item, rule)

		var self_has_rule := not disabled and rule != null
		subtree_has_rules = subtree_has_rules or self_has_rule

		var child_has_rules := false
		if not is_excluded:
			child_has_rules = _build_tree_from_filesystem(dir_path + d + '/', item, disabled or self_has_rule, Color(effective_bg, effective_bg.a * 0.7))
			if not disabled:
				subtree_has_rules = subtree_has_rules or child_has_rules

		if not disabled:
			if rule == null:
				item.set_indeterminate(0, child_has_rules)
				if not child_has_rules:
					item.set_checked(0, true)
			elif rule.required_tags.is_empty():
				item.set_indeterminate(0, false)
				item.set_checked(0, false)
			else:
				item.set_indeterminate(0, true)

		item.set_collapsed(disabled or self_has_rule or not child_has_rules)

	for f in files:
		var res_path := dir_path + f
		var rule := _config.get_rule_for_path(res_path)

		var item := _rules_tree.create_item(parent_item)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, f)
		item.set_metadata(0, res_path)
		item.set_tooltip_text(0, res_path)
		if inherited_bg.a > 0:
			item.set_custom_bg_color(0, inherited_bg)
			item.set_custom_bg_color(1, inherited_bg)

		if _is_glob_ignored(f):
			_apply_glob_ignored_style(item)
		elif disabled:
			_apply_disabled_style(item)
		else:
			item.set_editable(0, true)
			_set_checkbox_state(item, rule)
			_set_rule_columns(item, rule)
			if rule:
				subtree_has_rules = true

	return subtree_has_rules


func _apply_glob_ignored_style(item: TreeItem) -> void:
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_indeterminate(0, false)
	item.set_checked(0, false)
	item.set_custom_color(0, Color(0.5, 0.5, 0.5))
	item.set_text(1, 'Ignored by filter glob')
	item.set_custom_color(1, Color(0.7, 0.5, 0.2))


func _apply_disabled_style(item: TreeItem) -> void:
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_indeterminate(0, true)
	item.set_custom_color(0, Color(0.5, 0.5, 0.5))


func _set_checkbox_state(item: TreeItem, rule: Resource) -> void:
	if rule == null:
		item.set_indeterminate(0, false)
		item.set_checked(0, true)
	elif rule.required_tags.is_empty():
		item.set_indeterminate(0, false)
		item.set_checked(0, false)
	else:
		item.set_indeterminate(0, true)


func _set_rule_columns(item: TreeItem, rule: Resource) -> void:
	if rule == null:
		item.set_text(1, 'Always Included')
		item.set_custom_color(1, Color(0.6, 0.6, 0.6))
		return
	item.set_text(1, rule.get_status_label())
	if rule.required_tags.is_empty():
		item.set_custom_color(1, Color(1, 0.4, 0.4))
	else:
		item.set_custom_color(1, Color(0.4, 1, 0.4))


func _folder_color_from_name(color_name: String) -> Color:
	match color_name:
		'red':    return color_red
		'orange': return color_orange
		'yellow': return color_yellow
		'green':  return color_green
		'teal':   return color_teal
		'blue':   return color_blue
		'purple': return color_purple
		'pink':   return color_pink
		'gray':   return color_gray
	return color_default


## Natural sort comparator — numbers in paths are sorted numerically.
## E.g. "factory9" sorts before "factory10".
static func _natural_less_than(a: String, b: String) -> bool:
	var i: int = 0
	var j: int = 0
	while i < a.length() and j < b.length():
		var is_digit_a: bool = a[i] >= '0' and a[i] <= '9'
		var is_digit_b: bool = b[j] >= '0' and b[j] <= '9'
		if is_digit_a and is_digit_b:
			var num_a_str: String = ''
			while i < a.length() and a[i] >= '0' and a[i] <= '9':
				num_a_str += a[i]
				i += 1
			var num_b_str: String = ''
			while j < b.length() and b[j] >= '0' and b[j] <= '9':
				num_b_str += b[j]
				j += 1
			var num_a: int = num_a_str.to_int()
			var num_b: int = num_b_str.to_int()
			if num_a != num_b:
				return num_a < num_b
		else:
			if a[i] != b[j]:
				return a[i] < b[j]
			i += 1
			j += 1
	return a.length() < b.length()


func _snapshot_known_folders() -> void:
	_known_folders_cache.clear()
	_scan_folders_recursive('res://', _known_folders_cache)


func _scan_folders_recursive(dir_path: String, out_folders: Array[String]) -> void:
	var dir:= DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name:= dir.get_next()
	while entry_name != '':
		if not entry_name.begins_with('.') and dir.current_is_dir():
			var full_path: String = dir_path + entry_name + '/'
			out_folders.append(full_path)
			_scan_folders_recursive(full_path, out_folders)
		entry_name = dir.get_next()
	dir.list_dir_end()


func check_for_new_folders() -> void:
	if not _config:
		return
	var current_folders: Array[String] = []
	_scan_folders_recursive('res://', current_folders)
	for folder_path in current_folders:
		if _known_folders_cache.has(folder_path):
			continue
		# Skip if a parent folder is also new — only report the topmost new folder.
		var parent_is_new := false
		for other in current_folders:
			if other != folder_path and folder_path.begins_with(other) and not _known_folders_cache.has(other):
				parent_is_new = true
				break
		if not parent_is_new:
			_on_new_folder_detected(folder_path)
	_known_folders_cache = current_folders


func _on_new_folder_detected(folder_path: String) -> void:
	if not _config:
		return
	var policy:= _config.new_folder_policy as ExportRulesConfig.NewFolderPolicy
	match policy:
		ExportRulesConfig.NewFolderPolicy.AUTO_INCLUDE:
			_config.mark_path_known(folder_path)
			_config.save()
		ExportRulesConfig.NewFolderPolicy.AUTO_EXCLUDE:
			_config.add_rule(folder_path)
			_config.mark_path_known(folder_path)
			refresh_file_tree()
			_set_status('Auto-excluded new folder: ' + folder_path)
		ExportRulesConfig.NewFolderPolicy.ASK:
			if _pending_new_path.is_empty():
				_pending_new_path = folder_path
				_ask_dialog.dialog_text = (
					'New folder detected:\n' + folder_path +
					'\n\nWhat should happen when exporting?'
				)
				_ask_dialog.ok_button_text = 'Exclude from Exports'
				_ask_dialog.cancel_button_text = 'Include in Exports'
				_ask_dialog.popup_centered()


func update_export_presets() -> void:
	if not _config:
		return
	var updater:= ExportPresetsUpdater.new()
	var error:= updater.update(_config)
	if error == OK:
		_set_status('Export presets updated successfully.')
	else:
		_set_status('ERROR: Failed to update export presets.')


func _set_status(message: String) -> void:
	if _status_label:
		_status_label.text = message


func _find_tree_item_by_path(path: String) -> TreeItem:
	var root: TreeItem = _rules_tree.get_root()
	if not root:
		return null
	return _find_item_recursive(root, path)


func _find_item_recursive(item: TreeItem, path: String) -> TreeItem:
	if item.get_metadata(0) == path:
		return item
	var child: TreeItem = item.get_first_child()
	while child:
		var found: TreeItem = _find_item_recursive(child, path)
		if found:
			return found
		child = child.get_next()
	return null


# Signal handlers

func _on_update_pressed() -> void:
	update_export_presets()


func _on_scan_pressed() -> void:
	refresh_file_tree()


func _on_policy_changed(index: int) -> void:
	if not _config:
		return
	_config.new_folder_policy = _new_folder_policy_option.get_item_id(index)
	_config.save()


func _on_rule_selected() -> void:
	var selected: TreeItem = _rules_tree.get_selected()
	if not selected:
		_selected_rule = null
		_selected_path = ''
		_rule_editor.show_placeholder()
		return
	_selected_path = selected.get_metadata(0) as String
	_selected_rule = _config.get_rule_for_path(_selected_path)
	_rule_editor.load_rule(_config, _selected_path, _selected_rule)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _rules_tree or not _rules_tree.has_focus():
		return
	var key_event:= event as InputEventKey
	if key_event and key_event.pressed and not key_event.echo and key_event.keycode == KEY_DELETE:
		_on_remove_rule_pressed()
		get_viewport().set_input_as_handled()


func _on_remove_rule_pressed() -> void:
	if _selected_path.is_empty() or not _selected_rule:
		return
	var removed_path: String = _selected_path
	_config.remove_rule(removed_path)
	_selected_rule = null
	# Keep _selected_path so the item stays selected after refresh
	refresh_file_tree()
	_set_status('Rule removed for: ' + removed_path)


## Called when the user clicks a checkbox cell. We revert the toggle (the checkbox
## is read-only — clicking it opens the rule editor instead of toggling state).
func _on_tree_item_edited() -> void:
	var item := _rules_tree.get_edited()
	if not item:
		return
	var path := item.get_metadata(0) as String
	var rule := _config.get_rule_for_path(path)
	# Revert the checkbox to its correct visual state
	if rule == null:
		var children_have_rules := _tree_item_children_have_rules(item)
		item.set_indeterminate(0, children_have_rules)
		if not children_have_rules:
			item.set_checked(0, true)
	else:
		_set_checkbox_state(item, rule)
	_selected_path = path
	_selected_rule = rule
	_rule_editor.load_rule(_config, path, rule)


func _tree_item_children_have_rules(item: TreeItem) -> bool:
	var child := item.get_first_child()
	while child:
		if _config.get_rule_for_path(child.get_metadata(0) as String) != null:
			return true
		if _tree_item_children_have_rules(child):
			return true
		child = child.get_next()
	return false


func _on_ask_dialog_confirmed() -> void:
	if not _pending_new_path.is_empty():
		_config.add_rule(_pending_new_path)
		_config.mark_path_known(_pending_new_path)
		refresh_file_tree()
		_set_status('Excluded new folder: ' + _pending_new_path)
	_pending_new_path = ''


func _is_glob_ignored(filename: String) -> bool:
	for pattern in _config.ignored_globs:
		if filename.match(pattern):
			return true
	return false


func _on_ignored_globs_changed(text: String) -> void:
	if not _config:
		return
	_config.ignored_globs.clear()
	for part in text.split(','):
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			_config.ignored_globs.append(trimmed)
	_config.save()
	refresh_file_tree()


func _on_ask_dialog_canceled() -> void:
	if not _pending_new_path.is_empty():
		_config.mark_path_known(_pending_new_path)
		_config.save()
		_set_status('Included new folder: ' + _pending_new_path)
	_pending_new_path = ''

