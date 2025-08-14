extends XRController3D

signal ax_button_pressed
signal by_button_pressed
var show_laser = false
var show_help = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.button_pressed.connect(_on_button_pressed)
	self.button_released.connect(_on_button_released)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$FunctionPointer/Laser.visible = show_laser
	$HelpButtonX.visible = show_help
	$HelpButtonY.visible = show_help
	$"../RightHand/HelpButtonA".visible = show_help
	$"../RightHand/HelpButtonB".visible = show_help

	
func _on_button_pressed(button_name: String) -> void:
	if not "touch" in button_name:
		print("L-Hand: ", button_name)
	if button_name == "ax_button":
		emit_signal("ax_button_pressed")
	if button_name == "by_button":
		emit_signal("by_button_pressed")
	if button_name == "grip_click":
		show_laser = true
	if button_name == "menu_button":
		show_help = !show_help
		
func _on_button_released(button_name: String) -> void:
	if button_name == "grip_click":
		show_laser = false
	
