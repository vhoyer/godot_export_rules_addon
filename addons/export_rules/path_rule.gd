@tool
extends Resource

## The project-relative path this rule applies to (folder or file, e.g. res://stages/levels/prototype)
var path: String = ''

## Tags required for this path to be included in an export preset.
## Empty = always excluded from all presets.
## Non-empty = included only in presets that have ALL of these tags.
var required_tags: Array[String] = []

## Human-readable comment for this rule
var comment: String = ''


func should_include_for_tags(preset_tags: Array[String]) -> bool:
	if required_tags.is_empty():
		return false
	for tag in required_tags:
		if not preset_tags.has(tag):
			return false
	return true


func get_status_label() -> String:
	if required_tags.is_empty():
		return 'Always Excluded'
	return 'Required: ' + ', '.join(required_tags)
