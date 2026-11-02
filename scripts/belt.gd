class_name Belt
extends Node2D
## Draws the conveyor, the fork, the two gates and the bins. Owns the layout points.

const SPAWN := Vector2(480, -30)
const FORK := Vector2(480, 330)
const EXITS := {"left": Vector2(190, 460), "center": Vector2(480, 480), "right": Vector2(770, 460)}
const FLOOR := Vector2(335, 600)  # where a missed tray tumbles to, off the bottom of the screen
const DECISION_Y := FORK.y - 35.0  # top edge of the Fork Area2D: a tray touching this is committed
const WIDTH := 64.0
const LIT := Color("ffca28")
const DARK := Color("37474f")

var scroll := 0.0  # belt travel, animates the stripes
var route := "center"
var labels := {}  # route -> Array of lines naming what goes in that bin, filled from the rules
var swinging := false  # gate still moving: both gate boxes flash


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for r in EXITS:  # chutes: the open one glows
		draw_line(FORK, EXITS[r], LIT if r == route else DARK, WIDTH + 10)
	for r in EXITS:
		draw_line(FORK, EXITS[r], Color("455a64"), WIDTH - 6)
	# main belt with moving slats
	var left := FORK.x - WIDTH / 2
	draw_rect(Rect2(left, -40, WIDTH, FORK.y + 40), DARK)
	var y := fmod(scroll, 32.0) - 40.0
	while y < FORK.y:
		draw_line(Vector2(left, y), Vector2(left + WIDTH, y), Color("546e7a"), 3)
		y += 32.0
	draw_line(Vector2(left, -40), Vector2(left, FORK.y), Color("90a4ae"), 4)
	draw_line(Vector2(left + WIDTH, -40), Vector2(left + WIDTH, FORK.y), Color("90a4ae"), 4)
	draw_dashed_line(Vector2(left - 20, DECISION_Y), Vector2(left + WIDTH + 20, DECISION_Y), Color("ef5350"), 3, 8)
	# fork hub, direction arrow and the two gates
	draw_circle(FORK, 30, Color("263238"))
	draw_line(FORK, FORK + (EXITS[route] - FORK).normalized() * 28, LIT, 8)
	for g in [["left", Vector2(-120, -40), "L-SHIFT"], ["right", Vector2(60, -40), "R-SHIFT"]]:
		var box := Rect2(FORK + g[1], Vector2(60, 28))
		draw_rect(box, Color("ff7043") if swinging else (LIT if route == g[0] else DARK))
		draw_string(font, box.position + Vector2(0, 19), g[2], HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.BLACK if route == g[0] else Color.WHITE)
	# bins
	for r in EXITS:
		var bin := Rect2(EXITS[r] + Vector2(-75, -20), Vector2(150, 64))
		draw_rect(bin, Color("6d4c41"))
		draw_rect(bin, LIT if r == route else Color("3e2723"), false, 4)
		var lines: Array = labels.get(r, [])
		if lines.is_empty():
			lines = ["(empty)"]
		for i in lines.size():
			draw_string(font, bin.position + Vector2(0, 18 + i * 16 + (3 - lines.size()) * 8), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 150, 13)
