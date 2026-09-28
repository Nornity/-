extends RefCounted

static func install() -> void:
	var bindings = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A], "move_right": [KEY_D],
		"turn_left": [KEY_LEFT], "turn_right": [KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C], "flashlight": [KEY_F],
		"interact": [KEY_E], "fire": [KEY_SPACE], "reload": [KEY_R],
		"rock": [KEY_Q], "map": [KEY_M], "pause": [KEY_ESCAPE],
		"help": [KEY_H], "fullscreen": [KEY_F11]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for code in bindings[action]:
				var event := InputEventKey.new()
				event.physical_keycode = code
				InputMap.action_add_event(action, event)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("fire", click):
		InputMap.action_add_event("fire", click)

static func release_movement() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "turn_left", "turn_right"]:
		Input.action_release(action)
