extends Node3D
## Game/session coordinator. All asynchronous transitions use a state timer,
## never detached timers that could mutate a restarted run.

const Levels = preload("res://scripts/level_config.gd")
const Maze = preload("res://scripts/maze.gd")
const Models = preload("res://scripts/models.gd")
const Progress = preload("res://scripts/progress.gd")
const World = preload("res://scripts/world.gd")
const Interface = preload("res://scripts/interface.gd")
const Sound = preload("res://scripts/audio.gd")
const InputSetup = preload("res://scripts/input_setup.gd")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CREATURE_SCENE = preload("res://scenes/creature.tscn")
const TUTORIAL = [
	"WASD — идите. Мышь — осмотритесь.",
	"Зажмите SHIFT: бег тратит выносливость.",
	"Нажмите C: присядьте и идите тише.",
	"F — выключить или включить фонарь.",
	"Найдите оранжевый предохранитель. Возьмите: E.",
	"ПРОБЕЛ — выстрел из шокера. Здесь безопасно.",
	"R — зарядить один слот от запасной батареи.",
	"Q — бросить камень и отвлечь обитателя.",
	"M — карта. Она запоминает увиденные коридоры.",
	"Соберите оба предохранителя. Следите за компасом.",
	"Найдите шлюз и нажмите E. Вы готовы."
]
const TOUCH_TUTORIAL = [
	"Стик слева — идите. Справа — осмотритесь.",
	"Удерживайте БЕГ и двигайтесь вперёд.",
	"ТИШЕ — присядьте, чтобы уменьшить шум.",
	"СВЕТ — выключить или включить фонарь.",
	"Найдите предохранитель. Подойдите и жмите ВЗЯТЬ.",
	"ШОКЕР — выстрел. Здесь безопасно.",
	"ЗАРЯД — потратить 1 запасную батарею.",
	"КАМЕНЬ — отвлечь обитателя звуком.",
	"КАРТА — схема увиденных коридоров.",
	"Соберите оба предохранителя. Следите за компасом.",
	"Найдите шлюз и нажмите кнопку ШЛЮЗ. Вы готовы."
]
const TUTORIAL_ACTIONS = ["move", "sprint", "crouch", "flashlight", "fuse", "fire", "reload", "rock", "map"]

var state: String = "menu"
var progress = Progress.new()
var config: Dictionary = {}
var world
var player
var creature
var ui
var audio
var environment: Environment
var diorama
var menu_camera: Camera3D
var post: ShaderMaterial
var scare_flash: ColorRect
var scare_staging_position := Vector3.ZERO
var scare_impact_position := Vector3.ZERO
var scare_heading: float = 0.0
var fuses: int = 0
var elapsed: float = 0.0
var endless_floor: int = 0
var run_seed: int = 0
var new_record: bool = false
var map_visible: bool = false
var interaction: Dictionary = {}
var message: String = ""
var notice_time: float = 0.0
var fear: float = 0.0
var heart_timer: float = 0.0
var breath_timer: float = 0.0
var tutorial_step: int = 0
var tutorial_seen: Dictionary = {}
var transition_time: float = 0.0
var start_fade: float = 0.0
var cinematic_caption: String = ""
var thrown: Array[Dictionary] = []
var elevator: Dictionary = {}
var elevator_built: bool = false
var idle_clock: float = 0.0
var testing: bool = false
var touch_enabled: bool = false
var _pointer_callback
var _was_locked: bool = false

func _ready() -> void:
	InputSetup.install()
	touch_enabled = DisplayServer.is_touchscreen_available()
	testing = OS.get_cmdline_user_args().has("--smoke-test")
	progress.load_progress()
	_build_environment()
	audio = Sound.new()
	add_child(audio)
	audio.set_volume(progress.settings.volume)
	diorama = World.new()
	add_child(diorama)
	menu_camera = diorama.build_diorama()
	_build_postprocess()
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	ui = Interface.new()
	ui.app = self
	layer.add_child(ui)
	ui.command.connect(_on_command)
	ui.preference_changed.connect(_on_preference)
	_apply_preferences()
	ui.show_menu()
	if OS.has_feature("web"):
		_pointer_callback = JavaScriptBridge.create_callback(_on_pointer_change)
		JavaScriptBridge.get_interface("document").addEventListener("pointerlockchange", _pointer_callback)
	print("LOWER_LEVEL_READY")
	if testing:
		_run_tests.call_deferred()

func _build_environment() -> void:
	var holder := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b181c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9aaea9")
	environment.ambient_light_energy = 0.48
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color("0f2024")
	environment.fog_light_energy = 0.75
	environment.fog_density = 0.017
	holder.environment = environment
	add_child(holder)

func _build_postprocess() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var screen := ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/retro.gdshader")
	screen.material = post
	layer.add_child(screen)
	var scare_layer := CanvasLayer.new()
	scare_layer.layer = 4
	add_child(scare_layer)
	scare_flash = ColorRect.new()
	scare_flash.name = "ScareFlash"
	scare_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scare_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scare_flash.color = Color(0.82, 0.035, 0.018, 0.0)
	scare_flash.visible = false
	scare_layer.add_child(scare_flash)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch_enabled:
		touch_enabled = true
		if is_instance_valid(ui) and state == "playing":
			_was_locked = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ui.touch.show()
	# A real mouse takes priority on hybrid touch-screen laptops. Emulated
	# touch mouse events use device -1 and must not hide the virtual controls.
	if event is InputEventMouseButton and event.pressed and event.device != -1 and touch_enabled:
		touch_enabled = false
		ui.touch.reset()
		ui.touch.hide()
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("pause"):
		if state == "playing":
			pause_game()
		elif state == "paused":
			resume_game()
		elif state == "menu":
			ui.close_modal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help") and state == "menu":
		ui.show_help()
	elif event.is_action_pressed("fullscreen") and not OS.has_feature("web"):
		var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event: InputEvent) -> void:
	if state != "playing" or (event is InputEventKey and event.echo):
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		return
	for action in ["crouch", "flashlight", "interact", "fire", "reload", "rock", "map"]:
		if event.is_action_pressed(action):
			perform_action(action)
			get_viewport().set_input_as_handled()
			break

func perform_action(action: String) -> void:
	if state != "playing":
		return
	match action:
		"crouch":
			player.toggle_crouch()
			audio.play("click", -19)
		"flashlight":
			player.toggle_flashlight()
			audio.play("click", -11)
		"interact":
			_interact()
		"fire":
			_fire_taser()
		"reload":
			if player.reload_taser():
				audio.play("click", -6, 0.80)
		"rock":
			_throw_rock()
		"map":
			map_visible = not map_visible
			_observe("map")
			audio.play("click", -20)

func _on_command(action: String, value: Variant) -> void:
	audio.enable_audio()
	audio.play("click", -14)
	match action:
		"start": start_run(int(value))
		"endless": start_run(-1, int(value))
		"settings": ui.show_settings(state == "paused")
		"help": ui.show_help()
		"close": ui.close_modal()
		"back":
			if state == "paused":
				ui.show_settings(true)
			else:
				ui.close_modal()
		"resume": resume_game()
		"menu": return_to_menu()
		"restart": start_run(int(config.id), endless_floor, run_seed)
		"retry":
			if endless_floor > 0:
				start_run(-1, 1)
			else:
				start_run(int(config.id), 0, run_seed)
		"next": start_run(mini(3, int(config.id) + 1))

func start_run(sector_id: int, floor_number: int = 0, map_seed: int = -1) -> void:
	if sector_id > progress.unlocked and not testing:
		return
	_dispose_run()
	InputSetup.release_movement()
	config = Levels.endless(maxi(1, floor_number)) if sector_id == -1 else Levels.sector(sector_id)
	endless_floor = maxi(1, floor_number) if sector_id == -1 else 0
	run_seed = randi_range(1, 2147483646) if map_seed < 0 else map_seed
	world = World.new()
	add_child(world)
	print("SECTOR_BUILD_BEGIN ", config.code, " seed=", run_seed)
	world.build(config, run_seed)
	print("SECTOR_GEOMETRY_READY ", world.maze.floor_cells.size(), " cells")
	world.reduced_effects = progress.settings.reduced_effects
	player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.position = Maze.to_world(world.maze.spawn, 0.03)
	player.setup(config, progress.settings)
	var route: Array[Vector2i] = world.maze.find_path(world.maze.spawn, world.maze.fuse_cells[0])
	if not route.is_empty():
		var direction: Vector2i = route[0] - world.maze.spawn
		player.rotation.y = atan2(-direction.x, -direction.y)
	player.stepped.connect(_on_step)
	player.notice.connect(notify)
	player.observed.connect(_observe)
	player.charge_ready.connect(func(): audio.play("pickup", -16))
	if config.type != "none":
		creature = CREATURE_SCENE.instantiate()
		world.add_child(creature)
		creature.position = Maze.to_world(world.maze.enemy_cell, 0.03)
		creature.setup(world, player, config)
		creature.caught.connect(die)
		creature.sound_requested.connect(_creature_sound)
		creature.active = true
	fuses = 0
	elapsed = 0
	fear = 0
	heart_timer = 0
	breath_timer = 0
	transition_time = 0
	start_fade = 0.8
	scare_flash.visible = false
	map_visible = false
	tutorial_step = 0
	tutorial_seen.clear()
	interaction = {}
	elevator_built = false
	elevator.clear()
	new_record = false
	state = "playing"
	world.playing = true
	player.active = true
	diorama.hide()
	environment.ambient_light_energy = float(config.ambient)
	environment.fog_density = 0.019 if int(config.id) != 0 else 0.012
	ui.show_game()
	audio.enable_audio()
	audio.ambient.volume_db = -12
	_capture_mouse()
	notify(("Найдите %d предохранителя. ВЗЯТЬ — рядом с предметом." if touch_enabled else "Найдите %d предохранителя. [E] — взять. [M] — карта.") % int(config.fuses), 6.0)
	print("SECTOR_READY ", config.code)

func _dispose_run() -> void:
	if is_instance_valid(player):
		player.stop_input()
	if is_instance_valid(creature):
		creature.active = false
	if is_instance_valid(world):
		world.playing = false
		remove_child(world)
		world.queue_free()
	world = null
	player = null
	creature = null
	thrown.clear()

func return_to_menu() -> void:
	state = "menu"
	scare_flash.visible = false
	_dispose_run()
	InputSetup.release_movement()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	diorama.show()
	menu_camera.current = true
	environment.ambient_light_energy = 0.48
	environment.fog_density = 0.017
	post.set_shader_parameter("fear", 0.0)
	post.set_shader_parameter("fade", 0.0)
	audio.hush()
	audio.ambient.volume_db = -18
	ui.show_menu()

func _process(delta: float) -> void:
	idle_clock += delta
	if state == "menu":
		if not bool(progress.settings.reduced_effects):
			menu_camera.rotation.z = sin(idle_clock * 0.20) * 0.003
		return
	if state == "paused" or state == "result":
		return
	if state == "opening":
		_update_escape(delta)
		return
	if state == "dying":
		_update_death(delta)
		return
	if state != "playing" or not is_instance_valid(player):
		return
	elapsed += delta
	notice_time = maxf(0, notice_time - delta)
	start_fade = maxf(0, start_fade - delta)
	post.set_shader_parameter("fade", start_fade)
	world.reveal(player.global_position, player.rotation.y, delta)
	interaction = world.nearest_interaction(player)
	_update_rocks(delta)
	var target_fear: float = 0.0
	if is_instance_valid(creature):
		var distance: float = creature.global_position.distance_to(player.global_position)
		target_fear = clampf(1.0 - distance / 14.0, 0, 1)
		if creature.state == "chase":
			target_fear = clampf(target_fear + 0.25, 0, 1)
		if creature.stun_time > 0:
			target_fear *= 0.25
	fear = lerpf(fear, target_fear, minf(1, delta * 1.5))
	post.set_shader_parameter("fear", fear)
	heart_timer -= delta
	if fear > 0.24 and heart_timer <= 0:
		audio.play("heartbeat", lerpf(-22, -9, fear))
		heart_timer = lerpf(1.7, 0.65, fear)
	breath_timer -= delta
	if player.stamina < 24 and breath_timer <= 0:
		audio.play("breath", -12)
		breath_timer = 2.4
	if int(config.id) == 0:
		_update_tutorial()

func _interact() -> void:
	interaction = world.nearest_interaction(player)
	if interaction.is_empty():
		return
	match interaction.kind:
		"fuse", "battery":
			var item: Dictionary = interaction.item
			if not world.take_item(item):
				return
			audio.play("pickup", -6)
			if item.kind == "fuse":
				fuses += 1
				_observe("fuse")
				if fuses >= int(config.fuses):
					world.unlock_door()
					notify("Питание восстановлено. Найдите аварийный шлюз.", 5.0)
					audio.play("power", -8)
				else:
					notify("Предохранитель установлен: %d / %d" % [fuses, config.fuses])
			else:
				player.reserves += 1
				notify("Запасная батарея найдена. Всего: %d" % player.reserves)
		"exit":
			if fuses >= int(config.fuses):
				begin_escape()
			else:
				notify("Шлюз обесточен. Не хватает предохранителей: %d" % (int(config.fuses) - fuses))
		"wall":
			var point: Vector3 = Maze.to_world(interaction.cell, 0.1)
			if world.break_wall(interaction.cell):
				audio.spatial("break", point, -3)
				if is_instance_valid(creature):
					creature.hear_noise(point, 32.0, false)
				notify("Проход открыт. Шум разнёсся по коридорам.")

func interaction_caption() -> String:
	if interaction.is_empty():
		return ""
	match interaction.kind:
		"fuse": return "ВЗЯТЬ ПРЕДОХРАНИТЕЛЬ"
		"battery": return "ВЗЯТЬ ЗАПАСНУЮ БАТАРЕЮ"
		"exit": return "ОТКРЫТЬ ШЛЮЗ" if fuses >= int(config.fuses) else "ШЛЮЗ ОБЕСТОЧЕН"
		"wall": return "СЛОМАТЬ ПЕРЕГОРОДКУ · ГРОМКО"
	return ""

func _fire_taser() -> void:
	if not player.fire():
		return
	audio.play("taser", -5)
	if is_instance_valid(creature):
		var origin: Vector3 = player.camera.global_position
		var target_position: Vector3 = creature.global_position + Vector3(0, 1.3, 0)
		var aim: Vector3 = target_position - origin
		if aim.length() <= 11 and (-player.camera.global_basis.z).dot(aim.normalized()) > 0.88 and world.line_of_sight(origin, target_position):
			creature.stun(6.0)
			notify("Обитатель оглушён на 6 секунд. Уходите.")
			audio.spatial("growl", creature.global_position, -10)
		else:
			creature.hear_noise(player.global_position, 16.0)
	# A brief local electrical flash, not a full-screen strobe.
	var flash := OmniLight3D.new()
	flash.light_color = Color("a3e2f0")
	flash.light_energy = 2.0 if progress.settings.reduced_effects else 4.0
	flash.omni_range = 4.0
	player.camera.add_child(flash)
	flash.position.z = -0.6
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.16)
	tween.tween_callback(flash.queue_free)

func _throw_rock() -> void:
	if not player.spend_rock():
		return
	var start: Vector3 = player.camera.global_position - Vector3(0, 0.15, 0)
	var forward: Vector3 = -player.global_basis.z
	var end: Vector3 = start + forward * 17.0
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position + hit.normal * 0.20
	end.y = 0.12
	var stone := Models.sphere(world, 0.085, start, Models.material(Color("738080")))
	thrown.append({"node": stone, "start": start, "end": end, "time": 0.0, "landed": false})
	audio.play("breath", -25, 1.8)

func _update_rocks(delta: float) -> void:
	for i in range(thrown.size() - 1, -1, -1):
		var rock: Dictionary = thrown[i]
		rock.time += delta
		if not rock.landed:
			var amount: float = minf(1, rock.time / 0.65)
			rock.node.position = rock.start.lerp(rock.end, amount) + Vector3(0, sin(amount * PI) * 0.75, 0)
			if amount >= 1:
				rock.landed = true
				audio.spatial("rock", rock.end, 0)
				if is_instance_valid(creature):
					creature.hear_noise(rock.end, 27.0, false)
		if rock.time > 5:
			rock.node.queue_free()
			thrown.remove_at(i)

func _on_step(radius: float) -> void:
	audio.play("step", -23 if player.crouching else (-5 if player.sprinting else -12), randf_range(0.90, 1.08))
	if is_instance_valid(creature):
		creature.hear_noise(player.global_position, radius)

func _creature_sound(sound_name: String, at: Vector3) -> void:
	if state == "playing":
		audio.spatial(sound_name, at, -8 if sound_name == "step" else -4)

func notify(text: String, duration: float = 3.5) -> void:
	message = text
	notice_time = duration

func _observe(action: String) -> void:
	tutorial_seen[action] = true

func _update_tutorial() -> void:
	if tutorial_step < TUTORIAL_ACTIONS.size():
		if tutorial_seen.has(TUTORIAL_ACTIONS[tutorial_step]):
			tutorial_step += 1
	elif tutorial_step == 9 and fuses >= int(config.fuses):
		tutorial_step = 10

func tutorial_text() -> String:
	return (TOUCH_TUTORIAL if touch_enabled else TUTORIAL)[clampi(tutorial_step, 0, TUTORIAL.size() - 1)]

func pause_game() -> void:
	if state != "playing":
		return
	state = "paused"
	player.stop_input()
	world.playing = false
	if is_instance_valid(creature):
		creature.active = false
	InputSetup.release_movement()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio.hush()
	ui.show_settings(true)

func resume_game() -> void:
	if state != "paused":
		ui.close_modal()
		return
	state = "playing"
	player.active = true
	world.playing = true
	if is_instance_valid(creature):
		creature.active = true
	ui.show_game()
	_capture_mouse()

func _capture_mouse() -> void:
	if is_instance_valid(player):
		player.look_grace = 0.25
		player.mouse_buffer = Vector2.ZERO
	if not testing and not touch_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pointer_change(_arguments: Array) -> void:
	var locked: bool = bool(JavaScriptBridge.eval("Boolean(document.pointerLockElement)"))
	if _was_locked and not locked and state == "playing":
		pause_game()
	_was_locked = locked

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and not testing:
		pause_game()

func _on_preference(key: String, value: Variant) -> void:
	progress.settings[key] = value
	progress.save_progress()
	_apply_preferences()

func _apply_preferences() -> void:
	audio.set_volume(float(progress.settings.volume))
	post.set_shader_parameter("brightness", float(progress.settings.brightness))
	post.set_shader_parameter("effects", 0.0 if progress.settings.reduced_effects else 1.0)
	if is_instance_valid(player):
		player.settings = progress.settings
	if is_instance_valid(world):
		world.reduced_effects = progress.settings.reduced_effects

func die() -> void:
	if state != "playing":
		return
	state = "dying"
	ui.touch.reset()
	ui.touch.hide()
	transition_time = 0
	player.stop_input()
	creature.active = false
	creature.velocity = Vector3.ZERO
	world.playing = false
	player.viewmodel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var forward: Vector3 = -player.camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	scare_staging_position = player.global_position + forward * 2.35
	scare_staging_position.y = player.global_position.y
	scare_impact_position = player.global_position + forward * 1.15
	scare_impact_position.y = player.global_position.y
	creature.global_position = scare_staging_position
	var toward_camera: Vector3 = player.camera.global_position - scare_staging_position
	scare_heading = atan2(-toward_camera.x, -toward_camera.z)
	creature.rotation.y = scare_heading
	creature.model.root.scale = Vector3.ONE
	for arm in creature.model.arms:
		arm.rotation.x = 0.45
		arm.rotation.z = signf(arm.position.x) * 0.20
	player.camera.look_at(creature.model.head.global_position)
	player.camera.rotation.z = 0.0
	scare_flash.visible = not bool(progress.settings.reduced_effects)
	scare_flash.color = Color(1.0, 0.90, 0.78, 0.72)
	audio.play("scream", -4, randf_range(0.96, 1.04))
	audio.play("caught", -9)
	post.set_shader_parameter("fear", 1.0)

func _update_death(delta: float) -> void:
	transition_time += delta
	var lunge := smoothstep(0.0, 0.34, transition_time)
	if is_instance_valid(creature):
		creature.global_position = scare_staging_position.lerp(scare_impact_position, lunge)
		creature.rotation.y = scare_heading
		creature.model.root.scale = Vector3.ONE * lerpf(1.0, 1.55, lunge)
		creature.model.root.rotation.x = sin(transition_time * 27.0) * 0.06 * (1.0 - lunge)
		for arm in creature.model.arms:
			arm.rotation.x = lerpf(0.45, 1.15, lunge)
			arm.rotation.z = signf(arm.position.x) * lerpf(0.20, 0.42, lunge)
		player.camera.look_at(creature.model.head.global_position)
		if not bool(progress.settings.reduced_effects):
			var camera_kick: float = sin(transition_time * 52.0) * 0.040 * exp(-transition_time * 1.7)
			player.camera.rotation.z = camera_kick
		else:
			player.camera.rotation.z = 0.0
	if scare_flash.visible:
		var flash_alpha := 0.72 * exp(-transition_time * 7.5)
		scare_flash.color = Color(1.0, 0.90, 0.78, flash_alpha)
	post.set_shader_parameter("fade", clampf((transition_time - 0.6) / 1.6, 0, 0.94))
	if transition_time > 2.2:
		scare_flash.visible = false
		state = "result"
		ui.show_result(false)

func begin_escape() -> void:
	if state != "playing" or fuses < int(config.fuses):
		return
	state = "opening"
	ui.touch.reset()
	ui.touch.hide()
	transition_time = 0
	player.stop_input()
	player.viewmodel.hide()
	if is_instance_valid(creature):
		creature.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cinematic_caption = "ШЛЮЗ РАЗБЛОКИРОВАН"
	audio.play("door", -5)
	post.set_shader_parameter("fear", 0.0)

func _update_escape(delta: float) -> void:
	transition_time += delta
	var t: float = transition_time
	if t < 2.8:
		world.animate_door(smoothstep(0.3, 1.9, t))
		var target_position: Vector3 = world.door.root.global_position + world.door.root.global_basis.z * 0.85
		target_position.y = player.global_position.y
		player.global_position = player.global_position.lerp(target_position, minf(1, delta * 1.4))
		player.camera.look_at(world.door.root.global_position + Vector3(0, 1.5, 0))
		post.set_shader_parameter("fade", smoothstep(1.9, 2.75, t))
	elif not elevator_built:
		_build_elevator()
		elevator_built = true
		audio.play("door", -9, 0.7)
	if t >= 2.8 and t < 6.5:
		post.set_shader_parameter("fade", 1.0 - smoothstep(2.9, 3.6, t))
		cinematic_caption = "ГРУЗОВОЙ ЛИФТ / " + ("ПОДЪЁМ НА ПОВЕРХНОСТЬ" if int(config.id) == 3 else "СПУСК В СЛЕДУЮЩИЙ СЕКТОР")
		if not progress.settings.reduced_effects:
			player.head.position.y = 1.62 + sin(t * 17.0) * 0.012
	if t >= 6.5:
		for i in range(2):
			var side: float = -1 if i == 0 else 1
			elevator.leaves[i].position.x = side * (0.5 + smoothstep(6.5, 7.6, t))
		post.set_shader_parameter("fade", smoothstep(7.0, 7.9, t))
	if t > 8.1:
		_finish_escape()

func _build_elevator() -> void:
	var cabin := Node3D.new()
	world.add_child(cabin)
	cabin.position = Vector3(-90, 0, -90)
	var metal := Models.material(Color("80918d"), "metal")
	Models.box(cabin, Vector3(3, 0.14, 4), Vector3(0, -0.07, -0.4), Models.material(Color.WHITE, "floor"))
	Models.box(cabin, Vector3(3, 0.1, 4), Vector3(0, 3.15, -0.4), metal)
	for x in [-1.48, 1.48]:
		Models.box(cabin, Vector3(0.14, 3.2, 4), Vector3(x, 1.6, -0.4), metal)
		Models.box(cabin, Vector3(0.11, 0.1, 3.7), Vector3(x - signf(x) * 0.12, 1.0, -0.4), Models.material(Color("555f59")))
	Models.lamp(cabin, Vector3(0, 3.03, -0.4), Color("c6c9a6"), 2.5, 6)
	elevator = Models.airlock(cabin, "↑ 00" if int(config.id) == 3 else "↓ " + ("B%d" % (int(config.id) + 3) if endless_floor == 0 else "%02d" % (endless_floor + 1)))
	elevator.root.position.z = -2.1
	elevator.light.light_color = Color("e0ba7b")
	Models.box(elevator.root, Vector3(2.05, 2.5, 0.02), Vector3(0, 1.25, -0.15), Models.material(Color("efe1b8"), "", 2))
	player.global_position = cabin.global_position + Vector3(0, 0.03, 0.65)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.position.y = 1.62

func _finish_escape() -> void:
	if endless_floor > 0:
		progress.endless_best = maxi(progress.endless_best, endless_floor)
		progress.save_progress()
		start_run(-1, endless_floor + 1)
		return
	new_record = progress.record_sector(int(config.id), maxf(elapsed, 0.01))
	state = "result"
	world.playing = false
	audio.play("power", -8)
	ui.show_result(true, int(config.id) == 3)

func _run_tests() -> void:
	var suite = load("res://tests/smoke.gd").new()
	var result: Dictionary = await suite.run(self)
	print("LOWER_LEVEL_TEST_RESULT " + JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__testResult = " + JSON.stringify(result) + ";")
	else:
		get_tree().quit(0 if result.failed == 0 else 1)
