extends Control
## The break-room vending machine between hours: one card per item plus Skip.
## main.gd owns the selection and the buying; this only draws it.

const CARD := Vector2(200, 190)
const GAP := 16.0
const HAT := Color("ffca28")
const INK := Color("eceff1")

var items: Array = []  # shop entries from rules.json, plus a Skip card
var selected := 0
var wallet := 0
var heading := ""
var owned := ""  # what is already active, e.g. "Mate's Help x1"


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.11, 0.94))
	draw_string(font, Vector2(0, 70), "BREAK ROOM VENDING", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, HAT)
	draw_string(font, Vector2(0, 106), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, INK)
	draw_string(font, Vector2(0, 140), "Your pay: $%d%s" % [wallet, ("     Active: " + owned) if owned != "" else ""], HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, INK)
	var total := items.size() * CARD.x + (items.size() - 1) * GAP
	for i in items.size():
		var item: Dictionary = items[i]
		var lifted := 12.0 if i == selected else 0.0
		var at := Vector2((size.x - total) / 2.0 + i * (CARD.x + GAP), 175.0 - lifted)
		var affordable: bool = item.price <= wallet
		draw_rect(Rect2(at, CARD), Color("37474f") if i == selected else Color("263238"))
		draw_rect(Rect2(at, CARD), HAT if i == selected else Color("546e7a"), false, 4.0 if i == selected else 2.0)
		draw_string(font, at + Vector2(0, 38), item.name, HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 22, INK)
		var price := "free" if item.price == 0 else "$%d" % item.price
		draw_string(font, at + Vector2(0, 70), price, HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 20, HAT if affordable else Color("ef5350"))
		draw_multiline_string(font, at + Vector2(14, 100), item.text, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 28, 14, -1, Color("b0bec5"))
		if not affordable:
			draw_string(font, at + Vector2(0, CARD.y - 12), "can't afford", HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 14, Color("ef5350"))
	draw_string(font, Vector2(0, 430), "LEFT / RIGHT SHIFT  choose        ENTER  buy and start the next hour", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, INK)
	draw_string(font, Vector2(0, 460), "One item per break. Whatever you spend comes off your take-home pay.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("90a4ae"))
