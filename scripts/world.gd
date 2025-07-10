extends Node3D

signal pause_changed(paused: bool)
signal reverse_changed(reversed: bool)

@onready var file_dialog := $FileDialog
@export var playback_speed: float = 1.0
@export var packet_speed: float = 5.0

var packet_reader = PacketReader.new()
var hosts = {} # Stored MAC -> host instance mapping
var current_index = -1
var is_paused = false
var is_reversed = false

const PACKET_SCENE = "res://scenes/packet.tscn"
const HOST_SCENE = "res://scenes/host.tscn"

func _ready() -> void:
	file_dialog.filters = ["*.pcap ; PCAP Files"]
	file_dialog.popup_centered()  # Show on start-up
	file_dialog.file_selected.connect(_on_file_selected)
	
func _on_file_selected(path: String):
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("Selected PCAP file: %s" % path)
	packet_reader.read_pcap(path)
	spawn_hosts()
	
func _process(delta: float) -> void:
	var hud_index = get_node("HUD/Index")
	hud_index.text = "%s/%s" % [current_index+1, packet_reader.packets.size()]
	if Input.is_action_just_pressed("step_forward"):
		if is_packet_in_transit():
			return
		if is_reversed == true and current_index != -1:
			current_index -= 1
		is_reversed = false
		emit_signal("reverse_changed", is_reversed)
		process_packet()
	if Input.is_action_just_pressed("step_backward"):
		if is_packet_in_transit():
			return
		if is_reversed == false:
			current_index += 1
		is_reversed = true
		emit_signal("reverse_changed", is_reversed)
		process_packet()
	if Input.is_action_just_pressed("space"):
		is_paused = !is_paused	
		emit_signal("pause_changed", is_paused)
	if Input.is_action_just_pressed("escape"):
		toggle_pause()
		
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
					
		#print("spawn_packet: ", str(current_index).lpad(2," "), " ", " ".join([src_mac, dst_mac] + label_content))
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
		host.position = Vector3(5.0*cos(angle), 0.3, 5.0*sin(angle))
		add_child(host)
		hosts[src_mac] = host
		
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
	packet.player = $player
	add_child(packet)
	packet.global_position = source_host.position
	packet.move(source_host, destination_host, packet_speed, playback_speed)
