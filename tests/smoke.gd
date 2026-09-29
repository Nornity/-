extends RefCounted
## Run: godot --headless --path . -- --smoke-test
## Or open the development Web preview with ?test=1.
## Tests run inside the real Godot engine, not a JavaScript reimplementation.

const Maze = preload("res://scripts/maze.gd")
const Levels = preload("res://scripts/level_config.gd")
const Progress = preload("res://scripts/progress.gd")
const Player = preload("res://scripts/player.gd")
var passed: int = 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(description)
		print("TEST_FAILED: ", description)

func frames(app, count: int = 2) -> void:
	for i in range(count):
		await app.get_tree().physics_frame

func run(app) -> Dictionary:
	var had_save: bool = FileAccess.file_exists(Progress.PATH)
	var original_bytes := FileAccess.get_file_as_bytes(Progress.PATH) if had_save else PackedByteArray()
	var original_unlocks: int = app.progress.unlocked
	var original_best: Dictionary = app.progress.best.duplicate(true)
	var original_endless: int = app.progress.endless_best
	var original_settings: Dictionary = app.progress.settings.duplicate(true)
	var random_seed_a: int = app._fresh_map_seed()
	var random_seed_b: int = app._fresh_map_seed()
	check(random_seed_a != random_seed_b, "Fresh runs receive different random map seeds")
	# The logic/physics tests do not need GPU rendering. Keep real physics active.
	app.get_viewport().disable_3d = true
	_test_mazes()
	app.start_run(0, 0, 707)
	await frames(app, 3)
	check(app.state == "playing", "Training starts")
	check(not is_instance_valid(app.creature), "Training is genuinely safe")
	check(app.player.loaded_count() == 2, "Taser starts with two loaded slots")
	check(app.player.run_speed >= 6.9 and app.player.run_speed <= 7.2, "Sprint uses the increased running speed")
	check(app.player.max_stamina > 100.0 and app.player.stamina_drain < 28.0, "Stamina capacity and sprint duration are increased")
	check(is_equal_approx(app.player.max_stamina / app.player.stamina_drain, 120.0 / 22.0), "Full sprint lasts a longer but limited burst")
	app.player.stamina = app.player.max_stamina
	app.player.moving = true
	app.player.sprinting = true
	app.player._update_stamina(2.0)
	check(is_equal_approx(app.player.stamina, 76.0), "Sprinting spends stamina at the tuned rate")
	app.player._update_stamina(4.0)
	check(app.player.stamina == 0.0 and app.player.exhausted, "An overlong sprint exhausts the player")
	app.player.sprinting = false
	app.player.moving = false
	app.player._update_stamina(1.5)
	app.player._update_stamina(1.0 / 60.0)
	check(not app.player.exhausted and app.player.stamina > app.player.max_stamina * 0.24, "Resting recovers stamina before sprinting resumes")
	app.player.stamina = app.player.max_stamina
	app.player.exhausted = false
	app.begin_escape()
	check(app.state == "playing", "Escape is impossible without required fuses")
	var before: Vector3 = app.player.position
	Input.action_press("move_forward")
	await frames(app, 20)
	Input.action_release("move_forward")
	check(app.player.position.distance_to(before) > 0.15, "WASD physics moves the player")
	app.pause_game()
	var paused_time: float = app.elapsed
	var paused_battery: float = app.player.battery
	var paused_position: Vector3 = app.player.position
	await frames(app, 5)
	check(app.elapsed == paused_time, "Pause freezes the session timer")
	check(app.player.battery == paused_battery, "Pause freezes battery drain")
	check(app.player.position == paused_position, "Pause freezes physics movement")
	app.resume_game()
	check(app.player.active and app.world.playing, "Resume restores gameplay")
	app.player.toggle_crouch()
	check(app.player.crouching and app.player.collision.shape.height < 1.2, "Crouch lowers collision capsule")
	check(app.player.crouch_sprint_speed > app.player.crouch_speed, "Crouched sprint is faster than a quiet crouch-walk")
	var crouch_stamina_before: float = app.player.stamina
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(app, 12)
	check(app.player.crouching and app.player.crouch_sprinting, "Holding Shift while crouched activates the low sprint")
	check(app.player.stamina < crouch_stamina_before, "Crouched sprint consumes stamina")
	check(app.tutorial_seen.has("crouch_sprint"), "The training tutorial observes crouched sprint")
	check(app.TUTORIAL[3].contains("SHIFT"), "The training includes a separate crouched-sprint instruction")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await frames(app, 2)
	app.player.toggle_crouch()
	check(app.player.fire(), "A loaded taser can fire")
	check(app.player.loaded_count() == 1, "A shot spends exactly one charge")
	check(not app.player.fire(), "Shot cooldown prevents spam")
	var reserves: int = app.player.reserves
	check(app.player.reload_taser(), "Reload starts with a spare battery")
	check(app.player.reserves == reserves - 1, "Reload spends exactly one spare")
	check(not app.player.reload_taser(), "Reload animation cannot double-spend batteries")
	app.player.tick_resources(float(app.config.recharge) + 0.2)
	check(app.player.loaded_count() == 2, "A depleted slot recharges to ready")
	app.player.battery = 4
	app.player.reserves = 1
	app.player.tick_resources(0.1)
	check(app.player.battery == 100 and app.player.reserves == 0, "Automatic battery replacement is atomic")
	app.player.battery = 0
	app.player.tick_resources(0.1)
	check(not app.player.flashlight, "Empty flashlight switches off")
	app.player.battery = 100
	app.player.reserves = 2
	app.player.flashlight = true
	app.perform_action("map")
	check(app.map_visible, "Map toggles on")
	check(app.ui.hud.MAP_GRID_SIZE >= 410.0, "Scanner map is enlarged for clearer reading")
	app.perform_action("map")
	check(not app.map_visible, "Map toggles off")
	_test_touch(app)
	var rock_count: int = app.player.rocks
	app.perform_action("rock")
	check(app.player.rocks == rock_count - 1 and app.thrown.size() == 1, "Throw consumes one rock and creates a projectile")
	app._update_rocks(0.8)
	check(app.thrown[0].landed, "Rock reaches an impact point")
	app._update_rocks(6.0)
	check(app.thrown.is_empty(), "Old rock projectiles are removed")
	# Use the same reach/line-of-sight checks as the E key.
	for item in app.world.items:
		if item.kind != "fuse":
			continue
		app.player.global_position = item.root.global_position + Vector3(0, 0.03, 0.95)
		app.player.velocity = Vector3.ZERO
		app.player.camera.look_at(item.root.global_position + Vector3(0, 0.9, 0))
		app._interact()
		check(item.taken, "Reachable fuse can be picked up through E interaction")
		check(not app.world.take_item(item), "A fuse cannot be collected twice")
	check(app.fuses == int(app.config.fuses), "Every training fuse is collectable")
	app.begin_escape()
	check(app.state == "opening", "Complete objective opens the airlock")
	app._update_escape(2.9)
	check(app.elevator_built, "Escape builds the 3D elevator sequence")
	app._update_escape(4.0)
	app._update_escape(1.3)
	check(app.state == "result", "Escape reaches the result screen")
	check(app.progress.best.has("0"), "Training completion records a best time")
	# Campaign AI and combat, using adjacent reachable cells.
	app.start_run(1, 0, 901)
	await frames(app, 3)
	var creature = app.creature
	creature.awake_time = 10
	var center: Vector2i = Maze.to_cell(creature.position)
	var neighbor: Vector2i = center
	for direction in Maze.DIRECTIONS:
		if app.world.maze.is_open(center + direction):
			neighbor = center + direction
			break
	app.player.position = Maze.to_world(neighbor, 0.03)
	app.player.camera.look_at(creature.global_position + Vector3(0, 1.3, 0))
	creature.rotation.y = atan2(-(app.player.position.x - creature.position.x), -(app.player.position.z - creature.position.z))
	creature.state = "patrol"
	creature._sense_player()
	check(creature.state == "patrol", "Blind creature does not see a stationary lit player")
	check(is_equal_approx(creature.hearing_multiplier(), 1.4), "Blind creature gets a strong, explicit hearing profile")
	await _test_junction_approach(app, creature)
	await _test_corner_navigation(app, creature)
	var far_cell := Vector2i.ZERO
	for candidate in app.world.maze.floor_cells:
		var corridor_steps: int = app.world.maze.find_path(center, candidate).size()
		var straight_distance: float = Maze.to_world(center).distance_to(Maze.to_world(candidate))
		if corridor_steps >= 10 and corridor_steps <= 15 and straight_distance >= 15.0 and straight_distance <= 30.0:
			far_cell = candidate
			break
	check(far_cell != Vector2i.ZERO, "Acoustic range test finds a distant connected corridor")
	if far_cell != Vector2i.ZERO:
		app.player.global_position = Maze.to_world(far_cell, 0.03)
		creature.state = "patrol"
		creature.memory = 0.0
		check(not creature.hear_noise(app.player.position, Player.WALK_NOISE_RADIUS), "Ordinary walking is audible nearby, not anywhere in the maze")
		check(creature.hear_noise(app.player.position, Player.SPRINT_NOISE_RADIUS), "A sprint echoes across several connected corridors")
		check(creature.state == "investigate", "Distant running attracts investigation without omniscient pursuit")
	app.player.global_position = Maze.to_world(neighbor, 0.03)
	app.player.camera.look_at(creature.global_position + Vector3(0, 1.3, 0))
	creature.state = "patrol"
	creature.memory = 0.0
	check(not creature.hear_noise(app.player.position, Player.CROUCH_NOISE_RADIUS), "Crouch remains the quiet approach")
	check(creature.hear_noise(app.player.position, Player.WALK_NOISE_RADIUS), "Walking is noticed at short range")
	check(creature.state == "chase", "A close detected sound starts a chase")
	app._fire_taser()
	check(creature.state == "stunned" and creature.stun_time > 5.9, "Aimed taser stuns a visible creature")
	check(not creature.hear_noise(app.player.position, 40), "Stunned creature cannot react to a distraction")
	creature.stun_time = 0
	creature.state = "patrol"
	creature.memory = 0
	check(creature.hear_noise(app.player.position, 27, false), "Rock impact is a valid distraction")
	check(creature.state == "investigate" and creature.target == neighbor, "Creature investigates the sound location, not omniscient player tracking")
	creature.config = creature.config.duplicate(true)
	creature.config.type = "watcher"
	check(is_equal_approx(creature.hearing_multiplier(), 1.0), "Watcher receives a balanced hearing multiplier")
	creature.config.type = "listener"
	check(is_equal_approx(creature.hearing_multiplier(), 1.7), "Deep listener is the most sensitive to sound")
	creature.config.type = "watcher"
	creature.state = "patrol"
	creature._sense_player()
	check(creature.state == "chase", "Sighted creature detects a visible player")
	# A solid wall must block line of sight and taser hits.
	var occlusion_pair: Array[Vector2i] = []
	for y in range(1, app.world.maze.width - 1):
		for x in range(1, app.world.maze.width - 1):
			var c := Vector2i(x, y)
			if app.world.maze.is_open(c):
				continue
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				if app.world.maze.is_open(c + direction) and app.world.maze.is_open(c - direction):
					occlusion_pair = [c + direction, c - direction]
					break
			if not occlusion_pair.is_empty():
				break
		if not occlusion_pair.is_empty():
			break
	check(not occlusion_pair.is_empty(), "Occlusion test has a real separating wall")
	if not occlusion_pair.is_empty():
		app.player.position = Maze.to_world(occlusion_pair[0], 0.03)
		creature.position = Maze.to_world(occlusion_pair[1], 0.03)
		app.player.camera.look_at(creature.position + Vector3(0, 1.3, 0))
		check(not app.world.line_of_sight(app.player.camera.global_position, creature.position + Vector3(0, 1.3, 0)), "Walls block line of sight")
		app.player.shot_cooldown = 0
		app.player.slots[0] = 0
		creature.state = "patrol"
		app._fire_taser()
		check(creature.state != "stunned", "Taser cannot stun through walls")
	app.pause_game()
	var enemy_position: Vector3 = creature.position
	await frames(app, 3)
	check(creature.position == enemy_position and not creature.active, "Pause also freezes the enemy")
	app.resume_game()
	var original_reduced_effects: bool = bool(app.progress.settings.reduced_effects)
	app.progress.settings.reduced_effects = false
	app.player.settings = app.progress.settings
	app.die()
	check(app.state == "dying" and not app.player.active, "Capture disables player input")
	check(app.audio.streams.has("scream"), "Capture has its own short, original scream sting")
	var full_effects: bool = not bool(app.progress.settings.reduced_effects)
	check(app.scare_flash.visible == full_effects, "Capture uses one optional impact flash")
	var face_direction: Vector3 = (app.creature.model.head.global_position - app.player.camera.global_position).normalized()
	check((-app.player.camera.global_basis.z).dot(face_direction) > 0.999, "Capture camera locks onto the creature's face")
	var impact_gap: float = Vector2(
		app.scare_impact_position.x - app.player.camera.global_position.x,
		app.scare_impact_position.z - app.player.camera.global_position.z
	).length()
	check(impact_gap >= 1.0, "The lunge stops close without clipping through the camera")
	var initial_lunge_distance: float = app.scare_staging_position.distance_to(app.scare_impact_position)
	app._update_death(0.2)
	var remaining_lunge_distance: float = app.creature.global_position.distance_to(app.scare_impact_position)
	check(remaining_lunge_distance < initial_lunge_distance, "Caught creature lunges into the camera")
	check(app.creature.model.root.scale.x > 1.08, "Capture enlarges the creature during impact")
	check(app.creature.model.arms[0].rotation.x > 0.45, "Creature reaches toward the player during its lunge")
	check(not is_zero_approx(app.player.camera.rotation.z), "Full effects add a brief camera jolt")
	app._update_death(2.1)
	check(app.state == "result" and not app.scare_flash.visible, "Capture fades to a retry result screen")
	app.start_run(1, 0, 901)
	await frames(app, 2)
	check(app.fuses == 0 and app.player.loaded_count() == 2 and app.elapsed < 1, "Retry resets inventory, objective and session state")
	app.progress.settings.reduced_effects = true
	app.player.settings = app.progress.settings
	app.die()
	check(app.state == "dying" and not app.scare_flash.visible, "Reduced effects keep the scare but suppress its flash")
	app._update_death(0.2)
	check(is_zero_approx(app.player.camera.rotation.z), "Reduced effects suppress camera shake")
	app._update_death(2.1)
	app.progress.settings.reduced_effects = original_reduced_effects
	app.start_run(1, 0, 901)
	await frames(app, 2)
	# Progression is awarded only on completion.
	app.fuses = int(app.config.fuses)
	app.elapsed = 93
	app._finish_escape()
	check(app.progress.unlocked >= 2, "Winning B3 unlocks B4")
	app.start_run(2, 0, 1001)
	await frames(app, 2)
	check(app.world.breakables.size() > 0, "B4 contains breakable partitions")
	var broken: Vector2i = app.world.maze.breakable_cells[0]
	check(app.world.break_wall(broken), "Partition breaks once")
	check(app.world.maze.is_open(broken), "Broken wall immediately updates authoritative navigation grid")
	check(not app.world.break_wall(broken), "A partition cannot spawn infinite batteries")
	app.start_run(3, 0, 1002)
	await frames(app, 2)
	check(not bool(app.config.compass) and int(app.config.fuses) == 5, "B5 has its own difficulty and disabled compass")
	check(app.player.slots.size() == 1, "Deeper sectors reduce taser capacity")
	app.start_run(-1, 1, 1003)
	await frames(app, 2)
	app.fuses = int(app.config.fuses)
	app._finish_escape()
	check(app.endless_floor == 2 and app.state == "playing", "Endless completion advances to a fresh floor")
	check(app.fuses == 0 and app.progress.endless_best >= 1, "Endless record counts completed floors and inventory resets")
	# Save/load round trip, then restore the user's original file byte-for-byte.
	app.progress.settings.volume = 0.35
	app.progress.save_progress()
	var roundtrip = Progress.new()
	roundtrip.load_progress()
	check(is_equal_approx(roundtrip.settings.volume, 0.35), "Volume preference survives save/load")
	check(roundtrip.unlocked == app.progress.unlocked, "Unlocks survive save/load")
	check(roundtrip.best.has("1"), "Sector records survive save/load")
	app.return_to_menu()
	app.progress.unlocked = original_unlocks
	app.progress.best = original_best
	app.progress.endless_best = original_endless
	app.progress.settings = original_settings
	if had_save:
		var file := FileAccess.open(Progress.PATH, FileAccess.WRITE)
		file.store_buffer(original_bytes)
		file.close()
	else:
		DirAccess.remove_absolute(Progress.PATH)
	app._apply_preferences()
	app.ui.refresh_sector()
	app.get_viewport().disable_3d = false
	return {"passed": passed, "failed": failures.size(), "failures": failures, "engine": Engine.get_version_info().string}

func _test_mazes() -> void:
	for sector in range(4):
		var cfg: Dictionary = Levels.sector(sector)
		for map_seed in range(1, 17):
			var maze = Maze.new()
			maze.generate(cfg, map_seed)
			var distances: PackedInt32Array = maze.distances_from(maze.spawn)
			check(maze.width % 2 == 1, "Maze dimensions stay odd")
			check(maze.width == int(cfg.size), "Sector uses the enlarged configured maze size")
			var connected: bool = true
			for cell in maze.floor_cells:
				if distances[cell.y * maze.width + cell.x] < 0:
					connected = false
			check(connected, "Every floor tile is connected: sector=%d seed=%d" % [sector, map_seed])
			var perimeter_closed: bool = true
			for i in range(maze.width):
				for cell in [Vector2i(i, 0), Vector2i(0, i), Vector2i(i, maze.width - 1), Vector2i(maze.width - 1, i)]:
					perimeter_closed = perimeter_closed and not maze.is_open(cell)
			check(perimeter_closed, "Outer walls never have gaps")
			var used: Dictionary = {maze.spawn: true, maze.exit_cell: true, maze.enemy_cell: true}
			var unique: bool = used.size() == 3
			var reachable: bool = true
			for cell in maze.fuse_cells + maze.battery_cells:
				unique = unique and not used.has(cell)
				used[cell] = true
				reachable = reachable and maze.is_open(cell) and distances[cell.y * maze.width + cell.x] >= 0
			check(unique, "Items and spawn points do not overlap")
			check(reachable, "All required pickups are reachable")
			check(maze.fuse_cells.size() == int(cfg.fuses), "Exact required fuse count")
			check(maze.battery_cells.size() == int(cfg.batteries), "Exact spare battery count")
			var path: Array[Vector2i] = maze.find_path(maze.spawn, maze.exit_cell)
			check(not path.is_empty() and path.back() == maze.exit_cell, "The airlock is reachable without deleting a corridor")
			var valid_path: bool = true
			var previous: Vector2i = maze.spawn
			for cell in path:
				valid_path = valid_path and maze.is_open(cell) and absi(cell.x - previous.x) + absi(cell.y - previous.y) == 1
				previous = cell
			check(valid_path, "Enemy path is contiguous and never crosses a wall")
			check(maze.find_path(maze.spawn, Vector2i.ZERO).is_empty(), "Pathfinding safely rejects a wall goal")
			var twin = Maze.new()
			twin.generate(cfg, map_seed)
			check(twin.cells == maze.cells and twin.fuse_cells == maze.fuse_cells, "A seed reproduces layout and item positions")
	var random_a = Maze.new()
	var random_b = Maze.new()
	var random_cfg: Dictionary = Levels.sector(1)
	random_a.generate(random_cfg, 8713)
	random_b.generate(random_cfg, 8714)
	check(random_a.cells != random_b.cells, "Different seeds produce different random maze layouts")
	for floor_number in [1, 2, 3, 8, 20, 60]:
		var cfg: Dictionary = Levels.endless(floor_number)
		var maze = Maze.new()
		maze.generate(cfg, 707)
		check(maze.fuse_cells.size() == int(cfg.fuses), "Endless floors remain playable as difficulty grows")
		check(maze.width <= 35 and float(cfg.chase) < 4.65, "Endless difficulty has fair bounds")

func _test_corner_navigation(app, creature) -> void:
	var start_cell := Vector2i.ZERO
	var goal_cell := Vector2i.ZERO
	var route: Array[Vector2i] = []
	var first_direction := Vector2i.ZERO
	var turn_cell := Vector2i.ZERO
	var found_turn := false
	for start in app.world.maze.floor_cells:
		for goal in app.world.maze.floor_cells:
			var candidate: Array[Vector2i] = app.world.maze.find_path(start, goal)
			if candidate.size() < 3:
				continue
			var direction: Vector2i = candidate[0] - start
			for i in range(1, candidate.size()):
				var next_direction: Vector2i = candidate[i] - candidate[i - 1]
				if next_direction != direction:
					start_cell = start
					goal_cell = goal
					route = candidate
					first_direction = direction
					turn_cell = candidate[i - 1]
					found_turn = true
					break
			if found_turn:
				break
		if found_turn:
			break
	check(found_turn, "Navigation test finds a route with a right-angle corner")
	var saved_position: Vector3 = creature.global_position
	var saved_target: Vector2i = creature.target
	var saved_state: String = creature.state
	var saved_path: Array[Vector2i] = creature.path.duplicate()
	var saved_recovery: bool = creature.recovering_from_stuck
	var saved_recovery_target: Vector3 = creature.recovery_target
	var saved_recovery_cell: Vector2i = creature.recovery_cell
	var saved_recovery_attempts: int = creature.recovery_attempts
	var saved_aligned_cell: Vector2i = creature.aligned_cell
	var saved_awake_time: float = creature.awake_time
	var saved_sense_timer: float = creature.sense_timer
	var saved_path_timer: float = creature.path_timer
	var saved_stuck_time: float = creature.stuck_time
	var saved_velocity: Vector3 = creature.velocity
	var saved_player_position: Vector3 = app.player.global_position
	var saved_player_active: bool = app.player.active
	var was_active: bool = creature.active
	creature.active = false
	creature.global_position = Maze.to_world(start_cell, 0.03)
	creature.target = goal_cell
	creature.state = "patrol"
	creature.recovering_from_stuck = false
	creature.aligned_cell = Vector2i(-1, -1)
	creature.path = route.duplicate()
	var aimed_cell: Vector2i = Maze.to_cell(creature.navigation_aim())
	var aimed_offset: Vector2i = aimed_cell - start_cell
	check(
		(aimed_offset.x == 0 or aimed_offset.y == 0)
		and aimed_offset.x * first_direction.x + aimed_offset.y * first_direction.y > 0,
		"Creature follows the first straight corridor instead of cutting across a corner"
	)
	var turn_path: Array[Vector2i] = app.world.maze.find_path(turn_cell, goal_cell)
	var entering_turn_cell: Vector3 = Maze.to_world(turn_cell, 0.03) - Vector3(first_direction.x, 0, first_direction.y) * 0.70
	creature.global_position = entering_turn_cell
	creature.target = goal_cell
	creature.path = turn_path
	check(Maze.to_cell(creature.global_position) == turn_cell, "Turn test places the creature off-centre inside the corner cell")
	var corner_aim: Vector3 = creature.navigation_aim()
	check(
		corner_aim.is_equal_approx(Maze.to_world(turn_cell, 0.03)),
		"Creature re-centres in the corner cell before turning into the next corridor"
	)
	var catch_callback := Callable(app, "die")
	var had_catch_callback: bool = creature.caught.is_connected(catch_callback)
	if had_catch_callback:
		creature.caught.disconnect(catch_callback)
	app.player.active = false
	creature.global_position = entering_turn_cell
	creature.target = goal_cell
	creature.path = turn_path.duplicate()
	creature.state = "patrol"
	creature.active = true
	creature.awake_time = 10.0
	creature.sense_timer = 100.0
	creature.path_timer = 100.0
	creature.stuck_time = 0.0
	creature.recovering_from_stuck = false
	creature.recovery_attempts = 0
	creature.recovery_cell = Vector2i(-1, -1)
	creature.velocity = Vector3.ZERO
	await frames(app, 120)
	check(Maze.to_cell(creature.global_position) == turn_path[0], "Monster physically clears the corner and enters the next corridor")
	check(not creature.recovering_from_stuck, "Following the centered turn route does not invoke stuck recovery")
	if had_catch_callback:
		creature.caught.connect(catch_callback)
	app.player.global_position = saved_player_position
	app.player.active = saved_player_active
	creature.active = false
	var off_center: Vector3 = Maze.to_world(start_cell, 0.03) + Vector3(first_direction.x, 0, first_direction.y) * 0.70
	creature.global_position = off_center
	await frames(app, 1)
	creature._begin_stuck_recovery()
	check(creature.recovering_from_stuck, "Stuck recovery picks a capsule-clear nearby cell centre")
	check(Maze.to_cell(creature.recovery_target) == start_cell, "Corner recovery recentres in the current open cell first")
	creature.recovering_from_stuck = saved_recovery
	creature.recovery_target = saved_recovery_target
	creature.recovery_cell = saved_recovery_cell
	creature.recovery_attempts = saved_recovery_attempts
	creature.aligned_cell = saved_aligned_cell
	creature.active = was_active
	creature.global_position = saved_position
	creature.target = saved_target
	creature.state = saved_state
	creature.path = saved_path
	creature.recovering_from_stuck = saved_recovery
	creature.awake_time = saved_awake_time
	creature.sense_timer = saved_sense_timer
	creature.path_timer = saved_path_timer
	creature.stuck_time = saved_stuck_time
	creature.velocity = saved_velocity
	app.player.global_position = saved_player_position
	app.player.active = saved_player_active

func _test_junction_approach(app, creature) -> void:
	var intersection_cell := Vector2i.ZERO
	var found := false
	for y in range(1, app.world.maze.width - 2):
		for x in range(1, app.world.maze.width - 2):
			var cell := Vector2i(x, y)
			var junction_is_open: bool = (
				app.world.maze.is_open(cell)
				and app.world.maze.is_open(cell + Vector2i.RIGHT)
				and app.world.maze.is_open(cell + Vector2i.DOWN)
				and app.world.maze.is_open(cell + Vector2i(1, 1))
			)
			if junction_is_open:
				intersection_cell = cell
				found = true
				break
		if found:
			break
	check(found, "Navigation test finds a clear four-cell junction")
	if not found:
		return
	var saved_player_position: Vector3 = app.player.global_position
	var saved_enemy_position: Vector3 = creature.global_position
	var saved_state: String = creature.state
	var saved_target: Vector2i = creature.target
	var saved_memory: Vector3 = creature.last_known
	var saved_memory_time: float = creature.memory
	var saved_sense_timer: float = creature.sense_timer
	var saved_path_timer: float = creature.path_timer
	var saved_awake_time: float = creature.awake_time
	var saved_velocity: Vector3 = creature.velocity
	var saved_path: Array[Vector2i] = []
	for step in creature.path:
		saved_path.append(step)
	var junction_x: float = float(intersection_cell.x + 1) * Maze.CELL_SIZE
	var junction_z: float = float(intersection_cell.y + 1) * Maze.CELL_SIZE
	var junction := Vector3(junction_x, 0.03, junction_z)
	creature.global_position = Maze.to_world(intersection_cell, 0.03)
	app.player.global_position = junction
	creature.last_known = junction
	creature.target = Maze.to_cell(junction)
	creature.state = "chase"
	creature.memory = 3.6
	creature.path_timer = 0.0
	creature.path.clear()
	check(creature._can_steer_to_memory(), "A visible four-way target bypasses cell-center steering")
	check(creature.navigation_aim().is_equal_approx(junction), "Pursuit aims at the player's sub-cell junction position")
	var distance_before: float = creature.global_position.distance_to(junction)
	var catch_callback := Callable(app, "die")
	var had_catch_callback: bool = creature.caught.is_connected(catch_callback)
	if had_catch_callback:
		creature.caught.disconnect(catch_callback)
	await frames(app, 60)
	if had_catch_callback:
		creature.caught.connect(catch_callback)
	var distance_after: float = creature.global_position.distance_to(junction)
	check(distance_after < distance_before - 0.25, "Creature closes smoothly on a player at the junction")
	check(distance_after < 0.18, "Creature converges instead of orbiting the stationary junction target")
	var destination_cell_center: Vector3 = Maze.to_world(Maze.to_cell(junction), 0.03)
	check(creature.global_position.distance_to(destination_cell_center) > 1.0, "Creature reaches the sub-cell target without snapping to its center")
	app.player.global_position = saved_player_position
	creature.global_position = saved_enemy_position
	creature.state = saved_state
	creature.target = saved_target
	creature.last_known = saved_memory
	creature.memory = saved_memory_time
	creature.sense_timer = saved_sense_timer
	creature.path_timer = saved_path_timer
	creature.awake_time = saved_awake_time
	creature.velocity = saved_velocity
	creature.path = saved_path

func _test_touch(app) -> void:
	var controls = app.ui.touch
	var was_enabled: bool = app.touch_enabled
	app.touch_enabled = true
	controls.show()
	_touch(controls, 0, Vector2(135, 569), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = controls.get_global_transform_with_canvas() * Vector2(135, 509)
	drag.relative = Vector2(0, -60)
	controls._input(drag)
	check(app.player.touch_move.y < -0.8, "Touch stick moves forward")
	_touch(controls, 1, Vector2(266, 588), true)
	check(app.player.touch_sprint, "A second finger can hold sprint")
	_touch(controls, 2, Vector2(650, 360), true)
	drag.index = 2
	drag.relative = Vector2(22, -7)
	var look_before: Vector2 = app.player.mouse_buffer
	controls._input(drag)
	check(app.player.mouse_buffer != look_before, "A third finger can look while moving")
	_touch(controls, 2, Vector2(650, 360), false)
	check(controls.look_id == -1 and controls.move_id == 0, "Releasing look does not release movement")
	_touch(controls, 1, Vector2(266, 588), false)
	check(not app.player.touch_sprint and app.player.touch_move.length() > 0, "Releasing sprint leaves movement active")
	_touch(controls, 0, Vector2(135, 509), false)
	check(app.player.touch_move == Vector2.ZERO, "Touch release stops the joystick")
	_touch(controls, 3, Vector2(1057, 463), true)
	check(app.map_visible, "Touch map button uses the real map action")
	_touch(controls, 3, Vector2(1057, 463), false)
	_touch(controls, 3, Vector2(1057, 463), true)
	_touch(controls, 3, Vector2(1057, 463), false)
	var flashlight_before: bool = app.player.flashlight
	_touch(controls, 4, Vector2(1148, 463), true)
	check(app.player.flashlight != flashlight_before, "Touch flashlight button works")
	_touch(controls, 4, Vector2(1148, 463), false)
	_touch(controls, 4, Vector2(1148, 463), true)
	_touch(controls, 4, Vector2(1148, 463), false)
	_touch(controls, 0, Vector2(135, 509), true)
	_touch(controls, 1, Vector2(266, 588), true)
	_touch(controls, 5, Vector2(1201, 112), true)
	check(app.state == "paused" and not controls.visible, "Touch pause opens native settings")
	check(app.player.touch_move == Vector2.ZERO and not app.player.touch_sprint, "Pause cancels every held touch")
	check(controls.move_id == -1 and controls.look_id == -1 and controls.held.is_empty(), "Pause clears finger ownership")
	app.resume_game()
	app.player.mouse_buffer = Vector2.ZERO
	app.touch_enabled = was_enabled
	controls.visible = was_enabled

func _touch(controls, id: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = controls.get_global_transform_with_canvas() * position
	event.pressed = pressed
	controls._input(event)
