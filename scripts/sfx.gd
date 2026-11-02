extends Node
## Sound hooks: Sfx.play("gate_click"), Sfx.play("ding", 1.2) for a higher pitch, Sfx.loop("hum").
## Every sound is synthesized here at start-up (noise bursts, pitch sweeps, envelopes), so the game
## ships with no audio files and no licences to track. Unknown names are ignored.

const RATE := 22050

var _players := {}


func _ready() -> void:
	_add("gate_click", 0.07, func(t): return _noise() * _decay(t, 60.0) * 0.5 + sin(TAU * 2400.0 * t) * _decay(t, 90.0) * 0.5)
	_add("tray_thunk", 0.18, func(t): return sin(TAU * _sweep(t, 150.0, 55.0, 0.18)) * _decay(t, 22.0) + _noise() * _decay(t, 120.0) * 0.3)
	_add("ding", 0.45, func(t): return (sin(TAU * 1320.0 * t) + 0.5 * sin(TAU * 2640.0 * t) + 0.25 * sin(TAU * 3960.0 * t)) * _decay(t, 7.0) * 0.45)
	_add("strike_buzz", 0.45, func(t): return _saw(110.0 * t) * (0.6 + 0.4 * sin(TAU * 9.0 * t)) * _fade(t, 0.45) * 0.55)
	_add("missed", 0.6, func(t): return sin(TAU * _sweep(t, 1300.0, 220.0, 0.6)) * _fade(t, 0.6) * 0.5)
	_add("estop", 1.0, func(t): return _square((650.0 + 180.0 * sin(TAU * 3.0 * t)) * t) * _fade(t, 1.0) * 0.3)
	_add("clock_in", 0.7, func(t): return (sin(TAU * 660.0 * t) * _decay(t, 6.0) + (sin(TAU * 990.0 * t) * _decay(t - 0.16, 6.0) if t > 0.16 else 0.0)) * 0.45)
	_add("hour_end", 1.1, func(t): return (sin(TAU * 523.0 * t) + 0.6 * sin(TAU * 784.0 * t) + _noise() * 0.15) * minf(t * 8.0, 1.0) * _fade(t, 1.1) * 0.4)
	_add("cash", 0.5, func(t): return _noise() * _decay(t, 40.0) * 0.4 + (sin(TAU * 2093.0 * t) + sin(TAU * 2637.0 * t)) * _decay(t - 0.05, 9.0) * 0.3 * float(t > 0.05))
	_add("select", 0.05, func(t): return sin(TAU * 1200.0 * t) * _decay(t, 70.0) * 0.5)
	_add("pa_jingle", 0.9, func(t): return sin(TAU * (784.0 if t < 0.4 else 622.0) * t) * _decay(fmod(t, 0.4), 5.0) * 0.45)
	_add("hum", 1.0, func(t): return (sin(TAU * 55.0 * t) + 0.5 * sin(TAU * 110.0 * t) + _noise() * 0.08) * 0.12, true)


func play(sound: String, pitch := 1.0) -> void:
	if _players.has(sound):
		_players[sound].pitch_scale = pitch
		_players[sound].play()


func loop(sound: String, on: bool) -> void:
	if _players.has(sound) and _players[sound].playing != on:
		if on:
			_players[sound].play()
		else:
			_players[sound].stop()


func _add(sound: String, seconds: float, wave: Callable, looping := false) -> void:
	var count := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(wave.call(float(i) / RATE), -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	var p := AudioStreamPlayer.new()
	p.stream = wav
	p.volume_db = -6.0
	add_child(p)
	_players[sound] = p


static func _noise() -> float:
	return randf_range(-1.0, 1.0)


static func _decay(t: float, rate: float) -> float:  # sharp hit that dies away
	return exp(-rate * t) if t >= 0.0 else 0.0


static func _fade(t: float, length: float) -> float:  # linear fade to silence
	return clampf(1.0 - t / length, 0.0, 1.0)


static func _sweep(t: float, from: float, to: float, length: float) -> float:  # phase (cycles) of a linear pitch slide
	return from * t + (to - from) * t * t / (2.0 * length)


static func _saw(cycles: float) -> float:
	return 2.0 * fmod(cycles, 1.0) - 1.0


static func _square(cycles: float) -> float:
	return 1.0 if fmod(cycles, 1.0) < 0.5 else -1.0
