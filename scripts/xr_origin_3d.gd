extends XROrigin3D

const HOST_SCENE = "res://scenes/host-vr.tscn"
const PACKET_SCENE = "res://scenes/packet.tscn"

@onready var interaction_left = $LeftHand/RayCast3D # $head/camera/ray
@onready var interaction_right = $RightHand/RayCast3D

var selected_object
var grabbed_object
var showing_info: bool = false
var last_outline: MeshInstance3D = null
var do_vibrate = true
#var last_packet_outline: MeshInstance3D = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func vibrate(controllers) -> void:
	for controller in controllers:
		controller.trigger_haptic_pulse("haptic", 30, 0.3, 0.1, 0.0)
		
func is_laser_on(controllers) -> bool:
	return controllers.any(func(c): return c.show_laser)

func process_collider_outline() -> void:
	var obj_collider: Node3D = null
	var collider = null

	var interactions = []
	collider = interaction_left.get_collider()
	if collider and (collider.scene_file_path == HOST_SCENE or collider.scene_file_path == PACKET_SCENE):
		obj_collider = collider
		interactions.append($LeftHand)
	collider = interaction_right.get_collider()
	if collider and (collider.scene_file_path == HOST_SCENE or collider.scene_file_path == PACKET_SCENE):
		obj_collider = collider
		interactions.append($RightHand)
			
	if obj_collider and is_laser_on(interactions):
		var outline = obj_collider.get_node_or_null("outline")
		if outline:
			if last_outline:
				if last_outline != outline:
					vibrate(interactions)
					last_outline.visible = false
			else:
				vibrate(interactions)
			outline.visible = true
			last_outline = outline
	else:
		if last_outline:
			last_outline.visible = false
			last_outline = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	process_collider_outline()
