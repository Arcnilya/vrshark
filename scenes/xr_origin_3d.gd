extends XROrigin3D

const HOST_SCENE = "res://scenes/host-vr.tscn"
const PACKET_SCENE = "res://scenes/packet.tscn"

@onready var interaction = $LeftHand/RayCast3D # $head/camera/ray

var selected_object
var grabbed_object
var showing_info: bool = false
var last_host_outline: MeshInstance3D = null
var last_packet_outline: MeshInstance3D = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var collider = interaction.get_collider()
	if collider == null:
		if last_host_outline: last_host_outline.visible = false
	elif collider.scene_file_path == HOST_SCENE:
		# Highlight host cube
		var outline = collider.get_node_or_null("outline")
		if outline:
			if last_host_outline and last_host_outline != outline:
				last_host_outline.visible = false
			outline.visible = true
			last_host_outline = outline
	else:
		if last_host_outline: last_host_outline.visible = false
	
	# When left_click
	# TODO: Implement packet details toggle
	if selected_object != null:
		if selected_object.scene_file_path == PACKET_SCENE:
			# Highlight packet cube
			var outline = selected_object.get_node_or_null("outline")
			if outline:
				if last_packet_outline and last_packet_outline != outline: # Click new packet
					last_packet_outline.visible = false
				outline.visible = !outline.visible
				last_packet_outline = outline
				selected_object = null
