@tool
extends EditorPlugin

const ExportRulesPanel = preload('res://addons/export_rules/export_rules_panel/export_rules_panel.gd')
const ExportRulesPanelScene = preload('res://addons/export_rules/export_rules_panel/export_rules_panel.tscn')
const ExportPresetsUpdater = preload('res://addons/export_rules/export_presets_updater.gd')
const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')

var _panel: Control
var _config: ExportRulesConfig


func _enter_tree() -> void:
	_config = ExportRulesConfig.new()
	if FileAccess.file_exists(ExportRulesConfig.CONFIG_PATH):
		_config.load_from_json()

	_panel = ExportRulesPanelScene.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)
	(_panel as ExportRulesPanel).setup(_config, self)

	_update_export_presets()

	var filesystem:= EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null

	var filesystem:= EditorInterface.get_resource_filesystem()
	if filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.disconnect(_on_filesystem_changed)


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _panel:
		_panel.visible = visible


func _get_plugin_name() -> String:
	return 'Export Rules'


func _get_plugin_icon() -> Texture2D:
	return load('res://addons/export_rules/assets/icon.svg') as Texture2D


func _build() -> bool:
	_update_export_presets()
	return true


func _update_export_presets() -> void:
	if not _config:
		return
	if _config.rules.is_empty():
		return
	var updater:= ExportPresetsUpdater.new()
	var error:= updater.update(_config)
	if error != OK:
		push_warning('[ExportRules] Failed to update export_presets.cfg')


func _on_filesystem_changed() -> void:
	if _panel:
		(_panel as ExportRulesPanel).check_for_new_folders()
		(_panel as ExportRulesPanel).refresh_file_tree()


func _project_settings_changed() -> void:
	if _panel:
		(_panel as ExportRulesPanel).refresh_file_tree()
