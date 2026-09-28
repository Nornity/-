extends CharacterBody3D
## Explicit sensory state machine. Patrol does not know the player's position.
## Hearing uses corridor distance; a wall is not the same as open air.

signal caught
signal state_changed(new_state: String)
signal sound_requested(sound_name: String, position_3d: Vector3)

const Maze = preload("res://scripts/maze.gd")
const Models = preload("res://scripts/models.gd")
var world
var player
var config: Dictionary
var active: bool = false
var state: String = "patrol"
var target := Vector2i.ZERO
var last_known := Vector3.ZERO
var path: Array[Vector2i] = []
var memory: float = 0.0
var search_time: float = 0.0
var stun_time: float = 0.0
var sense_timer: float = 0.0
var path_timer: float = 0.0
var growl_timer: float = 9.0
var step_timer: float = 0.0
var stuck_time: float = 0.0
var awake_time: float = 0.0
var gait: float = 0.0
var model: Dictionary
var rng := RandomNumberGenerator.new()

func setup(level_world, subject, sector: Dictionary) -> void:
	world = level_world
	player = subject
	config = sector
	rng.seed = int(world.maze.generation_seed) + 607
	model = Models.creature(config.type)
	add_child(model.root)
	target = Maze.to_cell(global_position)
	last_known = global_position
	_new_patrol_target()

func _change_state(next: String) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(next)
	if next == "chase":
		sound_requested.emit("growl", global_position)

func hearing_multiplier() -> float:
	match str(config.get("type", "")):
		"blind": return 1.35
		"listener": return 1.65
		"watcher": return 0.95
	return 1.0

func hear_noise(where: Vector3, radius: float, from_player: bool = true) -> bool:
	if not active or stun_time > 0 or awake_time < 3.0:
		return false
	radius *= hearing_multiplier()
	var distance: float = global_position.distance_to(where)
	if distance > radius:
		return false
	var sound_cell: Vector2i = Maze.to_cell(where)
	if not world.maze.is_open(sound_cell):
		return false
	var sound_path: Array[Vector2i] = world.maze.find_path(Maze.to_cell(global_position), sound_cell)
	var acoustic_distance: float = sound_path.size() * Maze.CELL_SIZE * 0.72 + distance * 0.28
	if acoustic_distance > radius:
		return false
	if not from_player and state == "chase" and memory > 1.0:
		return false
	last_known = where
	target = sound_cell
	path_timer = 0.0
	search_time = 7.0
	if from_player and (distance < 8.0 or state == "chase"):
		memory = 3.6
		_change_state("chase")
	else:
		_change_state("investigate")
	return true

func stun(duration: float = 6.0) -> void:
	stun_time = duration
	memory = 0
	path.clear()
	velocity = Vector3.ZERO
	_change_state("stunned")

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(player):
		return
	awake_time += delta
	if stun_time > 0:
		stun_time = maxf(0, stun_time - delta)
		model.root.rotation.x = lerpf(model.root.rotation.x, -1.40, minf(1, delta * 6))
		if stun_time <= 0:
			_change_state("search")
			search_time = 4.0
			target = Maze.to_cell(global_position)
		return
	model.root.rotation.x = lerpf(model.root.rotation.x, 0, minf(1, delta * 5))
	sense_timer -= delta
	if sense_timer <= 0 and awake_time >= 3.0:
		sense_timer = 0.16
		_sense_player()
	if state == "chase":
		memory -= delta
		if memory <= 0:
			_change_state("search")
			search_time = 6.0
	elif state == "investigate" or state == "search":
		search_time -= delta
		if search_time <= 0:
			_change_state("patrol")
			_new_patrol_target()
	path_timer -= delta
	if path_timer <= 0:
		path_timer = 0.45 if state == "chase" else 0.9
		_repath()
	var aim := global_position
	if _can_steer_to_memory():
		# Keep the last seen position in world space. Chasing a cell center makes
		# the creature orbit a player standing on a four-way junction.
		aim = last_known
	elif not path.is_empty():
		aim = _visible_path_waypoint()
		if Vector2(aim.x - global_position.x, aim.z - global_position.z).length() < 0.34:
			path.pop_front()
			if not path.is_empty():
				aim = _visible_path_waypoint()
	elif global_position.distance_to(Maze.to_world(target)) < 0.65:
		if state == "patrol":
			_new_patrol_target()
		elif state == "search":
			_choose_search_target()
		elif state == "investigate":
			_change_state("search")
			search_time = 4.0
	var direction: Vector3 = aim - global_position
	direction.y = 0
	var speed: float = float(config.chase) if state == "chase" else float(config.patrol)
	if state == "investigate":
		speed *= 1.20
	if awake_time < 3:
		speed = 0.0
	if direction.length() > 0.06:
		direction = direction.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 7))
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0
		velocity.z = 0
	velocity.y = -0.1 if is_on_floor() else velocity.y - delta * 15.0
	var before := global_position
	move_and_slide()
	var travelled: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if travelled < 0.001 and direction.length() > 0.1:
		stuck_time += delta
		if stuck_time > 0.8:
			stuck_time = 0
			path_timer = 0.0
			_repath()
	else:
		stuck_time = 0
	gait += travelled * 3.4
	_animate(delta, travelled > 0.001)
	growl_timer -= delta
	if growl_timer <= 0:
		growl_timer = rng.randf_range(7, 14) if state != "chase" else 3.4
		sound_requested.emit("growl", global_position)
	step_timer += travelled
	if step_timer > 1.7:
		step_timer = 0
		sound_requested.emit("step", global_position)
	if awake_time >= 3.0 and global_position.distance_to(player.global_position) < 0.72:
		if world.line_of_sight(global_position + Vector3(0, 0.9, 0), player.global_position + Vector3(0, 0.9, 0)):
			caught.emit()

func _sense_player() -> void:
	var distance: float = global_position.distance_to(player.global_position)
	if distance > 17.0:
		return
	var eye: Vector3 = global_position + Vector3(0, 1.9, 0)
	var direction: Vector3 = (player.camera.global_position - eye).normalized()
	var los: bool = world.line_of_sight(eye, player.camera.global_position)
	var detected: bool = distance < (1.0 if player.crouching else 1.65) and los
	if config.type != "blind" and los:
		var sight_range: float = 6.0 if player.crouching else 9.5
		if distance < sight_range and (-global_basis.z).dot(direction) > 0.05:
			detected = true
		var in_beam: bool = (-player.camera.global_basis.z).dot(-direction) > 0.80
		if player.flashlight and in_beam and distance < 15:
			detected = true
	if detected:
		last_known = player.global_position
		target = Maze.to_cell(last_known)
		memory = 3.6
		_change_state("chase")

func _can_steer_to_memory() -> bool:
	if state != "chase" and state != "investigate":
		return false
	var eye := Vector3(0, 0.9, 0)
	return world.line_of_sight(global_position + eye, last_known + eye)

func navigation_aim() -> Vector3:
	if _can_steer_to_memory():
		return last_known
	if path.is_empty():
		return Maze.to_world(target)
	return _visible_path_waypoint()

func _visible_path_waypoint() -> Vector3:
	if path.is_empty():
		return Maze.to_world(target)
	var eye := Vector3(0, 0.9, 0)
	var origin: Vector3 = global_position + eye
	var furthest_visible := 0
	for i in range(mini(path.size(), 10)):
		var point: Vector3 = Maze.to_world(path[i]) + eye
		if not world.line_of_sight(origin, point):
			break
		furthest_visible = i
	for i in range(furthest_visible):
		path.pop_front()
	return Maze.to_world(path[0])

func _repath() -> void:
	path = world.maze.find_path(Maze.to_cell(global_position), target)

func _new_patrol_target() -> void:
	var cells: Array[Vector2i] = world.maze.floor_cells
	target = cells[rng.randi_range(0, cells.size() - 1)]
	path_timer = 0

func _choose_search_target() -> void:
	var nearby: Array[Vector2i] = []
	var center: Vector2i = Maze.to_cell(last_known)
	for cell in world.maze.floor_cells:
		if cell.distance_to(center) < 4.0:
			nearby.append(cell)
	if not nearby.is_empty():
		target = nearby[rng.randi_range(0, nearby.size() - 1)]
		path_timer = 0

func _animate(delta: float, is_moving: bool) -> void:
	for i in range(2):
		var swing: float = sin(gait + i * PI) * (0.37 if is_moving else 0.0)
		model.legs[i].rotation.x = swing
		model.arms[i].rotation.x = -swing * 0.8 - (0.7 if state == "chase" else 0.02)
	model.root.position.y = absf(sin(gait)) * 0.045 if is_moving else 0.0
	model.head.rotation.z = lerpf(model.head.rotation.z, sin(awake_time * 1.6) * 0.08 + (0.22 if state == "search" else 0.0), minf(1, delta * 4))
