extends RefCounted
## Data-only sector definitions. Distances and speeds are in metres / seconds.

const SECTORS = [
	{
		"id": 0, "code": "T0", "name": "УЧЕБНЫЙ СЕКТОР", "type": "none",
		"desc": "Проверьте снаряжение. Научитесь двигаться тихо.\nЗдесь вы пока одни.",
		"hint": "БЕЗОПАСНО · ОСНОВЫ ВЫЖИВАНИЯ", "size": 9,
		"fuses": 2, "batteries": 3, "patrol": 0.0, "chase": 0.0,
		"drain": 0.28, "ambient": 0.55, "compass": true, "breakables": 0,
		"recharge": 5.0, "ammo": 2, "difficulty": 0
	},
	{
		"id": 1, "code": "B3", "name": "ТЕХНИЧЕСКИЙ", "type": "blind",
		"desc": "Оно не видит. Но слышит каждый неверный шаг.\nНе бегите, если не знаете, куда.",
		"hint": "СЛЕПОЙ ОБИТАТЕЛЬ · СЛЕДИТЕ ЗА ШУМОМ", "size": 17,
		"fuses": 3, "batteries": 5, "patrol": 1.5, "chase": 3.2,
		"drain": 0.45, "ambient": 0.38, "compass": true, "breakables": 0,
		"recharge": 18.0, "ammo": 2, "difficulty": 1
	},
	{
		"id": 2, "code": "B4", "name": "НИЖНИЙ", "type": "watcher",
		"desc": "Свет выдаёт вас. Треснувшие перегородки\nскрывают короткие пути — и громкий шум.",
		"hint": "ЗРЯЧИЙ ОБИТАТЕЛЬ · БЕРЕГИТЕ СВЕТ", "size": 21,
		"fuses": 4, "batteries": 5, "patrol": 1.75, "chase": 3.5,
		"drain": 0.58, "ambient": 0.30, "compass": true, "breakables": 3,
		"recharge": 24.0, "ammo": 1, "difficulty": 2
	},
	{
		"id": 3, "code": "B5", "name": "ГЛУБОКИЙ", "type": "listener",
		"desc": "Здесь темно даже с фонарём. Оно слышит\nслишком хорошо. Компас больше не отвечает.",
		"hint": "ОСТРЫЙ СЛУХ · КОМПАС НЕДОСТУПЕН", "size": 25,
		"fuses": 5, "batteries": 6, "patrol": 1.85, "chase": 3.8,
		"drain": 0.68, "ambient": 0.23, "compass": false, "breakables": 4,
		"recharge": 28.0, "ammo": 1, "difficulty": 3
	}
]

static func sector(index: int) -> Dictionary:
	return SECTORS[clampi(index, 0, SECTORS.size() - 1)].duplicate(true)

static func endless(floor_number: int) -> Dictionary:
	var result = sector(1 + (floor_number - 1) % 3)
	result["id"] = -1
	result["code"] = "ЭТАЖ %02d" % floor_number
	result["name"] = "БЕЗ ДНА"
	result["size"] = mini(29, 17 + 2 * ((floor_number - 1) / 2))
	result["fuses"] = mini(7, 3 + (floor_number - 1) / 2)
	result["chase"] = minf(4.1, 3.1 + (floor_number - 1) * 0.12)
	result["patrol"] = minf(2.2, 1.4 + floor_number * 0.08)
	result["drain"] = minf(0.85, 0.4 + floor_number * 0.035)
	result["batteries"] = maxi(4, result.fuses)
	result["compass"] = floor_number <= 3
	return result
