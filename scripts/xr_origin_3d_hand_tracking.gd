extends Node3D

func _ready():
	var detector := $GrabDetector
	# Find your grabber nodes (assuming these names)
	var left_grabber  : Node = $LeftAim
	var right_grabber : Node = $RightAim

	detector.grab_started.connect(func(hand):
		if hand == "left": left_grabber.call("_try_grab")
		else: right_grabber.call("_try_grab")
	)

	detector.grab_ended.connect(func(hand):
		if hand == "left": left_grabber.call("_release")
		else: right_grabber.call("_release")
	)

	# Optional: use strength while holding (e.g., squeeze to scale)
	detector.grab_held.connect(func(hand, strength):
		# left_grabber/right_grabber could expose a method to use strength
		pass)
