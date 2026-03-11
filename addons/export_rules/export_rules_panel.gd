@tool
extends VBoxContainer

const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')
const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PathRule = preload('res://addons/export_rules/path_rule.gd')

var _config: ExportRulesConfig
var _plugin: EditorPlugin
var _selected_rule: Resource  # PathRule or null
var _selected_path: String = ''
var _pending_new_path: String = ''
var _known_folders_cache: Array[String] = []

# Dynamic editor nodes — rebuilt on each selection change
var _editor_path_label: Label
var _tags_flow: HFlowContainer
var _new_tag_edit: LineEdit
var _preset_preview_tree: Tree

@onready
var _rules_tree: Tree = %RulesTree
@onready
var _editor_container: VBoxContainer = %EditorContainer
@onready
var _status_label: Label = %StatusLabel
@onready
var _new_folder_policy_option: OptionButton = %NewFolderPolicyOption
@onready
var _file_dialog: EditorFileDialog = %FileDialog
@onready
var _ask_dialog: ConfirmationDialog = %AskDialog


func _ready() -> void:
	%UpdateButton.pressed.connect(_on_update_pressed)
	%ScanButton.pressed.connect(_on_scan_pressed)
	%ImportButton.pressed.connect(_on_import_pressed)
	%AddFolderButton.pressed.connect(_on_add_folder_pressed)
	%AddFileButton.pressed.connect(_on_add_file_pressed)
	%RemoveButton.pressed.connect(_on_remove_rule_pressed)
	_rules_tree.item_selected.connect(_on_rule_selected)
	_new_folder_policy_option.item_selected.connect(_on_policy_changed)
	_file_dialog.file_selected.connect(_on_file_dialog_selected)
	_file_dialog.dir_selected.connect(_on_file_dialog_selected)
	_ask_dialog.confirmed.connect(_on_ask_dialog_confirmed)
	_ask_dialog.canceled.connect(_on_ask_dialog_canceled)

	_rules_tree.set_column_title(0, 'Path')
	_rules_tree.set_column_title(1, 'Required Tags')
	_rules_tree.set_column_title(2, 'Status')
	_rules_tree.set_column_titles_visible(true)
	_rules_tree.set_column_expand(0, true)
	_rules_tree.set_column_expand(1, true)
	_rules_tree.set_column_expand(2, false)
	_rules_tree.set_column_custom_minimum_width(2, 140)

	_new_folder_policy_option.clear()
	_new_folder_policy_option.add_item('Auto Include', ExportRulesConfig.NewFolderPolicy.AUTO_INCLUDE)
	_new_folder_policy_option.add_item('Auto Exclude', ExportRulesConfig.NewFolderPolicy.AUTO_EXCLUDE)
	_new_folder_policy_option.add_item('Ask', ExportRulesConfig.NewFolderPolicy.ASK)

	_build_editor_placeholder()


func setup(config: Resource, plugin: EditorPlugin) -> void:
	_config = config
	_plugin = plugin
	_new_folder_policy_option.selected = _config.new_folder_policy
	_snapshot_known_folders()
	refresh_file_tree()
	_refresh_preset_preview()


func _build_editor_placeholder() -> void:
	_clear_editor()
	var placeholder:= Label.new()
	placeholder.text = 'Select a rule to edit it.'
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_container.add_child(placeholder)


func _build_rule_editor(path: String, rule: Resource) -> void:
	_clear_editor()

	_editor_path_label = Label.new()
	var display_path: String = path + ('/' if _is_directory_path(path) else '')
	_editor_path_label.text = 'Path: ' + display_path
	_editor_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_container.add_child(_editor_path_label)

	var tags_title:= Label.new()
	tags_title.text = 'Required Feature Tags:'
	_editor_container.add_child(tags_title)

	var tags_hint:= Label.new()
	tags_hint.text = 'Path is included only in presets that have ALL of these tags.\nLeave empty to always exclude from all presets.'
	tags_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tags_hint.modulate = Color(1, 1, 1, 0.6)
	_editor_container.add_child(tags_hint)

	_tags_flow = HFlowContainer.new()
	_tags_flow.custom_minimum_size.y = 40
	_editor_container.add_child(_tags_flow)
	_refresh_tags_display(rule)

	var add_tag_row:= HBoxContainer.new()
	_editor_container.add_child(add_tag_row)

	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = 'Tag name (e.g. steam, demo)'
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(_on_add_tag)
	add_tag_row.add_child(_new_tag_edit)

	var add_tag_btn:= Button.new()
	add_tag_btn.text = 'Add Tag'
	add_tag_btn.pressed.connect(func() -> void: _on_add_tag(_new_tag_edit.text))
	add_tag_row.add_child(add_tag_btn)

	var sep2:= HSeparator.new()
	_editor_container.add_child(sep2)

	var comment_label:= Label.new()
	comment_label.text = 'Comment:'
	_editor_container.add_child(comment_label)

	var comment_edit:= LineEdit.new()
	comment_edit.text = rule.comment if rule else ''
	comment_edit.placeholder_text = 'Optional description'
	comment_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comment_edit.text_changed.connect(func(text: String) -> void:
		var target_rule: Resource = _ensure_rule_exists()
		target_rule.comment = text
		_config.save()
	)
	_editor_container.add_child(comment_edit)

	var sep3:= HSeparator.new()
	_editor_container.add_child(sep3)

	var preview_label:= Label.new()
	preview_label.text = 'Export Preset Preview:'
	_editor_container.add_child(preview_label)

	_preset_preview_tree = Tree.new()
	_preset_preview_tree.hide_root = true
	_preset_preview_tree.columns = 2
	_preset_preview_tree.set_column_title(0, 'Preset')
	_preset_preview_tree.set_column_title(1, 'Result')
	_preset_preview_tree.set_column_titles_visible(true)
	_preset_preview_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preset_preview_tree.custom_minimum_size.y = 120
	_editor_container.add_child(_preset_preview_tree)

	_refresh_preset_preview_for_rule(rule)

	var sep_bottom:= HSeparator.new()
	_editor_container.add_child(sep_bottom)

	var rule_actions:= HBoxContainer.new()
	_editor_container.add_child(rule_actions)

	var add_rule_button:= Button.new()
	add_rule_button.text = 'Add Rule'
	add_rule_button.pressed.connect(func() -> void:
		_ensure_rule_exists()
		_build_rule_editor(_selected_path, _selected_rule)
	)
	if _selected_rule:
		add_rule_button.disabled = true
		add_rule_button.tooltip_text = 'A rule already exists for this path'
	rule_actions.add_child(add_rule_button)

	var delete_button:= Button.new()
	delete_button.text = 'Delete Rule'
	delete_button.pressed.connect(_on_remove_rule_pressed)
	if not _selected_rule:
		delete_button.disabled = true
		delete_button.tooltip_text = 'No rule exists for this path yet'
	rule_actions.add_child(delete_button)


func _ensure_rule_exists() -> Resource:
	if not _selected_rule:
		_selected_rule = _config.add_rule(_selected_path)
		refresh_file_tree()
	return _selected_rule


func _clear_editor() -> void:
	for child in _editor_container.get_children():
		child.queue_free()


func _refresh_tags_display(rule: Resource) -> void:
	for child in _tags_flow.get_children():
		child.queue_free()

	if not rule or rule.required_tags.is_empty():
		var empty_label:= Label.new()
		empty_label.text = '(none — always excluded)'
		empty_label.modulate = Color(1, 0.4, 0.4)
		_tags_flow.add_child(empty_label)
		return

	for tag in rule.required_tags:
		var tag_container:= HBoxContainer.new()
		_tags_flow.add_child(tag_container)

		var tag_label:= Label.new()
		tag_label.text = tag
		tag_container.add_child(tag_label)

		var remove_btn:= Button.new()
		remove_btn.text = 'x'
		remove_btn.custom_minimum_size = Vector2(24, 0)
		var tag_copy: String = tag
		remove_btn.pressed.connect(func() -> void:
			rule.required_tags.erase(tag_copy)
			_config.save()
			_refresh_tags_display(rule)
			refresh_file_tree()
			_refresh_preset_preview_for_rule(rule)
		)
		tag_container.add_child(remove_btn)


func refresh_file_tree() -> void:
	if not _rules_tree or not _config:
		return
	_rules_tree.clear()
	var root:= _rules_tree.create_item()
	var folder_items: Dictionary = {}
	var sorted_rules: Array = _config.rules.duplicate()
	sorted_rules.sort_custom(func(a: Resource, b: Resource) -> bool:
		return _natural_less_than(a.path, b.path)
	)
	for rule in sorted_rules:
		var short_path: String = rule.path.trim_prefix('res://')
		var segments: PackedStringArray = short_path.split('/')
		var parent: TreeItem = root
		var accumulated: String = ''
		for segment_index in range(segments.size() - 1):
			var segment: String = segments[segment_index]
			accumulated += ('' if accumulated.is_empty() else '/') + segment
			if not folder_items.has(accumulated):
				var folder_item: TreeItem = _rules_tree.create_item(parent)
				folder_item.set_text(0, segment + '/')
				folder_item.set_collapsed(false)
				folder_item.set_metadata(0, 'res://' + accumulated)
				folder_items[accumulated] = folder_item
			parent = folder_items[accumulated] as TreeItem
		var item: TreeItem
		if folder_items.has(short_path):
			item = folder_items[short_path] as TreeItem
		else:
			var last_segment: String = segments[segments.size() - 1]
			var is_dir: bool = _is_directory_path(rule.path)
			item = _rules_tree.create_item(parent)
			item.set_text(0, last_segment + ('/' if is_dir else ''))
			folder_items[short_path] = item
		item.set_tooltip_text(0, rule.path)
		item.set_text(1, ', '.join(rule.required_tags) if not rule.required_tags.is_empty() else '(none)')
		item.set_text(2, rule.get_status_label())
		if rule.required_tags.is_empty():
			item.set_custom_color(2, Color(1, 0.4, 0.4))
		else:
			item.set_custom_color(2, Color(0.4, 1, 0.4))
		item.set_metadata(0, rule.path)
	_rules_tree.set_column_expand(0, true)


func _refresh_preset_preview() -> void:
	if _selected_rule and is_instance_valid(_preset_preview_tree):
		_refresh_preset_preview_for_rule(_selected_rule)


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


func _is_directory_path(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _refresh_preset_preview_for_rule(rule: Resource) -> void:
	if not _preset_preview_tree or not rule:
		return
	_preset_preview_tree.clear()
	var root:= _preset_preview_tree.create_item()
	root.set_text(0, 'Presets')
	var presets:= _read_presets_summary()
	for preset_info in presets:
		var item:= _preset_preview_tree.create_item(root)
		item.set_text(0, preset_info['name'] as String)
		var tags:= preset_info['tags'] as Array[String]
		var included: bool = rule.should_include_for_tags(tags)
		if included:
			item.set_text(1, 'Included')
			item.set_custom_color(1, Color(0.4, 1, 0.4))
		else:
			item.set_text(1, 'Excluded')
			item.set_custom_color(1, Color(1, 0.4, 0.4))


func _read_presets_summary() -> Array:
	var result: Array = []
	if not FileAccess.file_exists('res://export_presets.cfg'):
		return result
	var file:= FileAccess.open('res://export_presets.cfg', FileAccess.READ)
	if not file:
		return result
	var lines:= file.get_as_text().split('\n')
	file.close()
	var current_name: String = ''
	var current_tags: Array[String] = []
	var in_preset: bool = false
	for line in lines:
		var trimmed:= line.strip_edges()
		if trimmed.begins_with('[preset.') and not trimmed.contains('.options'):
			if in_preset and not current_name.is_empty():
				result.append({'name': current_name, 'tags': current_tags})
			current_name = ''
			current_tags = []
			in_preset = true
		elif trimmed.begins_with('['):
			in_preset = false
		elif in_preset and trimmed.begins_with('name='):
			current_name = trimmed.trim_prefix('name=').trim_prefix('"').trim_suffix('"')
		elif in_preset and trimmed.begins_with('custom_features='):
			var raw:= trimmed.trim_prefix('custom_features=').trim_prefix('"').trim_suffix('"')
			current_tags = []
			if not raw.is_empty():
				for tag in raw.split(','):
					var cleaned:= tag.strip_edges()
					if not cleaned.is_empty():
						current_tags.append(cleaned)
	if in_preset and not current_name.is_empty():
		result.append({'name': current_name, 'tags': current_tags})
	return result


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


func _find_next_path_after_removal(removed_path: String) -> String:
	var sorted: Array = _config.rules.duplicate()
	sorted.sort_custom(func(a: Resource, b: Resource) -> bool:
		return _natural_less_than(a.path, b.path)
	)
	for i in range(sorted.size()):
		if sorted[i].path == removed_path:
			if i + 1 < sorted.size():
				return sorted[i + 1].path as String
			elif i - 1 >= 0:
				return sorted[i - 1].path as String
			return ''
	return ''


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
	check_for_new_folders()
	_set_status('Scan complete.')


func _on_import_pressed() -> void:
	_import_from_current_presets()


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
		_build_editor_placeholder()
		return
	_selected_path = selected.get_metadata(0) as String
	_selected_rule = _config.get_rule_for_path(_selected_path)
	_build_rule_editor(_selected_path, _selected_rule)


func _on_add_folder_pressed() -> void:
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.title = 'Select Folder to Add Rule For'
	_file_dialog.popup_centered(Vector2i(800, 600))


func _on_add_file_pressed() -> void:
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = 'Select File to Add Rule For'
	_file_dialog.popup_centered(Vector2i(800, 600))


func _on_file_dialog_selected(selected_path: String) -> void:
	if selected_path.is_empty():
		return
	var project_path:= ProjectSettings.globalize_path('res://')
	if selected_path.begins_with(project_path):
		selected_path = 'res://' + selected_path.trim_prefix(project_path)
	if not selected_path.begins_with('res://'):
		_set_status('Error: path must be inside the project directory.')
		return
	_config.add_rule(selected_path)
	refresh_file_tree()
	_set_status('Rule added for: ' + selected_path)


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
	var next_path: String = _find_next_path_after_removal(removed_path)
	_config.remove_rule(removed_path)
	_selected_rule = null
	_selected_path = ''
	refresh_file_tree()
	if not next_path.is_empty():
		var next_item: TreeItem = _find_tree_item_by_path(next_path)
		if next_item:
			next_item.select(0)
			_on_rule_selected()
			_set_status('Rule removed for: ' + removed_path)
			return
	_build_editor_placeholder()
	_set_status('Rule removed for: ' + removed_path)


func _on_add_tag(tag: String) -> void:
	tag = tag.strip_edges()
	if tag.is_empty() or _selected_path.is_empty():
		return
	var rule: Resource = _ensure_rule_exists()
	if not rule.required_tags.has(tag):
		rule.required_tags.append(tag)
		_config.save()
		_refresh_tags_display(rule)
		refresh_file_tree()
		_refresh_preset_preview_for_rule(rule)
	if _new_tag_edit:
		_new_tag_edit.clear()


func _on_ask_dialog_confirmed() -> void:
	if not _pending_new_path.is_empty():
		_config.add_rule(_pending_new_path)
		_config.mark_path_known(_pending_new_path)
		refresh_file_tree()
		_set_status('Excluded new folder: ' + _pending_new_path)
	_pending_new_path = ''


func _on_ask_dialog_canceled() -> void:
	if not _pending_new_path.is_empty():
		_config.mark_path_known(_pending_new_path)
		_config.save()
		_set_status('Included new folder: ' + _pending_new_path)
	_pending_new_path = ''


func _import_from_current_presets() -> void:
	if not FileAccess.file_exists('res://export_presets.cfg'):
		_set_status('No export_presets.cfg found.')
		return
	var file:= FileAccess.open('res://export_presets.cfg', FileAccess.READ)
	if not file:
		_set_status('Cannot read export_presets.cfg.')
		return
	var lines:= file.get_as_text().split('\n')
	file.close()

	var all_excluded_paths: Array[String] = []
	for line in lines:
		var trimmed:= line.strip_edges()
		if trimmed.begins_with('export_files='):
			var updater:= ExportPresetsUpdater.new()
			var files:= updater.parse_packed_string_array(trimmed.trim_prefix('export_files='))
			for file_path in files:
				if not all_excluded_paths.has(file_path):
					all_excluded_paths.append(file_path)
			break

	var folder_counts: Dictionary = {}
	for file_path in all_excluded_paths:
		var folder: String = file_path.get_base_dir()
		if not folder_counts.has(folder):
			folder_counts[folder] = 0
		folder_counts[folder] += 1

	var imported_count: int = 0
	var folders_with_many: Array[String] = []
	for folder in folder_counts:
		if (folder_counts[folder] as int) >= 3:
			folders_with_many.append(folder as String)

	for folder in folders_with_many:
		if not _config.get_rule_for_path(folder):
			_config.add_rule(folder)
			imported_count += 1

	for file_path in all_excluded_paths:
		var folder: String = file_path.get_base_dir()
		if not folders_with_many.has(folder):
			if not _config.get_rule_for_path(file_path):
				_config.add_rule(file_path)
				imported_count += 1

	_config.save()
	refresh_file_tree()
	_set_status('Imported %d rules from export_presets.cfg. Assign tags to customize.' % imported_count)
