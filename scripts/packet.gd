extends RigidBody3D

var source
var destination
var playback_speed: float = 1.0
var packet_speed: float = 5.0
var paused: bool = false
var reversed: bool = false
var player: CharacterBody3D


func move(source_host, destination_host, base_packet_speed: float, playback_speed_factor: float):
	source = source_host
	destination = destination_host
	playback_speed = playback_speed_factor
	packet_speed = base_packet_speed
	set_process(true)
	
func _on_pause_changed(value: bool):
	paused = value
func _on_reverse_changed(value: bool):
	reversed = value

func _process(delta: float) -> void:
	if player:
		var panel := get_node("outline/panel")
		var head_pos = player.get_node("head").global_transform.origin
		var packet_pos = global_transform.origin

		var to_player = (head_pos - packet_pos).normalized()
		var right = Vector3.UP.cross(to_player).normalized()
		var offset = right * 0.2 + Vector3.UP * 0.15

		var panel_pos = packet_pos + offset
		panel.global_transform.origin = panel_pos

		var forward = (head_pos - panel_pos).normalized()
		var up = Vector3.UP
		if abs(forward.dot(up)) > 0.99:
			up = Vector3.FORWARD 
				
		var original_scale = panel.global_transform.basis.get_scale()
		var basis = Basis().looking_at(forward, up).scaled(original_scale)
		panel.global_transform = Transform3D(basis, panel_pos)

	
	if not paused:
		var dst = source.global_position if reversed else destination.global_position
		var direction = (dst - global_position).normalized()
		global_position += direction * packet_speed * playback_speed * delta
		if global_position.distance_to(dst) < 0.5:
			queue_free()
