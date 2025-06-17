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
	if not paused:
		var dst = source.global_position if reversed else destination.global_position
		var direction = (dst - global_position).normalized()
		global_position += direction * packet_speed * playback_speed * delta
		if global_position.distance_to(dst) < 0.5:
			queue_free()
