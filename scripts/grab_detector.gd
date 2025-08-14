extends Node
class_name GrabDetector

signal grab_started(hand: String)          # "left" | "right"
signal grab_ended(hand: String)
signal grab_held(hand: String, strength: float) # 0..1

@export_range(0.0, 1.0, 0.01) var curl_threshold := 0.75
@export_range(0.0, 0.2, 0.005) var thumb_palm_max_dist := 0.045   # meters (~4.5 cm)
@export var debug_print := false

var _down := {"left": false, "right": false}
var _t_palm: Transform3D # temp palm transform for curl calc

func _process(_dt: float) -> void:
	_eval("left")
	_eval("right")

func _eval(side: String) -> void:
	var tracker := XRServer.get_tracker("/user/hand_tracker/%s" % side)
	var hand := tracker as XRHandTracker
	if hand == null:
		_set_down(side, false, 0.0)
		return

	var J = OpenXRInterface

	# Required joints
	var t_palm    := hand.get_hand_joint_transform(J.HAND_JOINT_PALM)
	var t_i_tip   := hand.get_hand_joint_transform(J.HAND_JOINT_INDEX_TIP)
	var t_i_prox  := hand.get_hand_joint_transform(J.HAND_JOINT_INDEX_PROXIMAL)
	var t_m_tip   := hand.get_hand_joint_transform(J.HAND_JOINT_MIDDLE_TIP)
	var t_m_prox  := hand.get_hand_joint_transform(J.HAND_JOINT_MIDDLE_PROXIMAL)
	var t_r_tip   := hand.get_hand_joint_transform(J.HAND_JOINT_RING_TIP)
	var t_r_prox  := hand.get_hand_joint_transform(J.HAND_JOINT_RING_PROXIMAL)
	var t_t_tip   := hand.get_hand_joint_transform(J.HAND_JOINT_THUMB_TIP)

	# Make sure all joints are valid
	if [t_palm, t_i_tip, t_i_prox, t_m_tip, t_m_prox, t_r_tip, t_r_prox, t_t_tip].has(null):
		_set_down(side, false, 0.0)
		return

	# Store palm for curl calc
	_t_palm = t_palm

	var c_index  := finger_curl(t_i_tip, t_i_prox)
	var c_middle := finger_curl(t_m_tip, t_m_prox)
	var c_ring   := finger_curl(t_r_tip, t_r_prox)
	var curl_avg := (c_index + c_middle + c_ring) / 3.0

	var thumb_near_palm := t_t_tip.origin.distance_to(t_palm.origin) <= thumb_palm_max_dist
	var strength : float = clamp((curl_avg - curl_threshold) / max(1.0 - curl_threshold, 0.0001), 0.0, 1.0)
	var is_grab := (curl_avg >= curl_threshold) #and thumb_near_palm

	if debug_print:
		prints(side, "curl_avg", snapped(curl_avg, 0.01), "thumb_near", thumb_near_palm, "grab", is_grab)

	if not _down[side] and is_grab:
		_set_down(side, true, strength)
	elif _down[side] and not is_grab:
		_set_down(side, false, strength)
	elif _down[side]:
		emit_signal("grab_held", side, strength)

func finger_curl(tip: Transform3D, prox: Transform3D) -> float:
	var length := prox.origin.distance_to(tip.origin)
	if length <= 0.0001:
		return 0.0
	var tip_to_palm := tip.origin.distance_to(_t_palm.origin)
	var open_ref := length * 1.2
	var curl_ref := length * 0.6
	var x : float = (tip_to_palm - curl_ref) / max(open_ref - curl_ref, 0.0001)
	return clamp(1.0 - x, 0.0, 1.0)

func _set_down(side: String, v: bool, strength: float) -> void:
	if _down[side] == v:
		if v:
			emit_signal("grab_held", side, strength)
		return
	_down[side] = v
	if v:
		emit_signal("grab_started", side)
	else:
		emit_signal("grab_ended", side)
