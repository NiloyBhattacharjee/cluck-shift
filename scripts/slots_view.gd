extends Control
## Chicken Slots in the break room: three reels, each stopped with a Shift press.
## ShiftState.spin() has already picked the result, so the reels only reveal it and the moment you
## press changes nothing. Each strip holds the symbols in the same proportions as the real odds.

signal settled

const SYMBOL_GAP := 120.0  # px between symbols on a reel
const SPIN_SPEED := 10.0  # symbols per second
const WINDOW := Vector2(180, 150)
const REEL_GAP := 24.0
const TOP := 150.0
const BACK := Color("10141c")
const HAT := Color("ffca28")
const INK := Color("eceff1")

var done := false  # all three reels have landed
var touch := false  # tap wording (#44)
var wallet := 0
var _result := {}  # from ShiftState.spin(): reels, payout
var _strips := [[], [], []]
var _pos := [0.0, 0.0, 0.0]  # how far each reel has turned, in symbols
var _target := [-1, -1, -1]  # where a stopping reel lands; -1 while it spins freely
var _stopped := 0
var _landed := 0
var _since_done := 0.0


## Starts a spin. `weights` is rules.json's slots.weights; a symbol of weight 5 is one place on the strip.
func start(result: Dictionary, weights: Dictionary) -> void:
	_result = result
	done = false
	_stopped = 0
	_landed = 0
	_since_done = 0.0
	_target = [-1, -1, -1]
	for i in 3:
		_strips[i] = []
		for symbol: String in weights:
			@warning_ignore("integer_division")
			for n in int(weights[symbol]) / 5:
				_strips[i].append(symbol)
		_strips[i].shuffle()
		_pos[i] = randf_range(0.0, _strips[i].size())


## A Shift press: the next reel starts slowing towards its symbol. The last reel slips further, and
## further still if the first two match.
func stop_next() -> void:
	if _stopped == 3:
		return
	var i := _stopped
	_stopped += 1
	var ahead := 3
	if i == 2:
		ahead = 10 if _result.reels[0] == _result.reels[1] else 5
	var t := int(ceil(_pos[i])) + ahead
	while _strips[i][t % _strips[i].size()] != _result.reels[i]:
		t += 1
	_target[i] = t


func since_done() -> float:
	return _since_done


func _process(delta: float) -> void:
	if not visible:
		return
	queue_redraw()
	if done:
		_since_done += delta
		return
	for i in 3:
		if _target[i] >= 0 and _pos[i] >= _target[i]:
			continue
		var was := int(_pos[i])
		if _target[i] < 0:
			_pos[i] += SPIN_SPEED * delta
		else:
			_pos[i] = minf(_pos[i] + clampf((_target[i] - _pos[i]) * 2.5, 1.5, SPIN_SPEED) * delta, _target[i])
			if _pos[i] >= _target[i]:
				_land()
		if int(_pos[i]) != was and i == mini(_stopped, 2):  # one reel ticks at a time; the slowing last one is the drama
			Sfx.play("reel_tick", 1.0 + 0.2 * i)


func _land() -> void:
	_landed += 1
	Sfx.play("reel_stop")
	if _landed == 3:
		done = true
		settled.emit()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	var payout: int = _result.get("payout", 0)
	var three: bool = done and _result.reels[0] == _result.reels[1] and _result.reels[1] == _result.reels[2]
	var jackpot: bool = three and _result.reels[0] == ShiftState.STRANGE
	var shake := Vector2.ZERO
	if three and _since_done < 0.6:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.0 - _since_done / 0.6) * (14.0 if jackpot else 6.0)
	var left := (size.x - 3.0 * WINDOW.x - 2.0 * REEL_GAP) / 2.0
	var top := TOP + shake.y
	for i in 3:
		_draw_reel(i, Vector2(left + i * (WINDOW.x + REEL_GAP) + shake.x, top))
	# hide what has scrolled out of the windows; everything else is drawn over this
	draw_rect(Rect2(0, 0, size.x, top), BACK)
	draw_rect(Rect2(0, top + WINDOW.y, size.x, size.y), BACK)
	for i in 3:
		var lit: bool = done and payout > 0 and _matched(i)
		var flash := lit and fmod(_since_done * 4.0, 1.0) < 0.5
		draw_rect(Rect2(Vector2(left + i * (WINDOW.x + REEL_GAP) + shake.x, top), WINDOW), HAT if lit else Color("546e7a"), false, 8.0 if flash else 4.0)
	if three:
		_draw_coins(160 if jackpot else 50)
	draw_string(font, Vector2(0, 70) + shake, "CHICKEN SLOTS", HORIZONTAL_ALIGNMENT_CENTER, size.x, 42, HAT)
	draw_string(font, Vector2(0, 112), "Your pay: $%d" % wallet, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, INK)
	if not done:
		draw_string(font, Vector2(0, 360), "TAP  stop the next reel" if touch else "LEFT or RIGHT SHIFT  stop the next reel", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, INK)
		return
	var colour := HAT if payout > 0 else Color("90a4ae")
	var line := _result_line(payout, three, jackpot)
	var big := 56 if jackpot else 34
	draw_string_outline(font, Vector2(0, 375) + shake, line, HORIZONTAL_ALIGNMENT_CENTER, size.x, big, 8, Color.BLACK)
	draw_string(font, Vector2(0, 375) + shake, line, HORIZONTAL_ALIGNMENT_CENTER, size.x, big, colour)
	if fmod(_since_done, 1.0) < 0.7:
		var go := "TAP  back to the line" if touch else "ENTER  back to the line"
		draw_string_outline(font, Vector2(0, 450), go, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, 6, Color.BLACK)
		draw_string(font, Vector2(0, 450), go, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, INK)


func _draw_reel(i: int, at: Vector2) -> void:
	var strip: Array = _strips[i]
	draw_rect(Rect2(at, WINDOW), Color("eceff1"))
	var first := int(_pos[i])
	for n in [-1, 0, 1, 2]:
		var y: float = at.y + WINDOW.y / 2.0 + (first + n - _pos[i]) * SYMBOL_GAP
		draw_set_transform(Vector2(at.x + WINDOW.x / 2.0, y), 0.0, Vector2(2.4, 2.4))
		Tray.draw_food(self, strip[(first + n) % strip.size()])
	draw_set_transform(Vector2.ZERO)


func _matched(i: int) -> bool:
	var others: Array = _result.reels.duplicate()
	others.remove_at(i)
	return _result.reels[i] in others


func _result_line(payout: int, three: bool, jackpot: bool) -> String:
	if jackpot:
		return "JACKPOT!  +$%d" % payout
	if three:
		return "THREE %sS!  +$%d" % [_result.reels[0].to_upper(), payout]
	if payout > 0:
		return "A PAIR:  $%d BACK" % payout
	return "NOTHING. BACK TO WORK."


func _draw_coins(count: int) -> void:
	for i in count:
		var fall: float = 180.0 + (i % 5) * 70.0
		var x := fmod(i * 137.5, size.x)
		var y := fmod(_since_done * fall + i * 97.0, size.y + 40.0) - 20.0
		draw_circle(Vector2(x, y), 7.0, HAT)
		draw_circle(Vector2(x, y), 4.0, Color("ffb300"))
