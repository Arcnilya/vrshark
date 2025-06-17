extends CharacterBody3D

const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.05
const BASE_FOV = 75.0
const FOV_CHANGE = 1.01
const HOST_SCENE_PATH = "res://scenes/host.tscn"
const PACKET_SCENE_PATH = "res://scenes/packet3.tscn"

var t_bob = 0.0
var speed
var selected_object
var grabbed_object
var showing_info: bool = false
var grab_power = 8
var last_host_outline: MeshInstance3D = null
var last_packet_outline: MeshInstance3D = null
var ctrl_pressed_last_frame = false

@onready var head = $head
@onready var camera = $head/camera
@onready var interaction = $head/camera/ray
@onready var hand = $head/camera/hand

	
func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("left_click"):
		if selected_object == null:
			var collider = interaction.get_collider()
			if collider != null and collider is RigidBody3D:
				selected_object = collider
		elif selected_object != null:
			if selected_object != null:
				selected_object = null


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
func _unhandled_input(event: InputEvent) -> void:
	var ctrl_pressed = Input.is_action_pressed("control")
	if ctrl_pressed and not ctrl_pressed_last_frame:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif not ctrl_pressed and ctrl_pressed_last_frame:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ctrl_pressed_last_frame = ctrl_pressed	
	
	if event is InputEventMouseMotion and not ctrl_pressed:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(60))
		
		
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	#if Input.is_action_just_pressed("jump") and is_on_floor():
		#cvelocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 10.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 10.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
		
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
	
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	var collider = interaction.get_collider()
	if collider == null:
		if last_host_outline: last_host_outline.visible = false
	elif collider.scene_file_path == HOST_SCENE_PATH:
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
	if selected_object != null:
		if selected_object.scene_file_path == HOST_SCENE_PATH:
			# Lift host cube
			var a = selected_object.global_transform.origin
			var b = hand.global_transform.origin
			selected_object.set_linear_velocity((b-a) * grab_power)
		elif selected_object.scene_file_path == PACKET_SCENE_PATH:
			# Highlight packet cube
			var outline = selected_object.get_node_or_null("outline")
			if outline:
				if last_packet_outline and last_packet_outline != outline: # Click new packet
					last_packet_outline.visible = false
				outline.visible = true
				last_packet_outline = outline
	
			

	move_and_slide()
	
func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ) * BOB_AMP
	return pos
