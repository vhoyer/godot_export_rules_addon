extends GutTest

const ExportFilesystem = preload('res://addons/export_rules/export_filesystem.gd')


# --- is_ignored_dir ---

func test_regular_dir_is_not_ignored() -> void:
	assert_false(ExportFilesystem.is_ignored_dir('res://scenes'))


func test_dotgodot_dir_is_ignored() -> void:
	# .godot/ contains a .gdignore (and is itself dot-prefixed, so doubly ignored)
	assert_true(ExportFilesystem.is_ignored_dir('res://.godot'))


func test_regular_dir_with_gdignore_is_ignored() -> void:
	assert_true(ExportFilesystem.is_ignored_dir('res://test/fixtures/gdignored'))


# --- should_skip_entry ---

func test_dot_prefixed_entry_is_skipped() -> void:
	assert_true(ExportFilesystem.should_skip_entry('.gdignore'))


func test_import_file_is_skipped() -> void:
	assert_true(ExportFilesystem.should_skip_entry('texture.png.import'))


func test_uid_file_is_skipped() -> void:
	assert_true(ExportFilesystem.should_skip_entry('scene.tscn.uid'))


func test_excluded_file_project_godot_is_skipped() -> void:
	assert_true(ExportFilesystem.should_skip_entry('project.godot'))


func test_regular_gd_file_is_not_skipped() -> void:
	assert_false(ExportFilesystem.should_skip_entry('my_script.gd'))


func test_regular_dir_name_is_not_skipped() -> void:
	assert_false(ExportFilesystem.should_skip_entry('entities'))


# --- matches_any_glob ---

func test_filename_matching_glob_returns_true() -> void:
	assert_true(ExportFilesystem.matches_any_glob('file.Zone.Identifier', ['*Zone.Identifier']))


func test_filename_not_matching_glob_returns_false() -> void:
	assert_false(ExportFilesystem.matches_any_glob('file.gd', ['*Zone.Identifier']))


func test_empty_globs_never_matches() -> void:
	assert_false(ExportFilesystem.matches_any_glob('anything.gd', []))
