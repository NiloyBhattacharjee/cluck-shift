extends Node
## Sound hooks. Sfx.play("gate_click") etc. Placeholder beeps are generated here;
## Phase 3 swaps them for real sounds without touching the callers.

const TONES := {  # name: [frequency Hz, seconds]
	"gate_click": [1400.0, 0.03],
	"tray_thunk": [110.0, 0.09],
	"ding": [990.0, 0.12],
	"strike_buzz": [80.0, 0.35],
	"estop": [300.0, 0.5],
}
const RATE := 22050

var _players := {}


func _ready() -> void:
	for n in TONES:
		var p := AudioStreamPlayer.new()
		p.stream = _tone(TONES[n][0], TONES[n][1])
		p.volume_db = -8.0
		add_child(p)
		_players[n] = p


func play(sound: String) -> void:
	if _players.has(sound):
		_players[sound].play()


func _tone(freq: float, seconds: float) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var fade := 1.0 - float(i) / count
		data.encode_s16(i * 2, int(signf(sin(TAU * freq * i / RATE)) * fade * 9000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
