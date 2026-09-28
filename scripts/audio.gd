extends Node
## Original PCM effects; 3D players provide actual left/right positional cues.

var streams: Dictionary = {}
var ambient: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var enabled: bool = false
var spatial_voices: Array[AudioStreamPlayer3D] = []
var next_spatial: int = 0

func _ready() -> void:
	for name in ["ambient", "step", "click", "pickup", "taser", "rock", "growl", "heartbeat", "breath", "door", "caught", "break", "power"]:
		streams[name] = AudioStreamWAV.load_from_file("res://assets/audio/%s.wav" % name)
	streams.ambient.loop_mode = AudioStreamWAV.LOOP_FORWARD
	streams.ambient.loop_end = int(streams.ambient.get_length() * streams.ambient.mix_rate)
	ambient = AudioStreamPlayer.new()
	ambient.stream = streams.ambient
	ambient.volume_db = -12
	add_child(ambient)
	for i in range(10):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	for i in range(8):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 35.0
		voice.unit_size = 5.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		spatial_voices.append(voice)

func enable_audio() -> void:
	enabled = true
	if not ambient.playing:
		ambient.play()

func set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(0, value <= 0.0)

func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not enabled or not streams.has(name):
		return
	var voice: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = streams[name]
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()

func spatial(name: String, at: Vector3, volume_db: float = -4.0) -> void:
	if not enabled or not streams.has(name):
		return
	var voice: AudioStreamPlayer3D = spatial_voices[next_spatial]
	next_spatial = (next_spatial + 1) % spatial_voices.size()
	voice.stream = streams[name]
	voice.global_position = at + Vector3(0, 0.85, 0)
	voice.volume_db = volume_db
	voice.pitch_scale = 0.72 if name == "step" else randf_range(0.92, 1.05)
	voice.play()

func hush() -> void:
	for voice in voices:
		voice.stop()
	for voice in spatial_voices:
		voice.stop()
