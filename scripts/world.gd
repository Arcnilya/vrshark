extends Node3D

signal pause_changed(paused: bool)
signal reverse_changed(reversed: bool)

@onready var file_dialog := $FileDialog
@export var playback_speed: float = 1.0
@export var packet_speed: float = 5.0

var packet_reader = PacketReader.new()
var hosts = {} # Stored MAC -> host instance mapping
var hosts_location = {}
var current_index = -1
var is_paused = false
var is_reversed = false

const PACKET_SCENE = "res://scenes/packet.tscn"
const HOST_SCENE = "res://scenes/host-vr.tscn"
const PCAP_FILE = "res://pcaps/web.pcap"

# XR stuff
signal focus_lost
signal focus_gained
signal pose_recentered
@export var maximum_refresh_rate : int = 90
var xr_interface : OpenXRInterface
var xr_is_focussed = false
@onready var left_controller := get_node("XROrigin3D/LeftHand")
@onready var right_controller := get_node("XROrigin3D/RightHand")


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR instantiated successfully.")
		var vp : Viewport = get_viewport()
		# Enable XR on our viewport
		vp.use_xr = true
		# Make sure v-sync is off, v-sync is handled by OpenXR
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Enable VRS
		if RenderingServer.get_rendering_device():
			vp.vrs_mode = Viewport.VRS_XR
		elif int(ProjectSettings.get_setting("xr/openxr/foveation_level")) == 0:
			push_warning("OpenXR: Recommend setting Foveation level to High in Project Settings")
		 # Connect the OpenXR events
		xr_interface.session_begun.connect(_on_openxr_session_begun)
		xr_interface.session_visible.connect(_on_openxr_visible_state)
		xr_interface.session_focussed.connect(_on_openxr_focused_state)
		xr_interface.session_stopping.connect(_on_openxr_stopping)
		xr_interface.pose_recentered.connect(_on_openxr_pose_recentered)
		
		# For controllers
		#left_controller.ax_button_pressed.connect(_on_ax_button_left)
		#left_controller.by_button_pressed.connect(_on_by_button_left)
		#right_controller.ax_button_pressed.connect(_on_ax_button_right)
		#right_controller.by_button_pressed.connect(_on_by_button_right)
		
		switch_to_ar()
	else:
		# We couldn't start OpenXR.
		print("OpenXR not instantiated!")
		get_tree().quit()
		
	# Read pcap file
	packet_reader.read_pcap(PCAP_FILE)
	spawn_hosts()
	
func _process(delta: float) -> void:
	# For controllers
	"""
	var left_label = get_node("XROrigin3D/LeftHand/ProgressLabel")
	left_label.text = "%s/%s" % [current_index+1, packet_reader.packets.size()]
	var right_label = get_node("XROrigin3D/RightHand/PauseLabel")
	right_label.visible = is_paused
	"""
	if Input.is_action_just_pressed("escape"):
		toggle_pause()
	for host in hosts_location:
		if hosts_location[host].distance_to(host.position) > 35.0:
			host.position = hosts_location[host]
	
		
func _on_by_button_left() -> void: # Step forward
	if is_packet_in_transit():
		return
	if is_reversed == true and current_index != -1:
		current_index -= 1
	is_reversed = false
	emit_signal("reverse_changed", is_reversed)
	process_packet()
	
func _on_ax_button_left() -> void: # Step backward
	if is_packet_in_transit():
		return
	if is_reversed == false:
		current_index += 1
	is_reversed = true
	emit_signal("reverse_changed", is_reversed)
	process_packet()
	
func _on_by_button_right() -> void: # Toggle pause/resume
	is_paused = !is_paused	
	emit_signal("pause_changed", is_paused)
	
func _on_ax_button_right() -> void:
	# Toggle host mesh visibility
	for host in hosts_location:
		var mesh = host.get_node_or_null("MeshInstance3D")
		if mesh:
			mesh.visible = !mesh.visible

		
func is_packet_in_transit():
	for child in get_children():
		if child.scene_file_path == PACKET_SCENE:
			return true
	return false
		
func toggle_pause():
	if get_tree().paused:
		resume_game()
	else:
		pause_game()
		
func resume_game():
		get_tree().paused = false
		$HUD/PauseMenu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
func pause_game():
		get_tree().paused = true
		$HUD/PauseMenu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_button_pressed() -> void: 
	resume_game() # "Close" button in PauseMenu
	
func get_hosts(src, dst):
	var tmp = []
	if src in hosts:
		tmp.append(hosts[src])
	elif src == "ff:ff:ff:ff:ff:ff":
		for mac in hosts.keys():
			if mac != dst:
				tmp.append(hosts[mac])
	return tmp
		
func process_packet():
	if is_paused:
		return
	if is_reversed:
		current_index -= 1
		if current_index < 0:
			print("Playback complete, reached start")
			current_index = -1
			return	
	else:
		current_index += 1
		if current_index >= packet_reader.packets.size():
			print("Playback complete, reached end")
			current_index = packet_reader.packets.size()-1
			return

	var pkt = packet_reader.packets[current_index]
	if pkt.ethernet:
		var src_mac = pkt.ethernet.src_mac
		var dst_mac = pkt.ethernet.dst_mac
				
		if is_reversed: # Flip dst and src
			var tmp = src_mac
			src_mac = dst_mac
			dst_mac = tmp
			
		var source_hosts = get_hosts(src_mac, dst_mac)
		var destination_hosts = get_hosts(dst_mac, src_mac)
					
		for dst_host in destination_hosts:
			for src_host in source_hosts:
				var distance = src_host.global_position.distance_to(dst_host.global_position)
				var travel_time = distance / (packet_speed * playback_speed)
				spawn_packet(src_host, dst_host, pkt)
		
func extract_hosts():
	var extracted_hosts = {}
	for pkt in packet_reader.packets:
		if pkt.ethernet and pkt.ip:
			var src_mac = pkt.ethernet.src_mac
			var src_ip = pkt.ip.src_ip
			if not extracted_hosts.has(src_mac):
				extracted_hosts[src_mac] = src_ip
	return extracted_hosts

func spawn_hosts():
	var extracted_hosts = extract_hosts()
	var host_keys = extracted_hosts.keys()
	for i in range(host_keys.size()):
		var src_mac = host_keys[i]
		var src_ip = extracted_hosts[src_mac]
		var host = preload(HOST_SCENE).instantiate()
		var label = host.get_node("label")
		if label: label.text = "%s\n%s" % [src_ip, src_mac]
		var angle = (TAU / host_keys.size()) * i
		host.position = Vector3(2.0*cos(angle), 0.4, 2.0*sin(angle))
		add_child(host)
		hosts[src_mac] = host
		hosts_location[host] = host.position
		
func format_pkt_info(pkt):
	var info = []
	if pkt.ethernet:
		info.append("-- eth --")
		info.append("ethertype: " + pkt.ethernet.ethertype)
		info.append("src_mac: " + (pkt.ethernet.src_mac))
		info.append("dst_mac: " + (pkt.ethernet.dst_mac))
	if pkt.ip:
		info.append("-- ip --")
		info.append("src_ip: " + (pkt.ip.src_ip))
		info.append("dst_ip: " + (pkt.ip.dst_ip))
	if pkt.ip and pkt.ip.transport:
		info.append("-- " + str(pkt.ip.transport.type).to_lower() + " --")
		info.append("flags: " + pkt.ip.transport.tcp_flags)
		info.append("src_port: %d" % pkt.ip.transport.src_port)
		info.append("dst_port: %d" % pkt.ip.transport.dst_port)
		#info.append("seq: %d" % pkt.ip.transport.seq_number)
		#info.append("ack: %d" % pkt.ip.transport.ack_number)
	if pkt.http_method != "":
		info.append("-- http --")
		#info.append("method: " + pkt.http_method)
		info.append("request_line: " + pkt.http_request_line)
		#info.append("host: " + pkt.http_host)
	return info
	
func spawn_packet(source_host, destination_host, pkt):
	var packet = preload(PACKET_SCENE).instantiate()
	var label = packet.get_node("outline").get_node("label")
	if label: label.text = "\n".join(format_pkt_info(pkt))
	connect("pause_changed", Callable(packet, "_on_pause_changed"))
	connect("reverse_changed", Callable(packet, "_on_reverse_changed"))
	add_child(packet)
	packet.global_position = source_host.position
	packet.move(source_host, destination_host, packet_speed, playback_speed)
	
# OpenXR stuff
# Handle OpenXR session ready
func _on_openxr_session_begun() -> void:
	# Get the reported refresh rate
	var current_refresh_rate = xr_interface.get_display_refresh_rate()
	if current_refresh_rate > 0:
		print("OpenXR: Refresh rate reported as ", str(current_refresh_rate))
	else:
		print("OpenXR: No refresh rate given by XR runtime")
	# See if we have a better refresh rate available
	var new_rate = current_refresh_rate
	var available_rates : Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.size() == 0:
		print("OpenXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1: # Only one available, so use it
		new_rate = available_rates[0]
	else:
		for rate in available_rates:
			if rate > new_rate and rate <= maximum_refresh_rate:
				new_rate = rate
	# Did we find a better rate?
	if current_refresh_rate != new_rate:
		print("OpenXR: Setting refresh rate to ", str(new_rate))
		xr_interface.set_display_refresh_rate(new_rate)
		current_refresh_rate = new_rate
	# Now match our physics rate
	Engine.physics_ticks_per_second = current_refresh_rate
	
# Handle OpenXR visible state
func _on_openxr_visible_state() -> void:
	# We always pass this state at startup,
	# but the second time we get this it means our player took off their headset
	if xr_is_focussed:
		print("OpenXR lost focus")
		xr_is_focussed = false
		# pause our game
		get_tree().paused = true
		emit_signal("focus_lost")

# Handle OpenXR focused state
func _on_openxr_focused_state() -> void:
	print("OpenXR gained focus")
	xr_is_focussed = true
	# unpause our game
	get_tree().paused = false
	emit_signal("focus_gained")

# Handle OpenXR stopping state
func _on_openxr_stopping() -> void:
	# Our session is being stopped.
	print("OpenXR is stopping")

# Handle OpenXR pose recentered signal
func _on_openxr_pose_recentered() -> void:
	# User recentered view, we have to react to this by recentering the view.
	# This is game implementation dependent.
	emit_signal("pose_recentered")


@onready var viewport : Viewport = get_viewport()
@onready var environment : Environment = $environment.environment
#$WorldEnvironment.environment

func switch_to_ar() -> bool:
	var xr_interface: XRInterface = XRServer.primary_interface
	if xr_interface:
		var modes = xr_interface.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			viewport.transparent_bg = true
		elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
			viewport.transparent_bg = false
	else:
		return false

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	return true

func switch_to_vr() -> bool:
	var xr_interface: XRInterface = XRServer.primary_interface
	if xr_interface:
		var modes = xr_interface.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		else:
			return false

	viewport.transparent_bg = false
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	return true
