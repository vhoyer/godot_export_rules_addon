@tool
extends VBoxContainer

signal rules_changed
signal rule_delete_requested

var _config: Resource
var _selected_path: String = ''
var _selected_rule: Resource

@onready var _placeholder: Label = %Placeholder
@onready var _editor_content: VBoxContainer = %EditorContent
@onready var _path_label: Label = %PathLabel
@onready var _tags_flow: HFlowContainer = %TagsFlow
@onready var _new_tag_edit: LineEdit = %NewTagEdit
@onready var _comment_edit: LineEdit = %CommentEdit
@onready var _preset_preview_tree: Tree = %PresetPreviewTree
@onready var _add_rule_button: Button = %AddRuleButton
@onready var _delete_button: Button = %DeleteButton


func _ready() -> void:
	%AddTagButton.pressed.connect(func() -> void: _on_add_tag(_new_tag_edit.text))
	_new_tag_edit.text_submitted.connect(_on_add_tag)
	_comment_edit.text_changed.connect(_on_comment_changed)
	_add_rule_button.pressed.connect(_on_add_rule_pressed)
	_delete_button.pressed.connect(func() -> void: rule_delete_requested.emit())

	_preset_preview_tree.hide_root = true
	_preset_preview_tree.columns = 2
	_preset_preview_tree.set_column_title(0, 'Preset')
	_preset_preview_tree.set_column_title(1, 'Result')
	_preset_preview_tree.set_column_titles_visible(true)

	show_placeholder()


func show_placeholder() -> void:
	_selected_path = ''
	_selected_rule = null
	_placeholder.visible = true
	_editor_content.visible = false


func load_rule(config: Resource, path: String, rule: Resource) -> void:
	_config = config
	_selected_path = path
	_selected_rule = rule
	_placeholder.visible = false
	_editor_content.visible = true
	_refresh_ui()


func _refresh_ui() -> void:
	var display_path := _selected_path + ('/' if _is_directory_path(_selected_path) else '')
	_path_label.text = 'Path: ' + display_path

	_comment_edit.text_changed.disconnect(_on_comment_changed)
	_comment_edit.text = _selected_rule.comment if _selected_rule else ''
	_comment_edit.text_changed.connect(_on_comment_changed)

	_add_rule_button.disabled = _selected_rule != null
	_add_rule_button.tooltip_text = 'A rule already exists for this path' if _selected_rule else ''
	_delete_button.disabled = _selected_rule == null
	_delete_button.tooltip_text = 'No rule exists for this path yet' if not _selected_rule else ''

	_refresh_tags_display()
	_refresh_preset_preview()


func _refresh_tags_display() -> void:
	for child in _tags_flow.get_children():
		child.queue_free()

	if not _selected_rule or _selected_rule.required_tags.is_empty():
		var empty_label := Label.new()
		empty_label.text = '(none — always excluded)'
		empty_label.modulate = Color(1, 0.4, 0.4)
		_tags_flow.add_child(empty_label)
		return

	for tag in _selected_rule.required_tags:
		var tag_container := HBoxContainer.new()
		_tags_flow.add_child(tag_container)

		var tag_label := Label.new()
		tag_label.text = tag
		tag_container.add_child(tag_label)

		var remove_btn := Button.new()
		remove_btn.text = 'x'
		remove_btn.custom_minimum_size = Vector2(24, 0)
		var tag_copy: String = tag
		remove_btn.pressed.connect(func() -> void:
			_selected_rule.required_tags.erase(tag_copy)
			_config.save()
			_refresh_tags_display()
			_refresh_preset_preview()
			rules_changed.emit()
		)
		tag_container.add_child(remove_btn)


func _refresh_preset_preview() -> void:
	_preset_preview_tree.clear()
	if not _selected_rule:
		return
	var root := _preset_preview_tree.create_item()
	root.set_text(0, 'Presets')
	for preset_info in _read_presets_summary():
		var item := _preset_preview_tree.create_item(root)
		item.set_text(0, preset_info['name'] as String)
		var tags: Array[String] = []
		tags.assign(preset_info['tags'])
		var included: bool = _selected_rule.should_include_for_tags(tags)
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
	var file := FileAccess.open('res://export_presets.cfg', FileAccess.READ)
	if not file:
		return result
	var lines := file.get_as_text().split('\n')
	file.close()
	var current_name: String = ''
	var current_tags: Array[String] = []
	var in_preset: bool = false
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with('[preset.') and not trimmed.contains('.options'):
			if in_preset and not current_name.is_empty():
				result.append({'name': current_name, 'tags': current_tags.duplicate()})
			current_name = ''
			current_tags = []
			in_preset = true
		elif trimmed.begins_with('['):
			if in_preset and not current_name.is_empty():
				result.append({'name': current_name, 'tags': current_tags.duplicate()})
			in_preset = false
		elif in_preset and trimmed.begins_with('name='):
			current_name = trimmed.trim_prefix('name=').trim_prefix('"').trim_suffix('"')
		elif in_preset and trimmed.begins_with('custom_features='):
			var raw := trimmed.trim_prefix('custom_features=').trim_prefix('"').trim_suffix('"')
			current_tags = []
			if not raw.is_empty():
				for tag in raw.split(','):
					var cleaned := tag.strip_edges()
					if not cleaned.is_empty():
						current_tags.append(cleaned)
	if in_preset and not current_name.is_empty():
		result.append({'name': current_name, 'tags': current_tags.duplicate()})
	return result


func _is_directory_path(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _ensure_rule_exists() -> Resource:
	if not _selected_rule:
		_selected_rule = _config.add_rule(_selected_path)
	return _selected_rule


func _on_add_rule_pressed() -> void:
	_ensure_rule_exists()
	_refresh_ui()
	rules_changed.emit()


func _on_add_tag(tag: String) -> void:
	tag = tag.strip_edges()
	if tag.is_empty() or _selected_path.is_empty():
		return
	var newly_created := _selected_rule == null
	_ensure_rule_exists()
	if not _selected_rule.required_tags.has(tag):
		_selected_rule.required_tags.append(tag)
		_config.save()
		_refresh_tags_display()
		_refresh_preset_preview()
		if newly_created:
			_refresh_ui()
		rules_changed.emit()
	_new_tag_edit.clear()


func _on_comment_changed(text: String) -> void:
	var newly_created := _selected_rule == null
	_ensure_rule_exists()
	_selected_rule.comment = text
	_config.save()
	if newly_created:
		_refresh_ui()
		rules_changed.emit()
