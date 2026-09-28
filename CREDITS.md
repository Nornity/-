# Авторы, материалы и лицензии

## Этот прототип

«Нижний уровень / Объект 07» — новая реализация на Godot, созданная по мотивам предоставленного пользователем HTML/JavaScript-референса. Общая идея: подземные сектора, предохранители, слух монстра, фонарь и аварийный выход. Исходный HTML-движок в проект не включён.

Новые GDScript-скрипты, сцены, шейдеры и инструменты доступны по **MIT**; текст — `LICENSE`. Лабиринты, низкополигональные модели, иконка, PNG-текстуры и WAV-звуки созданы процедурно для этого проекта и распространяются на тех же условиях. Генератор текстур/аудио — `tools/generate_assets.py`. Из внешних игр модели, музыка и звуковые записи не заимствовались.

## Шрифты

Шрифты получены из официального репозитория Google Fonts, содержимое не модифицировалось. Переименование файла Oswald в `Oswald.ttf` не меняет внутреннее имя шрифта.

| Файл | Правообладатель / источник | Лицензия |
| --- | --- | --- |
| `assets/fonts/Oswald.ttf` | Copyright 2016 The Oswald Project Authors · https://github.com/googlefonts/OswaldFont · https://github.com/google/fonts/tree/main/ofl/oswald | SIL Open Font License 1.1, `assets/fonts/Oswald-OFL.txt` |
| `assets/fonts/IBMPlexMono-Regular.ttf` | Copyright © 2017 IBM Corp. · Reserved Font Name “Plex” · https://github.com/IBM/plex · https://github.com/google/fonts/tree/main/ofl/ibmplexmono | SIL Open Font License 1.1, `assets/fonts/IBMPlexMono-OFL.txt` |

Шрифты не являются MIT-материалами; сохраняйте их OFL-уведомления при распространении.

## Движок

**Godot Engine** — https://godotengine.org, MIT. Копия уведомления — `licenses/Godot-MIT.txt`; уведомления компонентов версии 4.6 — `licenses/Godot-COPYRIGHT.txt`. Лицензии включённых в движок сторонних компонентов доступны по https://godotengine.org/license/ и https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt. При распространении экспортированной игры сохраняйте необходимые уведомления движка и его компонентов.

Редактируемый исходный ZIP не содержит бинарников движка. Для Web-предпросмотра и автономного Windows-лаунчера используется настоящий Godot 4.6 stable WebAssembly runtime. Файлы `index.js` и `index.wasm` происходят из npm-пакета `react-godot-shader-preview@0.6.5` (https://github.com/nnoxnnox/react-godot-shader-preview, MIT). React-обёртка и код игры этого пакета не используются. Уведомление — `licenses/Preview-package-MIT.txt`.

Отдельный саморазворачивающийся Windows EXE-лаунчер содержит Node.js `22.22.3` для Windows x64 из `node-win-x64@22.22.3` (https://github.com/aredridel/node-bin-gen, опубликованные двоичные файлы Node.js), MIT. Уведомление Node.js — `licenses/Node-MIT.txt`. Исходник лаунчера, который запускает локальный веб-сервер и открывает установленный браузер, находится в `tools/windows_launcher.js`. Это не нативный шаблон Godot для Windows.

## Средства разработки

Python, NumPy и Pillow нужны только при повторной генерации ассетов; Playwright/Chromium — для необязательной автоматической проверки браузера. Они не входят в исходный архив и не нужны игроку или редактору Godot. Проект не загружает внешние материалы и не обращается к игровым сервисам во время игры.
