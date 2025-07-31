extends Label3D

@export var height_offset: float = 1.0

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	var parent = get_parent()
	if parent:
		global_position = parent.global_position + Vector3(0, height_offset, 0)
