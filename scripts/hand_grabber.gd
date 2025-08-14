extends XRController3D

@onready var grab_anchor: Node3D = $GrabAnchor
@onready var grab_area: Area3D = $GrabAnchor/GrabArea

var _candidates: Array[RigidBody3D] = []
var _held: RigidBody3D = null
var _offset: Transform3D

func _ready():
	grab_area.body_entered.connect(_on_body_entered)
	grab_area.body_exited.connect(_on_body_exited)
	#button_pressed.connect(_on_button_pressed)
	#button_released.connect(_on_button_released)

func _on_body_entered(b):
	if b is RigidBody3D and b.is_in_group("grabbable"):
		_candidates.append(b)

func _on_body_exited(b):
	if b is RigidBody3D:
		_candidates.erase(b)

func _on_button_pressed(name: StringName):
	if name == &"index_pinch":
		_try_grab()

func _on_button_released(name: StringName):
	if name == &"index_pinch":
		_release()

func _physics_process(_delta):
	if _held:
		_held.global_transform = grab_anchor.global_transform * _offset

func _try_grab():
	if _held or _candidates.is_empty():
		return
	var anchor_pos := grab_anchor.global_transform.origin
	_candidates.sort_custom(func(a, b):
		return a.global_transform.origin.distance_to(anchor_pos) < b.global_transform.origin.distance_to(anchor_pos)
	)
	_held = _candidates[0]
	_held.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_held.freeze = true
	_offset = grab_anchor.global_transform.affine_inverse() * _held.global_transform

func _release():
	_held = null
