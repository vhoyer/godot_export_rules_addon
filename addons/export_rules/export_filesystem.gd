@tool
extends RefCounted

## Shared filesystem-walking predicates used by ExportPresetsUpdater and
## ExportRulesPanel. All methods are static — this class carries no state.

## Files that are always excluded from export listings and hidden from the
## rules tree, regardless of any rule.
const EXCLUDED_FILES: Array[String] = ['project.godot', 'export_presets.cfg', 'export_rules.json']


## Returns true if `entry_name` should be skipped during any filesystem walk:
##   - dot-prefixed entries (hidden files/dirs, .godot cache, .gdignore itself)
##   - Godot import sidecar files (.import, .uid)
##   - files in EXCLUDED_FILES
## `entry_name` must be the bare filename, not a full path.
static func should_skip_entry(entry_name: String) -> bool:
	if entry_name.begins_with('.'):
		return true
	if entry_name.ends_with('.import') or entry_name.ends_with('.uid'):
		return true
	if entry_name in EXCLUDED_FILES:
		return true
	return false


## Returns true if the directory at `dir_res_path` should be skipped because
## it contains a .gdignore marker file. `dir_res_path` must NOT have a trailing slash.
static func is_ignored_dir(dir_res_path: String) -> bool:
	return FileAccess.file_exists(dir_res_path + '/.gdignore')


## Returns true if `filename` matches any of the given glob patterns.
## `filename` is the bare filename (not a full path).
static func matches_any_glob(filename: String, ignored_globs: Array) -> bool:
	for pattern in ignored_globs:
		if filename.match(pattern):
			return true
	return false
