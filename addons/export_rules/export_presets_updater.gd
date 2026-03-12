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
		var resource_files: Array[String] = []
		var non_resource_files: Array[String] = []
		_compute_included_files(config, tags, resource_files, non_resource_files)
		cfg.set_value(section, 'export_filter', 'resources')
		cfg.set_value(section, 'export_files', PackedStringArray(resource_files))
		cfg.set_value(section, 'include_filter', ','.join(non_resource_files))
		cfg.set_value(section, 'exclude_filter', ','.join(config.ignored_globs))


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


## Walks all project files and populates resource_files (for export_files=) and
## non_resource_files (for include_filter=) based on rules and preset tags.
func _compute_included_files(config: Resource, preset_tags: Array[String], resource_files: Array[String], non_resource_files: Array[String]) -> void:
	_collect_included_recursive('res://', config.rules, config.ignored_globs, preset_tags, resource_files, non_resource_files)
	resource_files.sort()
	non_resource_files.sort()


func _collect_included_recursive(dir_res_path: String, rules: Array, ignored_globs: Array, preset_tags: Array[String], resource_files: Array[String], non_resource_files: Array[String]) -> void:
	var dir:= DirAccess.open(dir_res_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name:= dir.get_next()
	while entry_name != '':
		if not entry_name.begins_with('.'):
			var full_res_path: String
			if dir_res_path.ends_with('/'):
				full_res_path = dir_res_path + entry_name
			else:
				full_res_path = dir_res_path + '/' + entry_name
			if dir.current_is_dir():
				if not _is_ignored_dir(full_res_path):
					_collect_included_recursive(full_res_path, rules, ignored_globs, preset_tags, resource_files, non_resource_files)
			elif not entry_name.ends_with('.import') and not entry_name.ends_with('.uid'):
				if not _matches_any_glob(entry_name, ignored_globs):
					var rule = _find_matching_rule(full_res_path, rules)
					if rule == null or rule.should_include_for_tags(preset_tags):
						if ResourceLoader.exists(full_res_path):
							resource_files.append(full_res_path)
						else:
							non_resource_files.append(full_res_path.trim_prefix('res://'))
		entry_name = dir.get_next()
	dir.list_dir_end()


func _matches_any_glob(filename: String, ignored_globs: Array) -> bool:
	for pattern in ignored_globs:
		if filename.match(pattern):
			return true
	return false


func _is_ignored_dir(dir_res_path: String) -> bool:
	return FileAccess.file_exists(dir_res_path + '/.gdignore')


func _find_matching_rule(file_path: String, rules: Array):
	for rule in rules:
		var rule_path:= rule.path.rstrip('/') as String
		if file_path == rule_path or file_path.begins_with(rule_path + '/'):
			return rule
	return null
