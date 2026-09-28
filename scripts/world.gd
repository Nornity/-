extends Node3D

const Maze = preload("res://scripts/maze.gd")
const Models = preload("res://scripts/models.gd")
const HEIGHT: float = 3.25
var maze = Maze.new()
var config: Dictionary = {}
var items: Array[Dictionary] = []
var breakables: Dictionary = {}
var door: Dictionary = {}
var explored := PackedByteArray()
var elapsed: float = 0.0
var playing: bool = false
var lamps: Array[OmniLight3D] = []
var reduced_effects: bool = false
var explore_timer: float = 0.0

func build(sector: Dictionary, map_seed: int) -> void:
	config = sector
	maze.generate(config, map_seed)
	explored.resize(maze.width * maze.width)
	explored.fill(0)
	var span: float = maze.width * Maze.CELL_SIZE
	var floor_mat := Models.material(Color("c5cfca"), "floor")
	floor_mat.uv1_scale = Vector3(maze.width / 2.0, maze.width / 2.0, 1)
	var floor_size := Vector3(span, 0.20, span)
	var floor_position := Vector3(span * 0.5, -0.10, span * 0.5)
	Models.box(self, floor_size, floor_position, floor_mat)
	Models.collision_box(self, floor_size, floor_position)
	Models.box(self, Vector3(span, 0.14, span), Vector3(span * 0.5, HEIGHT + 0.07, span * 0.5), Models.material(Color("202a2d")))
	var wall_positions: Array[Vector3] = []
	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	add_child(wall_body)
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(Maze.CELL_SIZE, HEIGHT, Maze.CELL_SIZE)
	for y in range(maze.width):
		for x in range(maze.width):
			var c := Vector2i(x, y)
			if maze.is_open(c):
				continue
			var at: Vector3 = Maze.to_world(c, HEIGHT * 0.5)
			if maze.breakable_cells.has(c):
				var root := Node3D.new()
				root.position = at
				add_child(root)
				Models.box(root, bounds.size, Vector3.ZERO, Models.material(Color("e4c7a0"), "cracked"))
				Models.collision_box(root, bounds.size, Vector3.ZERO)
				breakables[c] = root
			else:
				wall_positions.append(at)
				var shape := CollisionShape3D.new()
				shape.shape = bounds
				shape.position = at
				wall_body.add_child(shape)
	_batch_boxes(wall_positions, bounds.size, Models.material(Color("d4ded8"), "concrete"))
	var base_positions: Array[Vector3] = []
	for at in wall_positions:
		base_positions.append(Vector3(at.x, 0.18, at.z))
	_batch_boxes(base_positions, Vector3(Maze.CELL_SIZE + 0.025, 0.20, Maze.CELL_SIZE + 0.025), Models.material(Color("283334")))
	_decorate()
	for c in maze.fuse_cells:
		add_pickup("fuse", c)
	for c in maze.battery_cells:
		add_pickup("battery", c)
	_place_airlock()

func _batch_boxes(positions: Array[Vector3], dimensions: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = mat
	var transforms: Array[Transform3D] = []
	for at in positions:
		transforms.append(Transform3D(Basis.IDENTITY, at))
	_batch_mesh(transforms, mesh)

func _batch_mesh(transforms: Array[Transform3D], mesh: Mesh, shadows: bool = true) -> void:
	# Small spatial chunks let Compatibility correctly cull local lights and
	# off-camera corridors instead of lighting one maze-sized MultiMesh.
	var chunks: Dictionary = {}
	for transform in transforms:
		var key := Vector2i(floori(transform.origin.x / 12.0), floori(transform.origin.z / 12.0))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(transform)
	for chunk in chunks.values():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = mesh
		instances.instance_count = chunk.size()
		for i in range(chunk.size()):
			instances.set_instance_transform(i, chunk[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = instances
		if not shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

func _decorate() -> void:
	var pipe_material := Models.material(Color("88604a"), "metal")
	var indices: int = 0
	var pipes: Array[Transform3D] = []
	for c in maze.floor_cells:
		indices += 1
		var at: Vector3 = Maze.to_world(c)
		if maze.is_open(c + Vector2i.DOWN) or maze.is_open(c + Vector2i.UP):
			pipes.append(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(-0.80, 2.96, 0)))
		else:
			pipes.append(Transform3D(Basis(Vector3.BACK, PI * 0.5), at + Vector3(0, 2.96, -0.80)))
		if indices % 27 == 0 and lamps.size() < 9:
			var light_color := Color("cf6651") if indices % 2 == 0 else Color("a2c0ae")
			lamps.append(Models.lamp(self, at + Vector3(0, 3.02, 0), light_color, 1.2, 6.0))
		if indices % 13 == 0:
			_place_panel(c, "%s / %02d" % [config.code, indices % 100])
	var pipe_mesh := CylinderMesh.new()
	pipe_mesh.top_radius = 0.066
	pipe_mesh.bottom_radius = 0.066
	pipe_mesh.height = Maze.CELL_SIZE
	pipe_mesh.radial_segments = 8
	pipe_mesh.rings = 1
	pipe_mesh.material = pipe_material
	_batch_mesh(pipes, pipe_mesh, false)
	lamps.append(Models.lamp(self, Maze.to_world(maze.spawn, 2.98), Color("b5d0bd"), 1.65, 8.5))
	_place_panel(maze.spawn, "ОБЪЕКТ 07\n" + config.code)

func _place_panel(cell: Vector2i, text: String) -> void:
	for direction in Maze.DIRECTIONS:
		if maze.is_open(cell + direction) or maze.breakable_cells.has(cell + direction):
			continue
		var root := Node3D.new()
		add_child(root)
		root.position = Maze.to_world(cell, 1.80) + Vector3(direction.x, 0, direction.y) * (Maze.CELL_SIZE * 0.5 - 0.035)
		root.rotation.y = atan2(-direction.x, -direction.y)
		Models.box(root, Vector3(0.80, 0.44, 0.025), Vector3.ZERO, Models.material(Color("273537")))
		Models.sign_text(root, text, Vector3(0, 0.01, 0.022), 27, Color("95a59d"))
		break

func _place_airlock() -> void:
	door = Models.airlock(self, config.code)
	var dir := Vector2i.UP
	for candidate in Maze.DIRECTIONS:
		if not maze.is_open(maze.exit_cell + candidate):
			dir = candidate
			break
	door.root.position = Maze.to_world(maze.exit_cell) + Vector3(dir.x, 0, dir.y) * 1.06
	door.root.rotation.y = atan2(-dir.x, -dir.y)
	Models.box(door.root, Vector3(1.96, 2.45, 0.05), Vector3(0, 1.24, -0.13), Models.material(Color("d2c19a"), "", 1.3))

func add_pickup(kind: String, cell: Vector2i) -> Dictionary:
	var holder := Node3D.new()
	holder.position = Maze.to_world(cell)
	add_child(holder)
	Models.box(holder, Vector3(0.47, 0.52, 0.47), Vector3(0, 0.26, 0), Models.material(Color("546263"), "metal"))
	var model := Models.pickup(kind)
	holder.add_child(model)
	model.position.y = 0.85
	var color := Color("d9b373") if kind == "fuse" else Color("8cc8b1")
	var label := Models.sign_text(holder, "ПРЕДОХРАНИТЕЛЬ" if kind == "fuse" else "БАТАРЕЯ", Vector3(0, 1.36, 0), 19, color)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	var item := {"kind": kind, "cell": cell, "root": holder, "model": model, "label": label, "taken": false, "phase": float(items.size()) * 1.72}
	items.append(item)
	return item

func take_item(item: Dictionary) -> bool:
	if item.is_empty() or item.taken:
		return false
	item.taken = true
	item.model.visible = false
	item.label.visible = false
	return true

func break_wall(cell: Vector2i) -> bool:
	if not maze.open_wall(cell):
		return false
	if breakables.has(cell):
		breakables[cell].queue_free()
		breakables.erase(cell)
	add_pickup("battery", cell)
	return true

func unlock_door() -> void:
	door.status.material_override = Models.material(Color("9dd7ad"), "", 1.8)
	door.light.light_color = Color("abd9ba")

func animate_door(amount: float) -> void:
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		door.leaves[i].position.x = side * (0.5 + amount * 0.99)

func line_of_sight(start: Vector3, end: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func reveal(position_3d: Vector3, yaw: float, delta: float) -> void:
	explore_timer -= delta
	if explore_timer > 0.0:
		return
	explore_timer = 0.15
	for i in range(56):
		var angle: float = yaw + lerpf(-1.18, 1.18, i / 55.0)
		var direction := Vector3(-sin(angle), 0, -cos(angle))
		for step in range(1, 23):
			var p: Vector3 = position_3d + direction * (step * 0.4)
			var c: Vector2i = Maze.to_cell(p)
			if c.x < 0 or c.y < 0 or c.x >= maze.width or c.y >= maze.width:
				break
			explored[c.y * maze.width + c.x] = 1
			if not maze.is_open(c):
				break

func nearest_interaction(player) -> Dictionary:
	var origin: Vector3 = player.camera.global_position
	var forward: Vector3 = -player.camera.global_basis.z
	var nearest: Dictionary = {}
	var nearest_distance: float = 2.3
	for item in items:
		if item.taken:
			continue
		var aim: Vector3 = item.root.global_position + Vector3(0, 0.90, 0)
		var distance: float = origin.distance_to(aim)
		if distance < nearest_distance and forward.dot((aim - origin).normalized()) > 0.46 and line_of_sight(origin, aim):
			nearest_distance = distance
			nearest = {"kind": item.kind, "item": item}
	if not nearest.is_empty():
		return nearest
	var door_aim: Vector3 = door.root.global_position + Vector3(0, 1.2, 0)
	if origin.distance_to(door_aim) < 2.6 and forward.dot((door_aim - origin).normalized()) > 0.28 and line_of_sight(origin, door_aim):
		return {"kind": "exit"}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 2.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var cell: Vector2i = Maze.to_cell(hit.position - hit.normal * 0.06)
		if breakables.has(cell):
			return {"kind": "wall", "cell": cell}
	return {}

func objective(player_position: Vector3, all_fuses: bool) -> Dictionary:
	if all_fuses:
		return {"position": Maze.to_world(maze.exit_cell, 1.0), "label": "АВАРИЙНЫЙ ШЛЮЗ"}
	var best: float = INF
	var result: Dictionary = {}
	for item in items:
		if item.kind != "fuse" or item.taken:
			continue
		var distance: float = player_position.distance_squared_to(item.root.position)
		if distance < best:
			best = distance
			result = {"position": item.root.position, "label": "ПРЕДОХРАНИТЕЛЬ"}
	return result

func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	for item in items:
		if item.taken:
			continue
		item.model.rotation.y += delta * 0.5
		item.model.position.y = 0.85 + sin(elapsed * 1.8 + item.phase) * 0.055
	for i in range(lamps.size()):
		var base: float = 1.65 if i == lamps.size() - 1 else 1.2
		lamps[i].light_energy = base if reduced_effects else base * (0.90 + 0.10 * sin(elapsed * 1.6 + i * 17.7))

func build_diorama() -> Camera3D:
	var concrete := Models.material(Color("dbe2d8"), "concrete")
	concrete.uv1_scale = Vector3(1, 1, 1)
	var floor_mat := Models.material(Color("c2cdcc"), "floor")
	floor_mat.uv1_scale = Vector3(2, 12, 1)
	Models.box(self, Vector3(5.8, 0.16, 40), Vector3(0, -0.08, -12), floor_mat)
	Models.box(self, Vector3(5.8, 0.15, 40), Vector3(0, 3.4, -12), Models.material(Color("253336")))
	var frame_mat := Models.material(Color("465856"), "metal")
	for i in range(12):
		var z: float = 5.0 - i * 3.0
		for x in [-2.9, 2.9]:
			Models.box(self, Vector3(0.22, 3.4, 3.0), Vector3(x, 1.7, z), concrete)
			Models.box(self, Vector3(0.18, 3.36, 0.18), Vector3(x - signf(x) * 0.19, 1.68, z + 1.5), frame_mat)
			Models.box(self, Vector3(0.22, 0.18, 3.0), Vector3(x - signf(x) * 0.10, 0.21, z), frame_mat)
		Models.box(self, Vector3(5.55, 0.18, 0.18), Vector3(0, 3.26, z + 1.5), frame_mat)
	for x in [-2.3, -1.92, 2.24]:
		var pipe := Models.cylinder(self, 0.10, 37, Vector3(x, 2.97, -11), Models.material(Color("796451"), "metal"))
		pipe.rotation.x = PI * 0.5
	Models.lamp(self, Vector3(1, 3.14, 1.5), Color("7aa6a2"), 2.3, 12)
	Models.lamp(self, Vector3(0, 3.14, -6), Color("b7cbb1"), 1.8, 8)
	Models.lamp(self, Vector3(0, 3.14, -13.5), Color("d86043"), 2.2, 9)
	var end_door := Models.airlock(self, "B3")
	end_door.root.position.z = -23
	end_door.light.light_energy = 3.0
	Models.box(self, Vector3(5.8, 3.4, 0.25), Vector3(0, 1.7, -23.3), concrete)
	# Maintenance cabinet, warning stripes and a slack cable along the right wall.
	Models.box(self, Vector3(0.35, 1.4, 0.90), Vector3(2.52, 1.2, -2.4), frame_mat)
	for y in range(8):
		Models.box(self, Vector3(0.38, 0.032, 0.65), Vector3(2.5, 1.45 + y * 0.065, -2.4), Models.material(Color("1f2b2e")))
	for i in range(18):
		var at := Vector3(2.64, 1.10 + sin(i * 0.3) * 0.12, 4 - i * 1.45)
		var cable := Models.cylinder(self, 0.027, 1.5, at, Models.material(Color("191f20")))
		cable.rotation.x = PI * 0.5
	var plaque := Node3D.new()
	add_child(plaque)
	plaque.position = Vector3(2.76, 1.85, -6.5)
	plaque.rotation.y = -PI * 0.5
	Models.box(plaque, Vector3(1.26, 0.87, 0.03), Vector3.ZERO, Models.material(Color("273536")))
	Models.sign_text(plaque, "НЕ ШУМЕТЬ\nОБЪЕКТ 07", Vector3(0, 0, 0.024), 42, Color("c1b59c"))
	var figure := Models.creature("blind")
	add_child(figure.root)
	figure.root.position = Vector3(0.8, 0, -16.7)
	figure.root.rotation.y = 0.20
	figure.head.rotation.z = 0.24
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-0.95, 1.55, 5.0)
	camera.look_at(Vector3(0.95, 1.63, -16.0))
	camera.fov = 68
	camera.current = true
	return camera
