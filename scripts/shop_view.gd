extends Control
## The break-room vending machine between hours: one card per item plus Skip, in two rows.
## main.gd owns the selection and the buying; this only draws it.

const CARD := Vector2(280, 122)
const GAP := 12.0
const PER_ROW := 3
const TOP := 158.0
const HAT := Color("ffca28")
const INK := Color("eceff1")

var items: Array = []  # shop entries from rules.json, plus a Skip card
var selected := 0
var wallet := 0
var heading := ""
var owned := ""  # what is already active, e.g. "Mate's Help x1"
var bet_result := 0  # what last hour's Double or Nothing made or lost; 0 if there was none
var touch := false  # tap wording and larger card text (#44)


## The card at index `i` on screen.
func card_rect(i: int) -> Rect2:
	var row_width := PER_ROW * CARD.x + (PER_ROW - 1) * GAP
	@warning_ignore("integer_division")
	return Rect2(Vector2((size.x - row_width) / 2.0 + (i % PER_ROW) * (CARD.x + GAP), TOP + (i / PER_ROW) * (CARD.y + GAP)), CARD)


## The card under a tap, or -1.
func card_at(at: Vector2) -> int:
	for i in items.size():
		if card_rect(i).has_point(at):
			return i
	return -1


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.11, 0.94))
	draw_string(font, Vector2(0, 54), "BREAK ROOM VENDING", HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, HAT)
	draw_string(font, Vector2(0, 84), heading, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, INK)
	draw_string(font, Vector2(0, 112), "Your pay: $%d%s" % [wallet, ("     Active: " + owned) if owned != "" else ""], HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, INK)
	if bet_result != 0:
		var won := bet_result > 0
		draw_string(font, Vector2(0, 140), "DOUBLE OR NOTHING: %s $%d" % ["YOU WON" if won else "YOU LOST", absi(bet_result)],
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, HAT if won else Color("ef5350"))
	for i in items.size():
		var item: Dictionary = items[i]
		var at := card_rect(i).position
		var affordable: bool = item.price <= wallet
		draw_rect(Rect2(at, CARD), Color("37474f") if i == selected else Color("263238"))
		draw_rect(Rect2(at, CARD), HAT if i == selected else Color("546e7a"), false, 4.0 if i == selected else 2.0)
		draw_string(font, at + Vector2(14, 32), item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		var price := "free" if item.price == 0 else "$%d" % item.price
		if not affordable:
			price = "can't afford " + price
		draw_string(font, at + Vector2(0, 32), price, HORIZONTAL_ALIGNMENT_RIGHT, CARD.x - 14, 16, HAT if affordable else Color("ef5350"))
		draw_multiline_string(font, at + Vector2(14, 60), item.text, HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 28, 16 if touch else 14, -1, Color("b0bec5"))
	draw_string(font, Vector2(0, 450), "TAP  choose        TAP AGAIN  buy" if touch else "LEFT / RIGHT SHIFT  choose        ENTER  buy", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, INK)
	draw_string(font, Vector2(0, 480), "One item per break. Whatever you spend comes off your take-home pay.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("90a4ae"))
