extends Control

const Models = preload("res://scripts/models.gd")
const Progress = preload("res://scripts/progress.gd")
const Maze = preload("res://scripts/maze.gd")
const INK := Color("dedfcf")
const MUTED := Color("8caaa6")
const RED := Color("e57c5f")
const GREEN := Color("a9d7ba")
const AMBER := Color("d6b779")
var app
var mono: FontFile
var heading: FontFile

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mono = Models.font()
	heading = Models.font(true)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func text(value: String, at: Vector2, color: Color = INK, font_size: int = 13, big: bool = false) -> void:
	var face: Font = heading if big else mono
	draw_string(face, at + Vector2(0, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.015, 0.025, 0.028, 0.95))
	draw_string(face, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func centered(value: String, y: float, color: Color = INK, font_size: int = 13) -> void:
	var width: float = mono.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text(value, Vector2(640 - width * 0.5, y), color, font_size)

func segments(at: Vector2, width: float, value: float, color: Color, count: int = 20) -> void:
	var segment_width: float = (width - (count - 1) * 3) / count
	for i in range(count):
		var used: bool = (i + 0.5) / count <= value
		draw_rect(Rect2(at + Vector2(i * (segment_width + 3), 0), Vector2(segment_width, 6)), color if used else Color(0.17, 0.24, 0.24, 0.65))

func _draw() -> void:
	if app == null or not is_instance_valid(app.player):
		return
	var p = app.player
	var cfg: Dictionary = app.config
	if app.state == "opening":
		draw_rect(Rect2(0, 0, 1280, 58), Color("080e10"))
		draw_rect(Rect2(0, 658, 1280, 62), Color("080e10"))
		centered(app.cinematic_caption, 693, INK, 16)
		text("ОБЪЕКТ 07 / " + str(cfg.code), Vector2(40, 36), MUTED, 12)
		return
	if app.state == "dying":
		centered("С И Г Н А Л   П О Т Е Р Я Н", 617, RED, 14)
		return
	if app.state != "playing" and app.state != "paused":
		return
	draw_rect(Rect2(39, 34, 3, 48), RED)
	text("ОБЪЕКТ 07   /   " + str(cfg.code), Vector2(54, 47), MUTED, 11)
	text("НАЙДИТЕ ШЛЮЗ" if app.fuses >= int(cfg.fuses) else "ВОССТАНОВИТЕ ПИТАНИЕ", Vector2(53, 77), INK, 24, true)
	for i in range(int(cfg.fuses)):
		var filled: bool = i < app.fuses
		draw_rect(Rect2(54 + i * 26, 91, 17, 8), AMBER if filled else Color(0.3, 0.38, 0.37, 0.35))
	text("%d / %d" % [app.fuses, int(cfg.fuses)], Vector2(63 + int(cfg.fuses) * 26, 99), AMBER, 12)
	text(Progress.format_time(app.elapsed), Vector2(1160, 48), INK, 21)
	text("СЕНСОРНОЕ УПРАВЛЕНИЕ" if app.touch_enabled else "[M] СКАНЕР  [ESC] ПАУЗА", Vector2(1050, 73), MUTED, 10)
	if bool(cfg.compass):
		_draw_compass()
	else:
		centered("КОМПАС: НЕТ СИГНАЛА", 44, Color("707c7b"), 10)
	if app.map_visible:
		_draw_map()
	if int(cfg.id) == 0:
		draw_rect(Rect2(40, 132, 502, 78), Color(0.025, 0.058, 0.059, 0.91))
		draw_line(Vector2(40, 132), Vector2(542, 132), GREEN, 1)
		text("УЧЕБНЫЙ ПРОТОКОЛ / %02d" % (app.tutorial_step + 1), Vector2(57, 154), GREEN, 10)
		text(app.tutorial_text(), Vector2(57, 183), INK, 12)
	if app.notice_time > 0:
		var message_width: float = mono.get_string_size(app.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(630 - message_width * 0.5, 542, message_width + 20, 32), Color(0.02, 0.035, 0.038, minf(0.92, app.notice_time)))
		centered(app.message, 563, AMBER, 12)
	if not app.interaction.is_empty():
		var caption: String = app.interaction_caption()
		var width: float = mono.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(605 - width * 0.5, 463, width + 70, 42), Color(0.023, 0.045, 0.045, 0.91))
		draw_rect(Rect2(612 - width * 0.5, 471, 25, 25), AMBER, false, 1)
		text("•" if app.touch_enabled else "E", Vector2(620 - width * 0.5, 489), AMBER, 14)
		text(caption, Vector2(650 - width * 0.5, 490), INK, 13)
	# Minimal crosshair, amber when an interaction is possible.
	var cross_color: Color = AMBER if not app.interaction.is_empty() else Color(0.80, 0.85, 0.79, 0.7)
	draw_circle(Vector2(640, 360), 1.4, cross_color)
	for side in [-1, 1]:
		draw_line(Vector2(640 + side * 5, 360), Vector2(640 + side * 9, 360), cross_color, 1)
		draw_line(Vector2(640, 360 + side * 5), Vector2(640, 360 + side * 9), cross_color, 1)
	if is_instance_valid(app.creature):
		if app.creature.state == "chase":
			centered("ОНО ВАС СЛЫШИТ. УХОДИТЕ.", 120, RED, 11)
		elif app.creature.stun_time > 0:
			centered("ОГЛУШЕНО · %.1f С" % app.creature.stun_time, 120, GREEN, 12)
		elif app.fear > 0.25:
			centered("ЧТО-ТО РЯДОМ", 120, Color("ad9a7a"), 10)
	if app.touch_enabled:
		text("СВЕТ %d%%  /  ЗАПАС %d  /  ШОКЕР %d  /  КАМНИ %d" % [int(p.battery), p.reserves, p.loaded_count(), p.rocks], Vector2(450, 688), GREEN, 10)
		centered("ТИШЕ" if p.crouching else ("ГРОМКИЙ БЕГ" if p.sprinting else "ШУМ %d%%" % int(p.noise_level * 100)), 625, AMBER, 10)
		segments(Vector2(532, 646), 216, p.stamina / 100.0, AMBER)
		return
	# Bottom corners: readable equipment and resources, not a full-width dashboard.
	draw_rect(Rect2(39, 606, 255, 81), Color(0.02, 0.035, 0.037, 0.62))
	text("ФОНАРЬ [F]", Vector2(53, 628), MUTED, 10)
	text("%03d%%" % int(p.battery) if p.flashlight else "ВЫКЛ", Vector2(235, 628), AMBER, 12)
	segments(Vector2(54, 640), 224, p.battery / 100.0, GREEN if p.battery > 20 else RED)
	text("ЗАПАС  %d БАТ." % p.reserves, Vector2(54, 671), INK, 11)
	text("ТИХИЙ ШАГ" if p.crouching else ("БЕГ" if p.sprinting else "ХОДЬБА"), Vector2(205, 671), MUTED, 10)
	segments(Vector2(540, 668), 200, p.stamina / 100.0, RED if p.stamina < 25 else Color("9faeac"), 25)
	centered("ВЫНОСЛИВОСТЬ", 690, MUTED, 9)
	for i in range(16):
		var height: float = 3.0 + (sin(i * 2.7) * 0.5 + 0.5) * 12.0
		var col: Color = (RED if p.noise_level > 0.65 else AMBER) if i / 16.0 < p.noise_level else Color(0.18, 0.26, 0.25, 0.7)
		draw_rect(Rect2(599 + i * 5, 643 - height, 3, height), col)
	centered("ШУМ", 617, MUTED, 9)
	text("ЭЛЕКТРОШОК [ПРОБЕЛ / ЛКМ]", Vector2(988, 623), MUTED, 10)
	for i in range(p.slots.size()):
		var slot: float = p.slots[i]
		var at := Vector2(1090 + i * 68, 635)
		var col: Color = GREEN if slot == 0 else (AMBER if slot > 0 else RED)
		draw_rect(Rect2(at, Vector2(59, 25)), Color(0.04, 0.08, 0.09, 0.85))
		draw_rect(Rect2(at, Vector2(59, 25)), col * Color(1, 1, 1, 0.45), false, 1)
		text("ГОТОВ" if slot == 0 else ("%02d С" % ceili(slot) if slot > 0 else "[R]"), at + Vector2(8, 17), col, 11)
	text("КАМНИ [Q]  %02d" % p.rocks, Vector2(1104, 683), AMBER, 11)

func _draw_compass() -> void:
	var objective: Dictionary = app.world.objective(app.player.global_position, app.fuses >= int(app.config.fuses))
	if objective.is_empty():
		return
	var offset: Vector3 = objective.position - app.player.global_position
	var relative: float = wrapf(atan2(-offset.x, -offset.z) - app.player.rotation.y, -PI, PI)
	draw_line(Vector2(510, 47), Vector2(770, 47), Color(0.41, 0.51, 0.47, 0.65), 1)
	for i in range(13):
		draw_line(Vector2(510 + i * 21.667, 43), Vector2(510 + i * 21.667, 51), Color("6f8580"), 1)
	var x: float = clampf(640 - relative / PI * 128, 513, 767)
	draw_colored_polygon(PackedVector2Array([Vector2(x, 38), Vector2(x - 4, 32), Vector2(x + 4, 32)]), AMBER)
	centered("%s / %02d М" % [objective.label, roundi(offset.length())], 73, AMBER, 10)

func _draw_map() -> void:
	var world = app.world
	var n: int = world.maze.width
	var cell_size: float = 248.0 / n
	var origin := Vector2(968, 154)
	draw_rect(Rect2(945, 112, 294, 328), Color(0.022, 0.057, 0.057, 0.96))
	draw_rect(Rect2(945, 112, 294, 328), Color("465d58"), false, 1)
	draw_line(Vector2(945, 112), Vector2(1002, 112), GREEN, 2)
	text("СКАНЕР / " + str(app.config.code), Vector2(963, 135), GREEN, 11)
	text("[M]", Vector2(1196, 135), MUTED, 11)
	for y in range(n):
		for x in range(n):
			var index: int = y * n + x
			if world.explored[index] == 0:
				continue
			var c := Vector2i(x, y)
			var color := Color("253f3b") if world.maze.is_open(c) else Color("61756a")
			if world.breakables.has(c):
				color = AMBER
			draw_rect(Rect2(origin + Vector2(x, y) * cell_size, Vector2.ONE * (cell_size - 0.7)), color)
	for item in world.items:
		if item.taken or world.explored[item.cell.y * n + item.cell.x] == 0:
			continue
		draw_circle(origin + (Vector2(item.cell) + Vector2.ONE * 0.5) * cell_size, maxf(2.1, cell_size * 0.22), AMBER if item.kind == "fuse" else GREEN)
	var exit_cell: Vector2i = world.maze.exit_cell
	if world.explored[exit_cell.y * n + exit_cell.x] != 0 or app.fuses >= int(app.config.fuses):
		draw_rect(Rect2(origin + Vector2(exit_cell) * cell_size, Vector2.ONE * (cell_size - 1)), GREEN, false, 1.5)
	var pos: Vector3 = app.player.global_position
	var player_at: Vector2 = origin + Vector2(pos.x, pos.z) / Maze.CELL_SIZE * cell_size
	var forward := Vector2(-sin(app.player.rotation.y), -cos(app.player.rotation.y))
	var right := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([player_at + forward * 6.5, player_at - forward * 4 - right * 3.5, player_at - forward * 4 + right * 3.5]), INK)
	text("СЕКТОР НЕ ИССЛЕДОВАН ПОЛНОСТЬЮ", Vector2(963, 427), MUTED, 9)
