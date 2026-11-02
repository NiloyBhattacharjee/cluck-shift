class_name Tray
extends Area2D
## One tray of chicken. Main moves it along `path`; the Fork Area2D routes it.

const FOOD := {"wing": Color("ffa726"), "drumstick": Color("a1653a"), "nugget": Color("ffd54f")}

var kind := "wing"
var path: Array = []  # Vector2 waypoints still to visit
var routed := false
var result := 0  # 0 = not at the fork yet, 1 = sorted right, -1 = strike


## Moves `dist` pixels along the path. Returns true once the path is used up.
func advance(dist: float) -> bool:
	while dist > 0.0 and not path.is_empty():
		var to: Vector2 = path[0] - position
		if to.length() <= dist:
			position = path.pop_front()
			dist -= to.length()
		else:
			position += to.normalized() * dist
			dist = 0.0
	return path.is_empty()


func _draw() -> void:
	var box := Rect2(-26, -18, 52, 36)
	draw_rect(box, Color("eceff1"))
	match kind:
		"wing":
			draw_colored_polygon(PackedVector2Array([Vector2(-18, 8), Vector2(16, -12), Vector2(6, 2), Vector2(14, 10)]), FOOD.wing)
		"drumstick":
			draw_line(Vector2(-16, 10), Vector2(-2, 0), Color("bcaaa4"), 5)
			draw_circle(Vector2(-18, 11), 4, Color("bcaaa4"))
			draw_circle(Vector2(6, -4), 11, FOOD.drumstick)
		"nugget":
			for p in [Vector2(-11, -4), Vector2(9, -6), Vector2(0, 7)]:
				draw_circle(p, 7, FOOD.nugget)
	var edge := Color("90a4ae")
	if result != 0:
		edge = Color("66bb6a") if result > 0 else Color("ef5350")
	draw_rect(box, edge, false, 3.0 if result == 0 else 5.0)
