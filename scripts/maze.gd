extends RefCounted
## Seeded maze generation and BFS share one authoritative grid with rendering,
## AI, fog-of-war and tests. Exit placement never replaces a walkable cell.

const DIRECTIONS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CELL_SIZE: float = 2.65
var width: int
var cells := PackedByteArray()
var floor_cells: Array[Vector2i] = []
var spawn := Vector2i(1, 1)
var exit_cell := Vector2i.ZERO
var enemy_cell := Vector2i.ZERO
var fuse_cells: Array[Vector2i] = []
var battery_cells: Array[Vector2i] = []
var breakable_cells: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()
var generation_seed: int

func generate(config: Dictionary, map_seed: int) -> void:
	generation_seed = map_seed
	rng.seed = map_seed
	width = int(config.size) | 1
	cells.resize(width * width)
	cells.fill(1)
	floor_cells.clear()
	fuse_cells.clear()
	battery_cells.clear()
	breakable_cells.clear()
	set_cell(spawn, 0)
	var stack: Array[Vector2i] = [spawn]
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var choices: Array[Vector2i] = []
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction * 2
			if inside(next) and not is_open(next):
				choices.append(direction)
		if choices.is_empty():
			stack.pop_back()
			continue
		var direction: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
		set_cell(current + direction, 0)
		set_cell(current + direction * 2, 0)
		stack.append(current + direction * 2)
	# Extra connections remove long forced backtracking while preserving the rim.
	for y in range(1, width - 1):
		for x in range(1, width - 1):
			var c := Vector2i(x, y)
			if not is_open(c) and rng.randf() < 0.27:
				if _bridges_corridors(c):
					set_cell(c, 0)
	# A few maintenance rooms break up the narrow corridors.
	for room in range(maxi(1, width / 9)):
		var origin := Vector2i(rng.randi_range(2, width - 4), rng.randi_range(2, width - 4))
		for y in range(origin.y, origin.y + 3):
			for x in range(origin.x, origin.x + 3):
				set_cell(Vector2i(x, y), 0)
	_rebuild_floor_cells()
	var distances := distances_from(spawn)
	exit_cell = spawn
	for c in floor_cells:
		if distances[_index(c)] > distances[_index(exit_cell)]:
			exit_cell = c
	var used: Array[Vector2i] = [spawn, exit_cell]
	# First fuse gives a nearby, readable objective rather than a random dead end.
	var candidates: Array[Vector2i] = []
	for c in floor_cells:
		if not used.has(c) and distances[_index(c)] >= 2 and distances[_index(c)] <= 5:
			candidates.append(c)
	var first: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	fuse_cells.append(first)
	used.append(first)
	for i in range(1, int(config.fuses)):
		var best_cell := Vector2i.ZERO
		var best_score: float = -1.0
		var separation_maps: Array[PackedInt32Array] = []
		for placed in fuse_cells:
			separation_maps.append(distances_from(placed))
		for c in floor_cells:
			if used.has(c):
				continue
			var separation: float = float(distances[_index(c)])
			for map in separation_maps:
				separation = minf(separation, float(map[_index(c)]))
			var score: float = separation + rng.randf() * 2.0
			if score > best_score:
				best_score = score
				best_cell = c
		fuse_cells.append(best_cell)
		used.append(best_cell)
	var available: Array[Vector2i] = []
	for c in floor_cells:
		if not used.has(c):
			available.append(c)
	for i in range(int(config.batteries)):
		if available.is_empty():
			break
		var index := rng.randi_range(0, available.size() - 1)
		var c: Vector2i = available[index]
		available.remove_at(index)
		battery_cells.append(c)
		used.append(c)
	var farthest: int = -1
	for c in floor_cells:
		if not used.has(c) and distances[_index(c)] > farthest:
			farthest = distances[_index(c)]
			enemy_cell = c
	var break_candidates: Array[Vector2i] = []
	for y in range(2, width - 2):
		for x in range(2, width - 2):
			var c := Vector2i(x, y)
			if not is_open(c) and _bridges_corridors(c):
				break_candidates.append(c)
	for i in range(int(config.breakables)):
		if break_candidates.is_empty():
			break
		var index := rng.randi_range(0, break_candidates.size() - 1)
		breakable_cells.append(break_candidates[index])
		break_candidates.remove_at(index)

func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x

func inside(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < width - 1 and cell.y < width - 1

func is_open(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= width:
		return false
	return cells[_index(cell)] == 0

func set_cell(cell: Vector2i, value: int) -> void:
	cells[_index(cell)] = value

func _bridges_corridors(c: Vector2i) -> bool:
	return (is_open(c + Vector2i.LEFT) and is_open(c + Vector2i.RIGHT)) or (is_open(c + Vector2i.UP) and is_open(c + Vector2i.DOWN))

func _rebuild_floor_cells() -> void:
	floor_cells.clear()
	for y in range(1, width - 1):
		for x in range(1, width - 1):
			var c := Vector2i(x, y)
			if is_open(c):
				floor_cells.append(c)

func open_wall(cell: Vector2i) -> bool:
	if not breakable_cells.has(cell):
		return false
	breakable_cells.erase(cell)
	set_cell(cell, 0)
	floor_cells.append(cell)
	return true

func distances_from(start: Vector2i) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(width * width)
	distances.fill(-1)
	if not is_open(start):
		return distances
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	distances[_index(start)] = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if is_open(next) and distances[_index(next)] == -1:
				distances[_index(next)] = distances[_index(current)] + 1
				queue.append(next)
	return distances

func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not is_open(start) or not is_open(goal) or start == goal:
		return path
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == goal:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if is_open(next) and not previous.has(next):
				previous[next] = current
				queue.append(next)
	if not previous.has(goal):
		return path
	var current := goal
	while current != start:
		path.push_front(current)
		current = previous[current]
	return path

static func to_world(cell: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, height, (cell.y + 0.5) * CELL_SIZE)

static func to_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
