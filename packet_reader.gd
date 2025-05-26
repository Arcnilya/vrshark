extends RefCounted

class_name PacketReader  # Main class for handling packets

var packets = []  # Stores parsed packets

# ==== PACKET DATA STRUCTURES ====
class Packet:
	var timestamp : float
	var length : int
	var ethernet : EthernetHeader
	var ip : IPHeader
	var transport : TransportHeader
	var data : PackedByteArray
	var http_method : String = ""
	var http_request_line : String = ""
	var http_host : String = ""

class EthernetHeader:
	var src_mac : String
	var dst_mac : String
	var ethertype : int

class IPHeader:
	var src_ip : String
	var dst_ip : String
	var protocol : int
	var total_length : int
	var transport : TransportHeader = null

class TransportHeader:
	var type : String  # "TCP" or "UDP"
	var src_port : int
	var dst_port : int
	var seq_number : int = 0  # For TCP
	var ack_number : int = 0  # For TCP
	var length : int = 0  # For UDP
	var tcp_flags : String = ""  # New: string like "[SYN, ACK]"

# ==== PACKET PARSING FUNCTIONS ====
func read_pcap(file_path: String):
	packets.clear()  # Reset list
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Failed to open file")
		return

	file.get_buffer(24)  # Skip PCAP global header

	while not file.eof_reached():
		if file.get_position() + 16 > file.get_length():
			break  

		var ts_sec = file.get_32()
		var ts_usec = file.get_32()
		var incl_len = file.get_32()
		var _orig_len = file.get_32()
		var packet_data = file.get_buffer(incl_len)

		var packet = Packet.new()
		packet.timestamp = ts_sec + (ts_usec / 1000000.0)
		packet.length = incl_len
		packet.data = packet_data

		if incl_len >= 14:
			var eth = EthernetHeader.new()
			eth.dst_mac = format_mac(packet_data.slice(0, 6))
			eth.src_mac = format_mac(packet_data.slice(6, 12))
			eth.ethertype = (packet_data[12] << 8) | packet_data[13]
			packet.ethernet = eth

			if eth.ethertype == 0x0800 and incl_len >= 34:
				packet.ip = parse_ipv4_header(packet_data.slice(14, incl_len))
				packet.http_method = _extract_http_method(packet)
			
		packets.append(packet)

	file.close()
	print("[+] Loaded", packets.size(), "packets!")


func format_mac(mac_bytes: PackedByteArray) -> String:
	var mac_parts = []
	for b in mac_bytes:
		mac_parts.append("%02x" % b)  
	return ":".join(mac_parts)


func parse_ipv4_header(ip_data: PackedByteArray) -> IPHeader:
	var ip = IPHeader.new()
	var version_ihl = ip_data[0]
	var ihl = (version_ihl & 0x0F) * 4  
	ip.total_length = (ip_data[2] << 8) | ip_data[3]
	ip.protocol = ip_data[9]
	ip.src_ip = "%d.%d.%d.%d" % [ip_data[12], ip_data[13], ip_data[14], ip_data[15]]
	ip.dst_ip = "%d.%d.%d.%d" % [ip_data[16], ip_data[17], ip_data[18], ip_data[19]]

	if ip.protocol == 6 and ip.total_length >= ihl + 20:
		ip.transport = parse_tcp_header(ip_data.slice(ihl, ip.total_length))
	elif ip.protocol == 17 and ip.total_length >= ihl + 8:
		ip.transport = parse_udp_header(ip_data.slice(ihl, ip.total_length))

	return ip


func parse_tcp_header(tcp_data: PackedByteArray) -> TransportHeader:
	var tcp = TransportHeader.new()
	tcp.type = "TCP"
	tcp.src_port = (tcp_data[0] << 8) | tcp_data[1]
	tcp.dst_port = (tcp_data[2] << 8) | tcp_data[3]
	tcp.seq_number = (tcp_data[4] << 24) | (tcp_data[5] << 16) | (tcp_data[6] << 8) | tcp_data[7]
	tcp.ack_number = (tcp_data[8] << 24) | (tcp_data[9] << 16) | (tcp_data[10] << 8) | tcp_data[11]

	if tcp_data.size() > 13:
		var flags_byte = tcp_data[13]
		var flag_names = {
			"FIN": 0x01,
			"SYN": 0x02,
			"RST": 0x04,
			"PSH": 0x08,
			"ACK": 0x10,
			"URG": 0x20,
			"ECE": 0x40,
			"CWR": 0x80
		}
		var active = []
		for name in flag_names.keys():
			if (flags_byte & flag_names[name]) != 0:
				active.append(name)
		tcp.tcp_flags = "[" + ", ".join(active) + "]"

	return tcp


func parse_udp_header(udp_data: PackedByteArray) -> TransportHeader:
	var udp = TransportHeader.new()
	udp.type = "UDP"
	udp.src_port = (udp_data[0] << 8) | udp_data[1]
	udp.dst_port = (udp_data[2] << 8) | udp_data[3]
	udp.length = (udp_data[4] << 8) | udp_data[5]
	return udp

func _extract_http_method(packet: Packet) -> String:
	if not packet.ip or not packet.ip.transport:
		return ""

	var transport = packet.ip.transport
	if transport.type != "TCP":
		return ""

	if transport.dst_port != 80 and transport.src_port != 80:
		return ""

	var ip_data = packet.data.slice(14, packet.length)
	var ihl = (ip_data[0] & 0x0F) * 4
	var tcp_offset = ((ip_data[ihl + 12] >> 4) & 0x0F) * 4
	var payload_start = 14 + ihl + tcp_offset

	if payload_start >= packet.length:
		return ""

	var http_data = packet.data.slice(payload_start, packet.length)
	var http_string = http_data.get_string_from_ascii()
	# After identifying method
	var lines = http_string.split("\r\n")
				
	for method in ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH", "CONNECT", "TRACE"]:
		if http_string.begins_with(method):
			if lines.size() > 0:
				packet.http_request_line = lines[0]
				for line in lines:
					if line.begins_with("Host:"):
						packet.http_host = line.substr(6).strip_edges()
			return method
	return ""
