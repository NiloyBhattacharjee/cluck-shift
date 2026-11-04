extends Control
## The 6 AM ending, drawn with shapes over a dawn sky. Shown only in WIN.
## Beside the payslip, the night's ledger: pay per hour as bars, strikes as red marks (#33).
## Normal: your payslip, and the night bus pulling away with you on it.
## Secret (every strange tray sent straight on): The Great Escape, delivery trucks leaving the
## loading dock driven by chickens in sunglasses.

const INK := Color("263238")
const PAPER := Color("fff8e1")
const HAT := Color("ffca28")

var secret := false
var heading := ""
var text := ""
var slip: Array = []  # payslip rows: [label, value]
var ledger: Array = []  # ShiftState.ledger: one tally per hour
var best := ""  # records beaten tonight, "" if none (#32)
var _since := 0.0  # seconds the ending has been up: drives the sunrise and the traffic


func show_ending(is_secret: bool, words: Dictionary, rows: Array, hours: Array = [], beaten := "") -> void:
	secret = is_secret
	heading = words.title
	text = words.text
	slip = rows
	ledger = hours
	best = beaten
	_since = 0.0
	show()


func _process(delta: float) -> void:
	if visible:
		_since += delta
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var t := _since
	# dawn: night blue at the top to orange at the horizon, the sun rising behind the factory
	var bands := [Color("1b2330"), Color("3b3a5a"), Color("6d4c7d"), Color("b5617a"), Color("ef8a5b"), Color("ffb74d")]
	for i in bands.size():
		draw_rect(Rect2(0, i * 66, size.x, 67), bands[i])
	draw_circle(Vector2(800, lerpf(420.0, 330.0, minf(t / 6.0, 1.0))), 46, Color("ffe082"))
	draw_rect(Rect2(40, 250, 210, 150), Color("37474f"))  # the factory
	draw_rect(Rect2(70, 190, 26, 60), Color("37474f"))
	draw_string(font, Vector2(40, 290), "CLUCK SHIFT FOODS", HORIZONTAL_ALIGNMENT_CENTER, 210, 15, HAT)
	# the road
	draw_rect(Rect2(0, 400, size.x, 140), Color("455a64"))
	for i in 12:
		draw_line(Vector2(i * 90 - fmod(t * 40.0, 90.0), 470), Vector2(i * 90 + 45 - fmod(t * 40.0, 90.0), 470), PAPER, 4)
	if secret:
		for i in 3:
			_draw_truck(Vector2(fmod(t * 110.0 + i * 330.0, size.x + 420.0) - 260.0, 440 - (i % 2) * 18))
	else:
		_draw_bus(Vector2(fmod(t * 70.0 + 640.0, size.x + 360.0) - 280.0, 440))  # starts mid-screen, at the stop

	draw_string_outline(font, Vector2(0, 58), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, 10, Color.BLACK)
	draw_string(font, Vector2(0, 58), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, HAT)
	draw_string(font, Vector2(0, 90), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)
	# the payslip
	var paper := Rect2(320, 108, 320, 40 + slip.size() * 24)
	draw_rect(paper, PAPER)
	draw_rect(paper, Color("bcaaa4"), false, 2)
	draw_string(font, paper.position + Vector2(0, 26), "PAYSLIP - NIGHT SHIFT", HORIZONTAL_ALIGNMENT_CENTER, paper.size.x, 16, INK)
	for i in slip.size():
		var y := paper.position.y + 54 + i * 24
		draw_string(font, Vector2(paper.position.x + 18, y), slip[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
		draw_string(font, Vector2(paper.position.x, y), slip[i][1], HORIZONTAL_ALIGNMENT_RIGHT, paper.size.x - 18, 16, INK)
	if best != "":
		var y := paper.end.y + 26
		draw_string_outline(font, Vector2(0, y), "NEW BEST: " + best, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 6, Color.BLACK)
		draw_string(font, Vector2(0, y), "NEW BEST: " + best, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, HAT)
	if not ledger.is_empty():
		_draw_ledger(Rect2(662, 108, 270, 190))
	if fmod(t, 1.0) < 0.7:
		draw_string(font, Vector2(0, 528), "PRESS ENTER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color.WHITE)


## One bar per hour, its height the hour's pay plus bonus; amber with a red X per strike, green if clean.
func _draw_ledger(box: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(box, Color(0, 0, 0, 0.35))
	draw_string(font, box.position + Vector2(0, 22), "HOUR BY HOUR", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, PAPER)
	var top := 1
	for h: Dictionary in ledger:
		top = maxi(top, h.pay + h.bonus)
	var slot := box.size.x / ledger.size()
	var base := box.end.y - 26
	for i in ledger.size():
		var h: Dictionary = ledger[i]
		var tall: float = (base - box.position.y - 52) * (h.pay + h.bonus) / top
		var x := box.position.x + i * slot + slot * 0.2
		draw_rect(Rect2(x, base - tall, slot * 0.6, tall), Color("9ccc65") if h.strikes == 0 else Color("ffa726"))
		for k in h.strikes:
			draw_string(font, Vector2(x, base - tall - 4 - k * 14), "X", HORIZONTAL_ALIGNMENT_CENTER, slot * 0.6, 14, Color("ef5350"))
		draw_string(font, Vector2(x - slot * 0.2, base + 18), h.from.split(" ")[0], HORIZONTAL_ALIGNMENT_CENTER, slot, 13, PAPER)


func _draw_bus(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(0, -70), Vector2(240, 70)), Color("ffa000"))
	for i in 5:
		draw_rect(Rect2(at + Vector2(14 + i * 44, -60), Vector2(34, 26)), Color("b3e5fc"))
	_draw_chicken_head(at + Vector2(31, -44), false)  # you, going home
	draw_string(ThemeDB.fallback_font, at + Vector2(0, -12), "NIGHT BUS", HORIZONTAL_ALIGNMENT_CENTER, 240, 14, INK)
	for x in [40.0, 200.0]:
		draw_circle(at + Vector2(x, 2), 14, Color("212121"))


func _draw_truck(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(0, -80), Vector2(170, 76)), Color("eceff1"))
	draw_string(ThemeDB.fallback_font, at + Vector2(0, -38), "CLUCK SHIFT", HORIZONTAL_ALIGNMENT_CENTER, 170, 15, Color("e53935"))
	draw_rect(Rect2(at + Vector2(174, -60), Vector2(60, 56)), Color("e53935"))  # the cab
	draw_rect(Rect2(at + Vector2(196, -54), Vector2(32, 24)), Color("b3e5fc"))
	_draw_chicken_head(at + Vector2(210, -38), true)  # the driver
	for x in [30.0, 130.0, 210.0]:
		draw_circle(at + Vector2(x, 0), 13, Color("212121"))


func _draw_chicken_head(at: Vector2, shades: bool) -> void:
	for i in 3:
		draw_circle(at + Vector2(-5 + i * 5, -11), 3, Color("e53935"))
	draw_circle(at, 9, Color("fafafa"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(8, 0), at + Vector2(15, 2), at + Vector2(8, 4)]), Color("ffa000"))
	if shades:
		draw_rect(Rect2(at + Vector2(-3, -5), Vector2(12, 5)), Color("212121"))
	else:
		draw_circle(at + Vector2(4, -2), 2, INK)
