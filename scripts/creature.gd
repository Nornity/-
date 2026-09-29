extends CharacterBody3D
## Explicit sensory state machine. Patrol does not know the player's position.
## Hearing uses corridor distance; a wall is not the same as open air.

signal caught
signal state_changed(new_state: String)
signal sound_requested(sound_name: String, position_3d: Vector3)

const Maze = preload("res://scripts/maze.gd")
const Models = preload("res://scripts/models.gd")
const PASSIVE_SENSE_RANGE: float = 24.0
const CLOSE_CROUCH_RANGE: float = 1.2
const CLOSE_STANDING_RANGE: float = 2.2
const SIGHT_CROUCH_RANGE: float = 8.0
const SIGHT_STANDING_RANGE: float = 13.0
const FLASHLIGHT_SENSE_RANGE: float = 20.0
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
@onready var collision_shape: CollisionShape3D = $Collision
var recovering_from_stuck: bool = false
var recovery_target := Vector3.ZERO
var recovery_cell := Vector2i(-1, -1)
var recovery_attempts: int = 0
var aligned_cell := Vector2i(-1, -1)

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
	aligned_cell = Vector2i(-1, -1)
	state_changed.emit(next)
	if next == "chase":
		sound_requested.emit("growl", global_position)

func hearing_multiplier() -> float:
	match str(config.get("type", "")):
		"blind": return 1.4
		"listener": return 1.7
		"watcher": return 1.0
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
	if target != sound_cell:
		aligned_cell = Vector2i(-1, -1)
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
	recovering_from_stuck = false
	recovery_attempts = 0
	aligned_cell = Vector2i(-1, -1)
	recovery_cell = Vector2i(-1, -1)
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
	var aim := navigation_aim()
	if recovering_from_stuck and _flat_distance(global_position, recovery_target) < 0.22:
		recovering_from_stuck = false
		recovery_attempts = 0
		aligned_cell = Vector2i(-1, -1)
		recovery_cell = Vector2i(-1, -1)
		path_timer = 0.0
		_repath()
		aim = navigation_aim()
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
	var distance_to_aim_before: float = _flat_distance(before, aim)
	move_and_slide()
	var travelled: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var progress_to_aim: float = distance_to_aim_before - _flat_distance(global_position, aim)
	if progress_to_aim < 0.002 and direction.length() > 0.1:
		stuck_time += delta
		if stuck_time > 0.45:
			stuck_time = 0.0
			_begin_stuck_recovery()
	else:
		stuck_time = 0.0
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
	if distance > PASSIVE_SENSE_RANGE:
		return
	var eye: Vector3 = global_position + Vector3(0, 1.9, 0)
	var direction: Vector3 = (player.camera.global_position - eye).normalized()
	var los: bool = world.line_of_sight(eye, player.camera.global_position)
	var close_range: float = CLOSE_CROUCH_RANGE if player.crouching else CLOSE_STANDING_RANGE
	var detected: bool = distance < close_range and los
	if config.type != "blind" and los:
		var sight_range: float = SIGHT_CROUCH_RANGE if player.crouching else SIGHT_STANDING_RANGE
		if distance < sight_range and (-global_basis.z).dot(direction) > 0.05:
			detected = true
		var in_beam: bool = (-player.camera.global_basis.z).dot(-direction) > 0.80
		if player.flashlight and in_beam and distance < FLASHLIGHT_SENSE_RANGE:
			detected = true
	if detected:
		last_known = player.global_position
		var seen_cell: Vector2i = Maze.to_cell(last_known)
		if target != seen_cell:
			aligned_cell = Vector2i(-1, -1)
		target = seen_cell
		memory = 3.6
		_change_state("chase")

func _can_steer_to_memory() -> bool:
	if state != "chase" and state != "investigate":
		return false
	var eye := Vector3(0, 0.9, 0)
	return (
		world.line_of_sight(global_position + eye, last_known + eye)
		and _capsule_path_clear(last_known)
	)

func navigation_aim() -> Vector3:
	if recovering_from_stuck:
		return recovery_target
	if _can_steer_to_memory():
		# Keep a sub-cell chase target at open junctions, but never steer a full
		# capsule through a corner just because a thin vision ray can see around it.
		aligned_cell = Vector2i(-1, -1)
		return last_known
	if not path.is_empty():
		# Follow one grid waypoint at a time. On entering a cell, centre the body
		# once before following the next edge; this prevents replanning from
		# aiming diagonally across the inside of a 90-degree corner.
		var current_cell: Vector2i = Maze.to_cell(global_position)
		if world.maze.is_open(current_cell) and aligned_cell != current_cell:
			var cell_center: Vector3 = Maze.to_world(current_cell, global_position.y)
			if _flat_distance(cell_center, global_position) > 0.12:
				return cell_center
			aligned_cell = current_cell
		while not path.is_empty() and path[0] == current_cell:
			path.pop_front()
		if path.is_empty():
			return Maze.to_world(target, global_position.y)
		var waypoint: Vector3 = Maze.to_world(path[0], global_position.y)
		if _flat_distance(waypoint, global_position) < 0.12:
			path.pop_front()
			waypoint = Maze.to_world(path[0], global_position.y) if not path.is_empty() else Maze.to_world(target, global_position.y)
		return waypoint
	if _flat_distance(global_position, Maze.to_world(target)) < 0.65:
		if state == "patrol":
			_new_patrol_target()
		elif state == "search":
			_choose_search_target()
		elif state == "investigate":
			_change_state("search")
			search_time = 4.0
	return Maze.to_world(target, global_position.y)

func _capsule_path_clear(destination: Vector3) -> bool:
	var motion := Vector3(destination.x - global_position.x, 0.0, destination.z - global_position.z)
	if motion.length_squared() < 0.0001:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.motion = motion
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = [get_rid()]
	query.exclude = excluded
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return not fractions.is_empty() and fractions[0] >= 0.995

func _capsule_position_clear(root_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	var shape_transform: Transform3D = collision_shape.global_transform
	shape_transform.origin += root_position - global_position
	query.transform = shape_transform
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = [get_rid()]
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _begin_stuck_recovery() -> void:
	path_timer = 0.0
	aligned_cell = Vector2i(-1, -1)
	_repath()
	if recovery_attempts >= 4:
		recovery_attempts = 0
		recovery_cell = Vector2i(-1, -1)
	var current_cell: Vector2i = Maze.to_cell(global_position)
	var candidates: Array[Vector2i] = []
	if world.maze.is_open(current_cell):
		candidates.append(current_cell)
		for step in Maze.DIRECTIONS:
			var neighbor: Vector2i = current_cell + step
			if world.maze.is_open(neighbor):
				candidates.append(neighbor)
	var best_cell := Vector2i(-1, -1)
	var best_score: float = INF
	for cell in candidates:
		if cell == recovery_cell:
			continue
		var waypoint: Vector3 = Maze.to_world(cell, global_position.y)
		var distance: float = _flat_distance(global_position, waypoint)
		if distance < 0.24 or not _capsule_path_clear(waypoint):
			continue
		var route: Array[Vector2i] = world.maze.find_path(cell, target)
		if cell != target and route.is_empty():
			continue
		var score: float = distance + route.size() * Maze.CELL_SIZE * 0.12
		if score < best_score:
			best_score = score
			best_cell = cell
	if best_cell.x >= 0:
		recovery_cell = best_cell
		recovery_target = Maze.to_world(best_cell, global_position.y)
		recovering_from_stuck = true
		recovery_attempts += 1
		path.clear()
		velocity = Vector3.ZERO
	else:
		recovering_from_stuck = false
		recovery_attempts += 1
		if recovery_attempts >= 2 and _emergency_recenter():
			return
		_repath()

func _emergency_recenter() -> bool:
	var best_cell := Vector2i(-1, -1)
	var best_score: float = INF
	for cell in world.maze.floor_cells:
		var candidate: Vector3 = Maze.to_world(cell, global_position.y)
		var distance: float = _flat_distance(global_position, candidate)
		if distance < 0.24 or distance > Maze.CELL_SIZE * 1.5:
			continue
		if not _capsule_position_clear(candidate):
			continue
		var route: Array[Vector2i] = world.maze.find_path(cell, target)
		if cell != target and route.is_empty():
			continue
		var score: float = distance + route.size() * Maze.CELL_SIZE * 0.12
		if score < best_score:
			best_score = score
			best_cell = cell
	if best_cell.x < 0:
		return false
	# A brief snap inside the nearest clear tile is safer than letting a wedged
	# capsule vibrate forever. It is only used after repeated recovery attempts.
	global_position = Maze.to_world(best_cell, global_position.y)
	velocity = Vector3.ZERO
	recovering_from_stuck = false
	recovery_attempts = 0
	recovery_cell = Vector2i(-1, -1)
	aligned_cell = Vector2i(-1, -1)
	path.clear()
	path_timer = 0.0
	_repath()
	return true

func _flat_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()

func _repath() -> void:
	var start: Vector2i = Maze.to_cell(global_position)
	if not world.maze.is_open(start):
		var nearest := Vector2i(-1, -1)
		var nearest_distance: float = INF
		for cell in world.maze.floor_cells:
			var distance: float = _flat_distance(global_position, Maze.to_world(cell, global_position.y))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = cell
			if nearest_distance < Maze.CELL_SIZE * 0.5:
				break
		start = nearest
	path = world.maze.find_path(start, target) if start.x >= 0 else []

func _new_patrol_target() -> void:
	var cells: Array[Vector2i] = world.maze.floor_cells
	target = cells[rng.randi_range(0, cells.size() - 1)]
	aligned_cell = Vector2i(-1, -1)
	path_timer = 0

func _choose_search_target() -> void:
	var nearby: Array[Vector2i] = []
	var center: Vector2i = Maze.to_cell(last_known)
	for cell in world.maze.floor_cells:
		if cell.distance_to(center) < 4.0:
			nearby.append(cell)
	if not nearby.is_empty():
		target = nearby[rng.randi_range(0, nearby.size() - 1)]
		aligned_cell = Vector2i(-1, -1)
		path_timer = 0

func _animate(delta: float, is_moving: bool) -> void:
	for i in range(2):
		var swing: float = sin(gait + i * PI) * (0.37 if is_moving else 0.0)
		model.legs[i].rotation.x = swing
		model.arms[i].rotation.x = -swing * 0.8 - (0.7 if state == "chase" else 0.02)
	model.root.position.y = absf(sin(gait)) * 0.045 if is_moving else 0.0
	model.head.rotation.z = lerpf(model.head.rotation.z, sin(awake_time * 1.6) * 0.08 + (0.22 if state == "search" else 0.0), minf(1, delta * 4))
