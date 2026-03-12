@tool
extends VBoxContainer

const TagChip = preload("res://addons/export_rules/export_rules_panel/rule_editor/tag_chip/tag_chip.tscn")

signal rules_changed
signal rule_delete_requested
signal preview_refresh_needed(rule: Resource)

var _config: Resource
var _selected_path: String = ''
var _selected_rule: Resource

@onready var _placeholder: Label = %Placeholder
@onready var _editor_content: VBoxContainer = %EditorContent
@onready var _path_label: Label = %PathLabel
@onready var _tags_flow: HFlowContainer = %TagsFlow
@onready var _new_tag_edit: LineEdit = %NewTagEdit
@onready var _comment_edit: LineEdit = %CommentEdit
@onready var _always_exclude_button: Button = %AlwaysExcludeButton
@onready var _always_include_button: Button = %AlwaysIncludeButton


func _ready() -> void:
	%AddTagButton.pressed.connect(func() -> void: _on_add_tag(_new_tag_edit.text))
	_new_tag_edit.text_submitted.connect(_on_add_tag)
	_comment_edit.text_changed.connect(_on_comment_changed)
	_always_exclude_button.pressed.connect(_on_always_exclude_pressed)
	_always_include_button.pressed.connect(func() -> void: rule_delete_requested.emit())

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

	var already_excluded: bool = _selected_rule != null and _selected_rule.required_tags.is_empty()
	_always_exclude_button.disabled = already_excluded
	_always_exclude_button.tooltip_text = 'Path is already always excluded' if already_excluded else ''
	_always_include_button.disabled = _selected_rule == null
	_always_include_button.tooltip_text = 'No rule exists for this path yet' if not _selected_rule else ''

	_refresh_tags_display()
	preview_refresh_needed.emit(_selected_rule)


func _refresh_tags_display() -> void:
	for child in _tags_flow.get_children():
		child.queue_free()

	if not _selected_rule or _selected_rule.required_tags.is_empty():
		var empty_label := Label.new()
		empty_label.text = '(empty)'
		_tags_flow.add_child(empty_label)
		return

	for tag in _selected_rule.required_tags:
		var chip: Control = TagChip.instantiate()
		_tags_flow.add_child(chip)
		chip.setup(tag)
		var tag_copy: String = tag
		chip.remove_requested.connect(func() -> void:
			_selected_rule.required_tags.erase(tag_copy)
			_config.save()
			_refresh_tags_display()
			preview_refresh_needed.emit(_selected_rule)
			rules_changed.emit()
		)


func _is_directory_path(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _ensure_rule_exists() -> Resource:
	if not _selected_rule:
		_selected_rule = _config.add_rule(_selected_path)
	return _selected_rule


func _on_always_exclude_pressed() -> void:
	_ensure_rule_exists()
	_selected_rule.required_tags.clear()
	_config.save()
	_refresh_ui()
	rules_changed.emit()


func _on_add_tag(tag: String) -> void:
	tag = tag.strip_edges()
	if tag.is_empty() or _selected_path.is_empty():
		return
	_ensure_rule_exists()
	if not _selected_rule.required_tags.has(tag):
		_selected_rule.required_tags.append(tag)
		_config.save()
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
