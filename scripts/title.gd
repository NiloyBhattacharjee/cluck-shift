extends Control
## The title screen: a night-shift chicken in a hard hat, the controls and "Press Enter".
## Drawn with shapes. Shown only in MENU.

const NIGHT := Color("1b2330")
const INK := Color("eceff1")
const HI_VIS := Color("ff8f00")
const HAT := Color("ffca28")

var backup_keys := false  # set by main.gd when Shift arrives with no left/right (#22)
var records := {}  # main.gd's record book (#32): best night and the mute setting


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # the "Press Enter" blink and the chicken's bob


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(Vector2.ZERO, size), NIGHT)
	# a strip of belt along the bottom, with a moon for the night shift
	draw_rect(Rect2(0, 470, size.x, 70), Color("37474f"))
	for i in 16:
		var x := fmod(i * 64.0 + t * 60.0, size.x + 64.0) - 32.0
		draw_line(Vector2(x, 470), Vector2(x, 540), Color("546e7a"), 3)
	draw_circle(Vector2(860, 80), 34, Color("fff8e1"))
	draw_circle(Vector2(876, 70), 30, NIGHT)

	draw_string_outline(font, Vector2(0, 110), "CLUCK SHIFT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, 12, Color.BLACK)
	draw_string(font, Vector2(0, 110), "CLUCK SHIFT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, HAT)
	draw_string(font, Vector2(0, 148), "the night shift at the packing line, 10 PM to 6 AM", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, INK)
	if records.get("nights", 0) > 0:
		draw_string(font, Vector2(0, 180), _best_line(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color("90a4ae"))

	_draw_chicken(Vector2(210, 330 + sin(t * 3.0) * 4.0))

	var lines := [
		["LEFT SHIFT", "open / close the left gate"],
		["RIGHT SHIFT", "open / close the right gate"],
		["BOTH SHIFTS", "emergency stop (3 per night)"],
		["ENTER", "menus and the break-room shop"],
		["ESC  /  M", "pause  /  sound " + ("(now OFF)" if records.get("muted", false) else "on-off")],
	]
	for i in lines.size():
		var y := 215 + i * 30
		draw_string(font, Vector2(400, y), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HAT)
		draw_string(font, Vector2(560, y), lines[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	draw_string(font, Vector2(400, 370), "Set the gate before each tray hits the red line.", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(font, Vector2(400, 394), "The supervisor changes one rule every hour.", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(font, Vector2(400, 418), "3 strikes in one hour and you're sent home.", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)

	if backup_keys:
		draw_string(font, Vector2(0, 505), "Your setup can't tell left Shift from right Shift: use Z (left gate) and / (right gate).",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, HI_VIS)
	if fmod(t, 1.0) < 0.7:
		draw_string(font, Vector2(0, 458), "PRESS ENTER TO CLOCK IN", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, HAT)
	draw_string(font, Vector2(0, 528), "Windows: turn off the Sticky Keys shortcut first (Settings > Accessibility > Keyboard).   Game Off 2026: SHIFT",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color("90a4ae"))


## "BEST NIGHT $1,240 take-home   BEST COMBO 31   2 of 5 nights survived   SECRET ENDING FOUND"
func _best_line() -> String:
	var parts := PackedStringArray()
	if records.survived > 0:
		parts.append("BEST NIGHT  $%d take-home" % records.best_pay)
	parts.append("BEST COMBO  %d" % records.best_combo)
	parts.append("%d of %d nights survived" % [records.survived, records.nights])
	if records.secret:
		parts.append("SECRET ENDING FOUND")
	return "     ".join(parts)


func _draw_chicken(at: Vector2) -> void:
	var white := Color("fafafa")
	# legs
	for dx in [-22.0, 22.0]:
		draw_line(at + Vector2(dx, 70), at + Vector2(dx, 115), Color("ffa000"), 7)
		draw_line(at + Vector2(dx, 115), at + Vector2(dx + 16, 118), Color("ffa000"), 6)
	# body (an ellipse) and hi-vis vest with reflective stripes
	draw_set_transform(at + Vector2(0, 30), 0.0, Vector2(1.0, 0.8))
	draw_circle(Vector2.ZERO, 78, white)
	draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-60, -5), at + Vector2(60, -5), at + Vector2(52, 72), at + Vector2(-52, 72)]), HI_VIS)
	for y in [20.0, 45.0]:
		draw_line(at + Vector2(-58, y), at + Vector2(58, y), Color("e0e0e0"), 6)
	# wing holding a clipboard
	draw_rect(Rect2(at + Vector2(48, 0), Vector2(46, 58)), Color("8d6e63"))
	draw_rect(Rect2(at + Vector2(53, 8), Vector2(36, 46)), Color("fff8e1"))
	for i in 4:
		draw_line(at + Vector2(58, 18 + i * 9), at + Vector2(84, 18 + i * 9), Color("90a4ae"), 2)
	draw_circle(at + Vector2(52, 30), 16, white)
	# head, comb, eye, beak, wattle
	var head := at + Vector2(-8, -78)
	for i in 3:
		draw_circle(head + Vector2(-14 + i * 14, -34), 10, Color("e53935"))
	draw_circle(head, 40, white)
	draw_circle(head + Vector2(14, -6), 7, Color("263238"))
	draw_circle(head + Vector2(16, -8), 2.5, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([head + Vector2(34, 2), head + Vector2(60, 10), head + Vector2(34, 18)]), Color("ffa000"))
	draw_circle(head + Vector2(36, 26), 7, Color("e53935"))
	# hard hat
	draw_colored_polygon(_arc(head + Vector2(-2, -18), 42, PI, TAU), HAT)
	draw_rect(Rect2(head + Vector2(-52, -20), Vector2(100, 9)), HAT)
	draw_rect(Rect2(head + Vector2(-8, -60), Vector2(12, 40)), Color("ffb300"))


static func _arc(center: Vector2, radius: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 17:
		var a := lerpf(from, to, i / 16.0)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points
