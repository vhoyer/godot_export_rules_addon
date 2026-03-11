@tool
extends RefCounted

const ExportRulesConfig = preload('res://addons/export_rules/export_rules_config.gd')
const PRESETS_PATH:= 'res://export_presets.cfg'


## Update export_presets.cfg based on the given config rules.
## Returns OK on success, ERR_FILE_NOT_FOUND or ERR_PARSE_ERROR on failure.
func update(config: ExportRulesConfig) -> int:
	if not FileAccess.file_exists(PRESETS_PATH):
		push_error('[ExportRules] export_presets.cfg not found')
		return ERR_FILE_NOT_FOUND

	var cfg:= ConfigFile.new()
	var load_error:= cfg.load(PRESETS_PATH)
	if load_error != OK:
		push_error('[ExportRules] Cannot parse export_presets.cfg: ' + str(load_error))
		return ERR_PARSE_ERROR

	_apply_rules(config, cfg)

	var save_error:= cfg.save(PRESETS_PATH)
	if save_error != OK:
		push_error('[ExportRules] Cannot write export_presets.cfg: ' + str(save_error))
		return ERR_FILE_NOT_FOUND
	return OK


func _apply_rules(config: Resource, cfg: ConfigFile) -> void:
	for section in cfg.get_sections():
		if not _is_preset_section(section):
			continue
		var tags:= _get_preset_tags(cfg, section)
		var excluded_files:= _compute_excluded_files(config, tags)
		cfg.set_value(section, 'export_filter', 'exclude')
		cfg.set_value(section, 'export_files', PackedStringArray(excluded_files))


func _is_preset_section(section: String) -> bool:
	if not section.begins_with('preset.'):
		return false
	var suffix:= section.trim_prefix('preset.')
	return suffix.is_valid_int()


func _get_preset_tags(cfg: ConfigFile, section: String) -> Array[String]:
	var raw:= cfg.get_value(section, 'custom_features', '') as String
	var tags: Array[String] = []
	for tag in raw.split(','):
		var cleaned:= tag.strip_edges()
		if not cleaned.is_empty():
			tags.append(cleaned)
	return tags


## Compute the list of files to exclude for a preset with the given tags.
## - Rules with empty required_tags → always excluded
## - Rules with required_tags → excluded if preset is missing any of those tags
func _compute_excluded_files(config: Resource, preset_tags: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for rule in config.rules:
		if not rule.should_include_for_tags(preset_tags):
			var expanded:= _expand_path(rule.path)
			for file_path in expanded:
				if not result.has(file_path):
					result.append(file_path)
	result.sort()
	return result


## Expand a res:// path to a flat list of all files within it.
## If it's a file, returns [path]. If a folder, recurses.
func _expand_path(res_path: String) -> Array[String]:
	var result: Array[String] = []
	var local_path:= ProjectSettings.globalize_path(res_path)
	if DirAccess.dir_exists_absolute(local_path):
		_collect_files_recursive(res_path, result)
	elif FileAccess.file_exists(res_path):
		result.append(res_path)
	return result


func _collect_files_recursive(dir_res_path: String, result: Array[String]) -> void:
	var dir:= DirAccess.open(dir_res_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name:= dir.get_next()
	while entry_name != '':
		if not entry_name.begins_with('.'):
			var full_res_path:= dir_res_path + '/' + entry_name
			if dir.current_is_dir():
				_collect_files_recursive(full_res_path, result)
			else:
				result.append(full_res_path)
		entry_name = dir.get_next()
	dir.list_dir_end()


## Parse a PackedStringArray(...) line value into an Array of strings.
## Used by the panel for importing existing export_presets.cfg entries.
func parse_packed_string_array(line_value: String) -> Array[String]:
	var result: Array[String] = []
	var start:= line_value.find('PackedStringArray(')
	if start == -1:
		return result
	start += len('PackedStringArray(')
	var end:= line_value.rfind(')')
	if end == -1 or end <= start:
		return result
	var content:= line_value.substr(start, end - start).strip_edges()
	if content.is_empty():
		return result
	if content.begins_with('"'):
		content = content.substr(1)
	if content.ends_with('"'):
		content = content.substr(0, content.length() - 1)
	var parts:= content.split('", "')
	for part in parts:
		if not part.is_empty():
			result.append(part)
	return result
