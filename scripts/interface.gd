extends Control
## Native Godot UI; no browser DOM is used for menus or gameplay.

signal command(action: String, value: Variant)
signal preference_changed(key: String, value: Variant)

const Models = preload("res://scripts/models.gd")
const Levels = preload("res://scripts/level_config.gd")
const Progress = preload("res://scripts/progress.gd")
const Hud = preload("res://scripts/hud.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const PAPER := Color("e0dfcc")
const MUTED := Color("8c9f9c")
const ACCENT := Color("d66a4f")
const LINE := Color("394e4e")
const GREEN := Color("a3c5ad")

var app
var content: Control
var menu: Control
var modal: Control
var hud
var touch
var menu_shade: TextureRect
var selected: int = 1
var tabs: Array[Button] = []
var start_button: Button
var sector_name: Label
var sector_description: Label
var sector_hint: Label
var sector_number: Label
var sector_details: Label
var record_label: Label
var modal_kind: String = ""
var mono: FontFile
var display_font: FontFile

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mono = Models.font()
	display_font = Models.font(true)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = Vector2(1280, 720)
	add_child(content)
	_build_menu()
	hud = Hud.new()
	hud.app = app
	hud.size = Vector2(1280, 720)
	content.add_child(hud)
	hud.hide()
	touch = TouchControls.new()
	touch.app = app
	touch.size = Vector2(1280, 720)
	content.add_child(touch)
	touch.hide()
	modal = Control.new()
	modal.size = Vector2(1280, 720)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(modal)
	modal.hide()
	resized.connect(_layout)
	_layout()
	refresh_sector()

func _layout() -> void:
	if content == null:
		return
	var ratio: float = minf(size.x / 1280.0, size.y / 720.0)
	content.scale = Vector2.ONE * ratio
	content.position = (size - Vector2(1280, 720) * ratio) * 0.5

func _rect(parent: Node, bounds: Rect2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = bounds.position
	rect.size = bounds.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _label(parent: Node, value: String, at: Vector2, font_size: int = 13, color: Color = PAPER, heading: bool = false, bounds: Vector2 = Vector2(600, 40)) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = bounds
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", display_font if heading else mono)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(fill: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _button(parent: Node, value: String, bounds: Rect2, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.position = bounds.position
	button.size = bounds.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", mono)
	button.add_theme_font_size_override("font_size", 15 if primary else 11)
	button.add_theme_color_override("font_color", Color("152225") if primary else PAPER)
	button.add_theme_color_override("font_hover_color", Color("102125") if primary else Color("f3ead8"))
	button.add_theme_color_override("font_focus_color", Color("152225") if primary else PAPER)
	button.add_theme_color_override("font_pressed_color", Color("102125") if primary else ACCENT)
	button.add_theme_color_override("font_disabled_color", Color("52625f"))
	button.add_theme_stylebox_override("normal", _style(ACCENT if primary else Color(0.045, 0.070, 0.075, 0.75), ACCENT if primary else LINE))
	button.add_theme_stylebox_override("hover", _style(Color("e48a6d") if primary else Color("263e3e"), Color("e48a6d") if primary else Color("718982")))
	button.add_theme_stylebox_override("pressed", _style(Color("aa503d") if primary else Color("243332"), ACCENT))
	button.add_theme_stylebox_override("disabled", _style(Color(0.035, 0.055, 0.060, 0.55), Color("273838")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("d7c8a0"), 2))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _emit(action: String, value: Variant = null) -> void:
	command.emit(action, value)

func _build_menu() -> void:
	menu = Control.new()
	menu.size = Vector2(1280, 720)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(menu)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.34, 0.57, 1.0])
	gradient.colors = PackedColorArray([Color(0.024, 0.043, 0.049, 0.97), Color(0.024, 0.043, 0.049, 0.92), Color(0.024, 0.043, 0.049, 0.30), Color(0.024, 0.043, 0.049, 0.13)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1280
	texture.height = 2
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	menu_shade = TextureRect.new()
	menu_shade.texture = texture
	menu_shade.size = Vector2(1280, 720)
	menu_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(menu_shade)
	_rect(menu, Rect2(48, 38, 1184, 1), Color(0.46, 0.57, 0.53, 0.26))
	_rect(menu, Rect2(48, 38, 40, 40), ACCENT)
	_label(menu, "07", Vector2(56, 37), 27, Color("122125"), true, Vector2(34, 40))
	_label(menu, "ОБЪЕКТ 07", Vector2(104, 39), 12, PAPER)
	_label(menu, "СИСТЕМА АВАРИЙНОГО ДОСТУПА", Vector2(104, 58), 9, MUTED)
	_rect(menu, Rect2(768, 56, 5, 5), ACCENT)
	_label(menu, "СВЯЗЬ НЕСТАБИЛЬНА", Vector2(784, 43), 10, Color("bf9481"))
	_button(menu, "НАСТРОЙКИ", Rect2(1080, 47, 152, 32), func(): _emit("settings"))
	_label(menu, "// ПРОТОКОЛ АВАРИЙНОГО СПУСКА", Vector2(64, 119), 10, ACCENT)
	_label(menu, "НИЖНИЙ", Vector2(59, 149), 85, PAPER, true, Vector2(520, 107))
	_label(menu, "УРОВЕНЬ", Vector2(59, 234), 85, PAPER, true, Vector2(520, 107))
	_rect(menu, Rect2(64, 349, 40, 2), ACCENT)
	_label(menu, "ТЕХНИЧЕСКИЙ ЛАБИРИНТ", Vector2(118, 333), 11, MUTED)
	_label(menu, "Питание отключено. Три сектора под землёй.\nПредохранители разбросаны.\nЧто-то ходит здесь вместе с вами.", Vector2(64, 373), 12, Color("a4b0a8"), false, Vector2(455, 61))
	_label(menu, "01 / ВЫБЕРИТЕ СЕКТОР", Vector2(64, 437), 10, MUTED)
	for i in range(4):
		var cfg: Dictionary = Levels.sector(i)
		var title: String = str(cfg.code) + "\n" + ("ОБУЧЕНИЕ" if i == 0 else ("ДОСТУПЕН" if i <= app.progress.unlocked else "ЗАКРЫТ"))
		var tab := _button(menu, title, Rect2(64 + i * 111, 473, 101, 49), func():
			selected = i
			refresh_sector()
			_emit("select", i)
		)
		tab.add_theme_font_size_override("font_size", 10)
		tabs.append(tab)
	start_button = _button(menu, "НАЧАТЬ СПУСК                         →", Rect2(64, 541, 434, 55), func(): _emit("start", selected), true)
	_button(menu, "БЕСКОНЕЧНЫЙ РЕЖИМ", Rect2(64, 608, 212, 37), func(): _emit("endless", 1))
	_button(menu, "УПРАВЛЕНИЕ  [H]", Rect2(286, 608, 212, 37), func(): _emit("help"))
	_label(menu, "◉  РЕКОМЕНДУЕМ ИГРАТЬ В НАУШНИКАХ", Vector2(64, 665), 9, Color("8a9c91"))
	# The selected sector is presented like a worn technical dossier.
	_rect(menu, Rect2(812, 464, 420, 185), Color(0.030, 0.052, 0.057, 0.93))
	_rect(menu, Rect2(812, 464, 420, 1), Color("6d7c72"))
	_rect(menu, Rect2(812, 464, 69, 2), ACCENT)
	_label(menu, "СЕКТОР / ДОПУСК", Vector2(836, 480), 9, MUTED)
	sector_number = _label(menu, "01 — 03", Vector2(1141, 480), 10, ACCENT, false, Vector2(90, 30))
	sector_name = _label(menu, "B3 · ТЕХНИЧЕСКИЙ", Vector2(835, 503), 27, PAPER, true)
	sector_description = _label(menu, "", Vector2(836, 546), 11, Color("9aa9a0"), false, Vector2(379, 49))
	sector_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sector_hint = _label(menu, "", Vector2(836, 600), 8, ACCENT, false, Vector2(378, 24))
	sector_details = _label(menu, "", Vector2(836, 625), 9, MUTED, false, Vector2(378, 24))
	record_label = _label(menu, "", Vector2(836, 422), 10, GREEN)
	_label(menu, "ПРОТОТИП 0.1 / GODOT", Vector2(1083, 665), 9, Color("839085"))
	_label(menu, "Есть пугающие сцены. Мягкие эффекты — в настройках.", Vector2(812, 691), 8, Color("687c76"))
	# Small annotation integrated into the corridor composition.
	_label(menu, "ПИТАНИЕ  0%", Vector2(922, 153), 9, Color("ae8170"))
	_rect(menu, Rect2(922, 184, 136, 1), Color(0.62, 0.40, 0.32, 0.38))
	_label(menu, "B3", Vector2(1111, 192), 79, Color(0.80, 0.79, 0.66, 0.13), true)

func refresh_sector() -> void:
	if not is_instance_valid(sector_name):
		return
	var cfg: Dictionary = Levels.sector(selected)
	for i in range(tabs.size()):
		var unlocked: bool = i <= app.progress.unlocked
		tabs[i].disabled = not unlocked
		tabs[i].text = str(Levels.SECTORS[i].code) + "\n" + ("ОБУЧЕНИЕ" if i == 0 else ("ДОСТУПЕН" if unlocked else "ЗАКРЫТ"))
		tabs[i].tooltip_text = "" if unlocked else "Завершите предыдущий сектор, чтобы открыть этот."
		tabs[i].add_theme_stylebox_override("normal", _style(Color("243837") if i == selected else Color(0.045, 0.070, 0.075, 0.75), ACCENT if i == selected else LINE))
		tabs[i].add_theme_color_override("font_color", PAPER if i == selected else MUTED)
	sector_name.text = str(cfg.code) + " · " + str(cfg.name)
	sector_description.text = cfg.desc
	sector_hint.text = cfg.hint
	sector_number.text = "УЧЕБНЫЙ" if selected == 0 else "%02d — 03" % selected
	sector_details.text = "%02d ПРЕДОХРАНИТЕЛЯ   /   %s" % [cfg.fuses, "НЕТ УГРОЗ" if selected == 0 else "УРОВЕНЬ УГРОЗЫ " + str(selected)]
	var key := str(selected)
	record_label.text = "ЛУЧШЕЕ ВРЕМЯ / " + Progress.format_time(app.progress.best[key]) if app.progress.best.has(key) else ""
	start_button.text = "НАЧАТЬ ОБУЧЕНИЕ                   →" if selected == 0 else "НАЧАТЬ СПУСК                      →"

func show_menu() -> void:
	touch.reset()
	touch.hide()
	modal.hide()
	modal_kind = ""
	hud.hide()
	menu.show()
	refresh_sector()

func show_game() -> void:
	touch.reset()
	touch.visible = app.touch_enabled
	menu.hide()
	modal.hide()
	modal_kind = ""
	hud.show()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()

func _modal_base(title: String, eyebrow: String, height: float = 580.0, color: Color = PAPER) -> Control:
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()
	modal.show()
	_rect(modal, Rect2(0, 0, 1280, 720), Color(0.006, 0.015, 0.018, 0.83))
	var panel := Control.new()
	panel.position = Vector2(340, (720 - height) * 0.5)
	panel.size = Vector2(600, height)
	modal.add_child(panel)
	_rect(panel, Rect2(0, 0, 600, height), Color("0c191d"))
	_rect(panel, Rect2(0, 0, 600, 1), LINE)
	_rect(panel, Rect2(0, height - 1, 600, 1), LINE)
	_rect(panel, Rect2(0, 0, 61, 3), ACCENT)
	_label(panel, eyebrow, Vector2(36, 23), 10, MUTED, false, Vector2(524, 30))
	_label(panel, title, Vector2(34, 59), 49, color, true, Vector2(544, 75))
	_rect(panel, Rect2(36, 145, 528, 1), LINE)
	return panel

func show_settings(paused: bool) -> void:
	touch.reset()
	touch.hide()
	modal_kind = "pause" if paused else "settings"
	var panel := _modal_base("ПАУЗА" if paused else "НАСТРОЙКИ", "СИГНАЛ УДЕРЖИВАЕТСЯ" if paused else "ОБЪЕКТ 07 / ПАРАМЕТРЫ", 620)
	_slider(panel, "ЧУВСТВИТЕЛЬНОСТЬ МЫШИ", "sensitivity", 0.3, 3.0, 0.1, 168)
	_slider(panel, "ОБЩАЯ ГРОМКОСТЬ", "volume", 0.0, 1.0, 0.05, 240)
	_slider(panel, "ЯРКОСТЬ", "brightness", 0.7, 1.7, 0.05, 312)
	var toggle := CheckButton.new()
	toggle.position = Vector2(32, 381)
	toggle.size = Vector2(536, 35)
	toggle.text = "МЯГКИЕ ЭФФЕКТЫ"
	toggle.add_theme_font_override("font", mono)
	toggle.add_theme_font_size_override("font_size", 12)
	toggle.add_theme_color_override("font_color", GREEN)
	toggle.button_pressed = app.progress.settings.reduced_effects
	toggle.toggled.connect(func(value): preference_changed.emit("reduced_effects", value))
	panel.add_child(toggle)
	_label(panel, "Без зерна, покачивания и мерцания фонаря.", Vector2(36, 417), 10, MUTED)
	_button(panel, "ПРОДОЛЖИТЬ →" if paused else "СОХРАНИТЬ И ЗАКРЫТЬ", Rect2(36, 460, 528, 48), func(): _emit("resume" if paused else "close"), true)
	if paused:
		_button(panel, "ЗАНОВО", Rect2(36, 520, 160, 38), func(): _emit("restart"))
		_button(panel, "УПРАВЛЕНИЕ", Rect2(210, 520, 172, 38), func(): _emit("help"))
		_button(panel, "В МЕНЮ", Rect2(396, 520, 168, 38), func(): _emit("menu"))
	else:
		_button(panel, "УПРАВЛЕНИЕ", Rect2(36, 520, 528, 38), func(): _emit("help"))
	_label(panel, "[ESC] НАЗАД", Vector2(36, 573), 10, MUTED)

func _slider(parent: Control, title: String, key: String, minimum: float, maximum: float, step: float, y: float) -> void:
	_label(parent, title, Vector2(36, y), 11, MUTED)
	var value_label := _label(parent, _setting_value(key, app.progress.settings[key]), Vector2(490, y), 11, ACCENT, false, Vector2(75, 25))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.position = Vector2(36, y + 36)
	slider.size = Vector2(528, 19)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = app.progress.settings[key]
	var line_style := _style(Color("2d4141"), Color("2d4141"), 0)
	line_style.content_margin_top = 2
	line_style.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", line_style)
	var area := _style(ACCENT, ACCENT, 0)
	area.content_margin_top = 2
	area.content_margin_bottom = 2
	slider.add_theme_stylebox_override("grabber_area", area)
	slider.add_theme_stylebox_override("grabber_area_highlight", area)
	var image := Image.create(9, 17, false, Image.FORMAT_RGBA8)
	image.fill(ACCENT)
	var thumb := ImageTexture.create_from_image(image)
	slider.add_theme_icon_override("grabber", thumb)
	slider.add_theme_icon_override("grabber_highlight", thumb)
	slider.value_changed.connect(func(value):
		value_label.text = _setting_value(key, value)
		preference_changed.emit(key, value)
	)
	parent.add_child(slider)

func _setting_value(key: String, value: float) -> String:
	return "%d%%" % roundi(value * 100) if key == "volume" else "%.2f×" % value

func show_help() -> void:
	modal_kind = "help"
	var panel := _modal_base("НЕ ДАЙТЕ СЕБЯ УСЛЫШАТЬ", "ОБЪЕКТ 07 / ПАМЯТКА СОТРУДНИКУ", 616)
	_label(panel, "Найдите предохранители. Доберитесь до шлюза.\nНе расходуйте всё снаряжение при первой встрече.", Vector2(36, 162), 11, PAPER, false, Vector2(528, 50))
	var controls = [
		["W A S D", "Движение · мышь — осмотреться"],
		["SHIFT / C", "Бежать / присесть и идти тише"],
		["F / E", "Фонарь / взять предмет, открыть шлюз"],
		["ПРОБЕЛ / ЛКМ", "Шокер: оглушает на 6 секунд, до 11 м"],
		["R", "Зарядить один слот: нужна 1 батарея"],
		["Q / M", "Бросить камень / открыть карту"],
		["ESC", "Пауза · настройки · выйти в меню"]
	]
	if app.touch_enabled:
		controls = [
			["СТИК СЛЕВА", "Движение · справа — обзор пальцем"],
			["БЕГ / ТИШЕ", "Удерживать бег / переключить приседание"],
			["СВЕТ / ВЗЯТЬ", "Фонарь / предмет, шлюз, перегородка"],
			["ШОКЕР", "Оглушает на 6 секунд, до 11 м"],
			["ЗАРЯД", "Зарядить 1 слот: нужна 1 батарея"],
			["КАМЕНЬ / КАРТА", "Отвлечь шумом / исследованный лабиринт"],
			["II", "Пауза · настройки · выйти в меню"]
		]
	for i in range(controls.size()):
		var y: float = 222 + i * 35
		_rect(panel, Rect2(36, y + 29, 528, 1), Color(0.2, 0.3, 0.3, 0.45))
		_label(panel, controls[i][0], Vector2(36, y), 10, ACCENT, false, Vector2(131, 28))
		_label(panel, controls[i][1], Vector2(178, y), 10, PAPER, false, Vector2(395, 28))
	_label(panel, "Запасная батарея автоматически заменит разряженную.\nКарта запоминает только то, что вы успели увидеть.\nСлепой монстр не замечает свет, но отлично слышит бег.", Vector2(36, 483), 10, MUTED, false, Vector2(528, 58))
	_button(panel, "ПОНЯТНО", Rect2(36, 550, 528, 42), func(): _emit("back"), true)

func show_result(won: bool, final_sector: bool = false) -> void:
	touch.reset()
	touch.hide()
	modal_kind = "result"
	hud.hide()
	var title: String = "ВЫ ВЫБРАЛИСЬ" if final_sector else ("СЕКТОР ПРОЙДЕН" if won else "ВАС НАШЛИ")
	if int(app.config.id) == 0 and won:
		title = "ОБУЧЕНИЕ ЗАВЕРШЕНО"
	var panel := _modal_base(title, "АВАРИЙНЫЙ ШЛЮЗ ОТКРЫТ" if won else "СВЯЗЬ С СОТРУДНИКОМ ПОТЕРЯНА", 530, GREEN if won else ACCENT)
	var line: String = "Снаружи светло. Внизу всё ещё кто-то есть." if final_sector else ("Шлюз закрылся. Впереди — следующий сектор." if won else "Оно услышало вас раньше, чем вы его увидели.")
	_label(panel, line, Vector2(36, 160), 11, MUTED, false, Vector2(528, 44))
	var values = [Progress.format_time(app.elapsed), "%d / %d" % [app.fuses, int(app.config.fuses)], "%d%%" % int(app.player.battery)]
	var names = ["ВРЕМЯ", "ПРЕДОХРАНИТЕЛИ", "БАТАРЕЯ"]
	for i in range(3):
		_label(panel, names[i], Vector2(36 + i * 182, 221), 9, MUTED, false, Vector2(167, 30))
		_label(panel, values[i], Vector2(36 + i * 182, 250), 32, PAPER, true, Vector2(167, 49))
	_rect(panel, Rect2(36, 310, 528, 1), LINE)
	var detail: String = "НОВЫЙ РЕКОРД СЕКТОРА" if won and app.new_record else ""
	if app.endless_floor > 0:
		detail = "ПРОЙДЕНО ЭТАЖЕЙ: %d / РЕКОРД: %d" % [app.endless_floor - 1, app.progress.endless_best]
	_label(panel, detail, Vector2(36, 326), 10, GREEN)
	if won and not final_sector:
		_button(panel, "СЛЕДУЮЩИЙ СЕКТОР →", Rect2(36, 379, 528, 49), func(): _emit("next"), true)
	elif won:
		_button(panel, "БЕСКОНЕЧНЫЙ РЕЖИМ →", Rect2(36, 379, 528, 49), func(): _emit("endless", 1), true)
	else:
		_button(panel, "ПОПРОБОВАТЬ ЕЩЁ РАЗ", Rect2(36, 379, 528, 49), func(): _emit("retry"), true)
	_button(panel, "В ГЛАВНОЕ МЕНЮ", Rect2(36, 442, 528, 39), func(): _emit("menu"))

func close_modal() -> void:
	modal.hide()
	modal_kind = ""
