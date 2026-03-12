@tool
extends Resource

const CONFIG_PATH:= 'res://export_rules.json'
const PathRule = preload('res://addons/export_rules/path_rule.gd')

enum NewFolderPolicy {
	AUTO_INCLUDE = 0,
	AUTO_EXCLUDE = 1,
	ASK = 2,
}

var new_folder_policy: int = NewFolderPolicy.ASK
var rules: Array = []  # Array of PathRule
var known_paths: Array[String] = []  # All paths seen; used to detect new folders


func get_rule_for_path(target_path: String) -> Resource:
	for rule in rules:
		if rule.path == target_path:
			return rule
	return null


func add_rule(target_path: String) -> Resource:
	target_path = target_path.trim_suffix('/')
	var existing:= get_rule_for_path(target_path)
	if existing:
		return existing
	# Remove any child rules — the parent now governs the whole subtree
	var prefix := target_path + '/'
	for i in range(rules.size() - 1, -1, -1):
		if (rules[i].path as String).begins_with(prefix):
			rules.remove_at(i)
	var rule:= PathRule.new()
	rule.path = target_path
	rules.append(rule)
	save()
	return rule


func remove_rule(target_path: String) -> void:
	for i in range(rules.size() - 1, -1, -1):
		if rules[i].path == target_path:
			rules.remove_at(i)
	save()


func mark_path_known(target_path: String) -> void:
	if not known_paths.has(target_path):
		known_paths.append(target_path)


func is_path_known(target_path: String) -> bool:
	return known_paths.has(target_path)


func save() -> void:
	var data: Dictionary = {
		'new_folder_policy': new_folder_policy,
		'known_paths': known_paths,
		'rules': [],
	}
	for rule in rules:
		var rule_data: Dictionary = {
			'path': rule.path,
			'required_tags': rule.required_tags,
			'comment': rule.comment,
		}
		data['rules'].append(rule_data)
	var file:= FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if not file:
		push_error('[ExportRules] Failed to save config to ' + CONFIG_PATH)
		return
	file.store_string(JSON.stringify(data, '\t'))
	file.close()


func load_from_json() -> void:
	var file:= FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return
	var content:= file.get_as_text()
	file.close()
	var parsed:= JSON.parse_string(content)
	if not parsed is Dictionary:
		push_error('[ExportRules] Failed to parse config JSON')
		return
	var data:= parsed as Dictionary
	if data.has('new_folder_policy'):
		new_folder_policy = data['new_folder_policy'] as int
	if data.has('known_paths'):
		known_paths.clear()
		var raw_known: Array = data['known_paths'] as Array
		for p in raw_known:
			known_paths.append(p as String)
	if data.has('rules'):
		rules.clear()
		for rule_data: Dictionary in data['rules']:
			var rule:= PathRule.new()
			rule.path = rule_data.get('path', '') as String
			var tags: Array = rule_data.get('required_tags', []) as Array
			rule.required_tags.assign(tags)
			rule.comment = rule_data.get('comment', '') as String
			rules.append(rule)
