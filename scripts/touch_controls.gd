extends Control
## Native multi-touch controls. Movement, looking and held sprint use distinct
## touch IDs, so a cancelled finger cannot leave an action stuck on.

const Models = preload("res://scripts/models.gd")
var app
var move_id: int = -1
var look_id: int = -1
var held: Dictionary = {}
var stick := Vector2.ZERO
var mono: FontFile
const CENTER := Vector2(135, 569)
const RADIUS: float = 68.0
const BUTTONS = [
	{"id": "fire", "label": "ШОКЕР", "at": Vector2(1148, 568), "r": 49.0},
	{"id": "interact", "label": "ВЗЯТЬ", "at": Vector2(1036, 577), "r": 37.0},
	{"id": "reload", "label": "ЗАРЯД", "at": Vector2(1148, 663), "r": 29.0},
	{"id": "rock", "label": "КАМЕНЬ", "at": Vector2(1036, 663), "r": 29.0},
	{"id": "sprint", "label": "БЕГ", "at": Vector2(266, 588), "r": 35.0},
	{"id": "crouch", "label": "ТИШЕ", "at": Vector2(266, 670), "r": 29.0},
	{"id": "flashlight", "label": "СВЕТ", "at": Vector2(1148, 463), "r": 29.0},
	{"id": "map", "label": "КАРТА", "at": Vector2(1057, 463), "r": 29.0},
	{"id": "pause", "label": "II", "at": Vector2(1201, 112), "r": 25.0}
]

func _ready() -> void:
	mono = Models.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func reset() -> void:
	move_id = -1
	look_id = -1
	held.clear()
	stick = Vector2.ZERO
	if is_instance_valid(app.player):
		app.player.touch_move = Vector2.ZERO
		app.player.touch_sprint = false
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or app.state != "playing" or not is_instance_valid(app.player):
		return
	if event is InputEventScreenTouch:
		var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			if at.distance_to(CENTER) < RADIUS + 32 and move_id == -1:
				move_id = event.index
				_move_stick(at)
			else:
				var found: bool = false
				for button in BUTTONS:
					if at.distance_to(button.at) <= button.r + 7:
						held[event.index] = button.id
						if button.id == "sprint":
							app.player.touch_sprint = true
						elif button.id == "pause":
							app.pause_game()
						else:
							app.perform_action(button.id)
						found = true
						break
				if not found and look_id == -1:
					look_id = event.index
		else:
			_release(event.index)
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == move_id:
			_move_stick(get_global_transform_with_canvas().affine_inverse() * event.position)
		elif event.index == look_id:
			app.player.add_look(event.relative * 1.25 / maxf(0.1, get_global_transform_with_canvas().get_scale().x))
		get_viewport().set_input_as_handled()

func _release(id: int) -> void:
	if id == move_id:
		move_id = -1
		stick = Vector2.ZERO
		app.player.touch_move = Vector2.ZERO
	if id == look_id:
		look_id = -1
	if held.has(id):
		held.erase(id)
		app.player.touch_sprint = held.values().has("sprint")

func _move_stick(at: Vector2) -> void:
	stick = ((at - CENTER) / RADIUS).limit_length(1.0)
	app.player.touch_move = stick if stick.length() > 0.14 else Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	if app == null or not is_instance_valid(app.player):
		return
	draw_circle(CENTER, RADIUS, Color(0.035, 0.065, 0.07, 0.65))
	draw_arc(CENTER, RADIUS, 0, TAU, 64, Color(0.56, 0.68, 0.65, 0.55), 1.5)
	draw_circle(CENTER + stick * RADIUS * 0.70, 27, Color(0.56, 0.68, 0.65, 0.35))
	var keys: Array = held.values()
	for button in BUTTONS:
		var highlight: bool = keys.has(button.id)
		var col := Color("e38665") if highlight else Color("a1b7ab")
		draw_circle(button.at, button.r, Color(0.10, 0.17, 0.17, 0.72))
		draw_arc(button.at, button.r, 0, TAU, 48, col * Color(1, 1, 1, 0.75), 1.5)
		var caption: String = button.label
		if button.id == "interact" and not app.interaction.is_empty():
			if app.interaction.kind == "exit":
				caption = "ШЛЮЗ"
			elif app.interaction.kind == "wall":
				caption = "ЛОМАТЬ"
		var width: float = mono.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(mono, button.at + Vector2(-width * 0.5, 4), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
