@tool
extends Control

signal remove_requested

@onready var _tag_label: Label = %TagLabel
@onready var _remove_btn: Button = %RemoveButton


func setup(tag: String) -> void:
	_tag_label.text = tag
	_remove_btn.pressed.connect(func() -> void: remove_requested.emit())
