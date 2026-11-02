class_name ShiftState
extends RefCounted
## Every rule of one night, with no nodes: gates, emergency stop, pay, combo, strikes
## and the belt ramp. main.gd shows it on screen; tests/test_logic.gd drives it directly.
## A new run is a new ShiftState, so there is no reset code to forget a field in.

const BOTH_SHIFT_WINDOW := 0.15  # seconds: second Shift this soon after the other = "both together"
const COMBO_STEP := 5  # every 5 correct in a row adds x1 to the pay multiplier
const MAX_MULTIPLIER := 5

var cfg: Dictionary
var route := "center"  # where the fork sends the next tray: "left", "center" or "right"
var clock := 0.0  # game seconds since clock-in (also times the both-Shifts window)
var speed := 0.0  # belt speed in px/s
var interval := 0.0  # seconds between new trays
var pay := 0
var combo := 0
var best_combo := 0
var strikes := 0
var sorted_ok := 0
var sorted_total := 0
var estops_left := 0
var stop_left := 0.0  # seconds of emergency stop still to run

var _route_before := "center"  # route before the latest toggle, restored by an emergency stop
var _last_press := {"left": -INF, "right": -INF}


func _init(config: Dictionary) -> void:
	cfg = config
	estops_left = int(cfg.estops)
	speed = cfg.belt.start_speed
	interval = cfg.belt.start_interval


## Advances game time by `delta`. Returns how far the belt moves (0 during an emergency stop).
func tick(delta: float) -> float:
	clock += delta
	if stop_left > 0.0:
		stop_left = maxf(stop_left - delta, 0.0)
		return 0.0
	var b: Dictionary = cfg.belt
	speed = minf(speed + b.speed_ramp * delta, b.max_speed)
	interval = maxf(interval - b.interval_ramp * delta, b.min_interval)
	return speed * delta


func is_stopped() -> bool:
	return stop_left > 0.0


## A Shift key went down ("left" or "right"). Returns what happened:
## "toggle" (gate moved), "estop" (belt stopped) or "denied" (both pressed, no stop available).
func press_shift(side: String) -> String:
	var other := "right" if side == "left" else "left"
	var both: bool = clock - _last_press[other] <= BOTH_SHIFT_WINDOW
	_last_press[side] = clock
	if not both:
		_route_before = route
		route = "center" if route == side else side
		return "toggle"
	route = _route_before  # the first Shift already toggled a gate; undo it
	_last_press = {"left": -INF, "right": -INF}  # a third quick press starts fresh
	if estops_left == 0 or is_stopped():
		return "denied"
	estops_left -= 1
	stop_left = cfg.estop_seconds
	return "estop"


## A tray of `kind` reached the fork. Scores it against the current route. Returns true if correct.
func sort(kind: String) -> bool:
	var ok: bool = cfg.routes.get(kind) == route
	sorted_total += 1
	if ok:
		sorted_ok += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		pay += int(cfg.pay_per_tray) * multiplier()
	else:
		combo = 0
		strikes += 1
	return ok


@warning_ignore("integer_division")
func multiplier() -> int:
	return mini(1 + combo / COMBO_STEP, MAX_MULTIPLIER)


func sent_home() -> bool:
	return strikes >= int(cfg.strikes_allowed)


func accuracy() -> float:
	return 0.0 if sorted_total == 0 else float(sorted_ok) / sorted_total
