extends XRController3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.button_pressed.connect(_on_button_pressed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _on_button_pressed(button_name: String) -> void:
	if not "touch" in button_name:
		print("L-Hand: ", button_name)
