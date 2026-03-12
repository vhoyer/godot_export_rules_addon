@tool
extends VBoxContainer

@onready var _tree: Tree = %PresetPreviewTree


func _ready() -> void:
	_tree.set_column_title(0, 'Preset')
	_tree.set_column_title(1, 'Result')


func refresh(rule: Resource) -> void:
	_tree.clear()
	var root := _tree.create_item()
	root.set_text(0, 'Presets')
	for preset_info in _read_presets_summary():
		var item := _tree.create_item(root)
		item.set_text(0, preset_info['name'] as String)
		var tags: Array[String] = []
		tags.assign(preset_info['tags'])
		var included: bool = not rule or rule.should_include_for_tags(tags)
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
