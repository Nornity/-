extends CharacterBody3D

signal stepped(radius: float)
signal notice(text: String)
signal observed(action: String)
signal charge_ready

const Models = preload("res://scripts/models.gd")
@export var walk_speed: float = 2.55
@export var run_speed: float = 4.65
@export var crouch_speed: float = 1.25
@export var stamina_drain: float = 23.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var lamp: SpotLight3D = $Head/Camera/Flashlight
@onready var collision: CollisionShape3D = $Collision

var active: bool = false
var settings: Dictionary = {}
var config: Dictionary = {}
var flashlight: bool = true
var battery: float = 100.0
var reserves: int = 1
var stamina: float = 100.0
var sprinting: bool = false
var crouching: bool = false
var exhausted: bool = false
var moving: bool = false
var noise_level: float = 0.0
var rocks: int = 3
var slots: Array[float] = [] # 0 = loaded; -1 = spent; positive = charging seconds.
var shot_cooldown: float = 0.0
var throw_cooldown: float = 0.0
var reload_animation: float = 0.0
var recoil: float = 0.0
var pitch: float = 0.0
var bob: float = 0.0
var step_distance: float = 0.0
var warned_battery: bool = false
var viewmodel: Node3D
var touch_move := Vector2.ZERO
var touch_sprint: bool = false
var mouse_buffer := Vector2.ZERO
var look_grace: float = 0.25
var fear: float = 0.0

func _ready() -> void:
	collision.shape = collision.shape.duplicate()
	viewmodel = Models.taser()
	camera.add_child(viewmodel)
	viewmodel.position = Vector3(0.32, -0.29, -0.58)
	viewmodel.scale = Vector3.ONE * 1.18
	for child in viewmodel.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func setup(sector: Dictionary, preferences: Dictionary) -> void:
	config = sector
	settings = preferences
	reserves = 2 if int(config.id) == 0 else 1
	slots.clear()
	for i in range(int(config.ammo)):
		slots.append(0.0)
	camera.current = true

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Some browsers emit a cursor-warp delta when pointer lock starts.
		if look_grace <= 0.0 and event.relative.length() < 280.0:
			mouse_buffer += event.relative

func add_look(delta_pixels: Vector2) -> void:
	if active:
		mouse_buffer += delta_pixels

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		mouse_buffer = Vector2.ZERO
		return
	look_grace = maxf(0, look_grace - delta)
	var look := mouse_buffer * (1.0 - exp(-30.0 * delta))
	mouse_buffer -= look
	rotation.y -= look.x * 0.0021 * float(settings.get("sensitivity", 1.0))
	pitch = clampf(pitch - look.y * 0.0021 * float(settings.get("sensitivity", 1.0)), -1.28, 1.28)
	rotation.y += (Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")) * delta * 1.8
	head.rotation.x = pitch
	var movement: Vector2 = (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move).limit_length(1.0)
	moving = movement.length() > 0.08
	if exhausted and stamina > 24.0:
		exhausted = false
	var wants_run: bool = (Input.is_action_pressed("sprint") or touch_sprint) and movement.y < -0.1 and not crouching
	sprinting = wants_run and not exhausted and moving
	var speed: float = crouch_speed if crouching else (run_speed if sprinting else walk_speed)
	if movement.y > 0:
		speed *= 0.75
	var direction: Vector3 = global_basis * Vector3(movement.x, 0, movement.y)
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 20.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 20.0)
	if not is_on_floor():
		velocity.y -= 15.0 * delta
	else:
		velocity.y = -0.15
	var old_position := global_position
	move_and_slide()
	var travelled: float = Vector2(global_position.x - old_position.x, global_position.z - old_position.z).length()
	moving = travelled > 0.001
	if not moving:
		sprinting = false
	if sprinting:
		stamina = maxf(0, stamina - stamina_drain * delta)
		if stamina <= 0:
			exhausted = true
	else:
		stamina = minf(100, stamina + (20.0 if not moving else 11.0) * delta)
	step_distance += travelled
	bob += travelled * (3.8 if sprinting else 3.1)
	if step_distance > (1.40 if crouching else (1.30 if sprinting else 1.32)):
		step_distance = 0.0
		stepped.emit(1.7 if crouching else (18.0 if sprinting else 7.0))
	if moving:
		observed.emit("sprint" if sprinting else "move")
	var target_noise: float = 0.0
	if moving:
		target_noise = 0.12 if crouching else (0.91 if sprinting else 0.40)
	noise_level = lerpf(noise_level, target_noise, minf(1, delta * 6))
	var effects: bool = not bool(settings.get("reduced_effects", false))
	var camera_bob: float = sin(bob * 2) * (0.03 if sprinting else 0.015) if effects and moving else 0.0
	head.position.y = lerpf(head.position.y, (1.03 if crouching else 1.62) + camera_bob, minf(1, delta * 12))
	camera.rotation.z = lerpf(camera.rotation.z, -movement.x * 0.014 if effects else 0.0, minf(1, delta * 7))
	viewmodel.position.x = 0.32 + (sin(bob) * 0.012 if moving and effects else 0.0)
	viewmodel.position.y = -0.29 - (sin(reload_animation / 1.1 * PI) * 0.24 if reload_animation > 0 else 0.0)
	viewmodel.position.z = -0.58 + recoil * 0.095
	viewmodel.rotation.x = -recoil * 0.19
	tick_resources(delta)

func tick_resources(delta: float) -> void:
	shot_cooldown = maxf(0, shot_cooldown - delta)
	throw_cooldown = maxf(0, throw_cooldown - delta)
	reload_animation = maxf(0, reload_animation - delta)
	recoil = maxf(0, recoil - delta * 4.5)
	for i in range(slots.size()):
		if slots[i] > 0:
			slots[i] = maxf(0.0, slots[i] - delta)
			if slots[i] == 0.0:
				charge_ready.emit()
	if flashlight:
		battery = maxf(0, battery - float(config.get("drain", 0.4)) * delta)
	if battery <= 5.0 and reserves > 0:
		reserves -= 1
		battery = 100
		flashlight = true
		warned_battery = false
		notice.emit("Батарея заменена автоматически. Запас: %d" % reserves)
	elif battery <= 0 and flashlight:
		flashlight = false
		notice.emit("Фонарь разряжен. Ищите зелёные батареи.")
	elif battery < 20 and not warned_battery:
		warned_battery = true
		notice.emit("Заряд фонаря ниже 20%. Берегите свет.")
	lamp.visible = flashlight and battery > 0
	var flicker: float = 1.0
	if battery < 15 and not bool(settings.get("reduced_effects", false)):
		flicker = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
	lamp.light_energy = 4.4 * flicker * float(settings.get("brightness", 1.0))

func toggle_crouch() -> void:
	crouching = not crouching
	collision.shape.height = 1.10 if crouching else 1.72
	collision.position.y = collision.shape.height * 0.5
	observed.emit("crouch")

func toggle_flashlight() -> void:
	if battery <= 0:
		notice.emit("Фонарь разряжен.")
		return
	flashlight = not flashlight
	lamp.visible = flashlight
	observed.emit("flashlight")

func loaded_count() -> int:
	var count: int = 0
	for slot in slots:
		if slot == 0:
			count += 1
	return count

func fire() -> bool:
	if shot_cooldown > 0 or reload_animation > 0:
		return false
	var index := slots.find(0.0)
	if index < 0:
		notice.emit("Шокер разряжен. [R] — зарядить от запасной батареи.")
		return false
	slots[index] = -1.0
	shot_cooldown = 0.8
	recoil = 1.0
	observed.emit("fire")
	return true

func reload_taser() -> bool:
	if reload_animation > 0:
		return false
	var index := slots.find(-1.0)
	if index < 0:
		notice.emit("Все слоты заряжены или уже заряжаются.")
		return false
	if reserves <= 0:
		notice.emit("Нет запасных батарей. Ищите зелёные контейнеры.")
		return false
	reserves -= 1
	reload_animation = 1.1
	slots[index] = float(config.get("recharge", 18.0))
	notice.emit("Зарядка шокера: %d с. Потрачена одна батарея." % int(slots[index]))
	observed.emit("reload")
	return true

func spend_rock() -> bool:
	if throw_cooldown > 0:
		return false
	if rocks <= 0:
		notice.emit("Камней больше нет.")
		return false
	rocks -= 1
	throw_cooldown = 0.75
	observed.emit("rock")
	return true

func stop_input() -> void:
	active = false
	velocity = Vector3.ZERO
	touch_move = Vector2.ZERO
	touch_sprint = false
	mouse_buffer = Vector2.ZERO
