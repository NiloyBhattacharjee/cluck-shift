class_name ShiftState
extends RefCounted
## Every rule of one night, with no nodes: the hours and their supervisor notes, gates,
## gate swing, emergency stop, pay, combo, strikes, the belt ramp, the shop, the PA and the strange
## night (trays in disguise, radio clucks, flickering lights, the ending). main.gd shows it
## on screen; tests/test_logic.gd drives it directly. A new night is a new ShiftState,
## so there is no reset code to forget a field in.

const BOTH_SHIFT_WINDOW := 0.15  # seconds: second Shift this soon after the other = "both together"
const COMBO_STEP := 5  # every 5 correct in a row adds x1 to the pay multiplier
const MAX_MULTIPLIER := 5
const EXITS := ["left", "center", "right"]
const STRANGE := "stranger"  # a chicken in sunglasses and a trench coat; no rule covers it

var cfg: Dictionary
var rng := RandomNumberGenerator.new()
var routes := {}  # tray kind -> exit; supervisor notes change it
var stamps := {}  # stamp colour -> exit; a stamp beats the kind
var dead_stamps := []  # stamps a note cancelled: still printed, but the tray goes where its kind goes
var route := "center"  # where the fork sends the next tray: "left", "center" or "right"
var clock := 0.0  # game seconds since clock-in (also times the both-Shifts window)
var hour := -1  # index into cfg.hours; -1 until the first hour starts
var hour_elapsed := 0.0  # seconds into this hour, not counting emergency stops
var note := {}  # this hour's supervisor note
var changed: Array = []  # kinds or stamps this hour's note changed (highlighted on the board)
var speed := 0.0  # belt speed in px/s
var interval := 0.0  # seconds between new trays

var pay := 0  # earned over the night, bonuses included
var spent := 0  # spent in the shop
var winnings := 0  # net result of Double or Nothing and Chicken Slots; can be negative
var bet := 0  # staked on this hour being clean (Double or Nothing)
var last_bet := 0  # what the latest Double or Nothing made or lost
var last_spin := {}  # the latest Chicken Slots result: reels, payout
var last_gain := 0  # pay from the latest correct tray
var combo := 0  # carries over between hours
var best_combo := 0
var sorted_ok := 0  # night totals
var sorted_total := 0
var strikes := 0  # this hour only
var hour_sorted := 0
var hour_ok := 0
var hour_pay := 0
var ledger: Array = []  # every finished hour's tally, in order (the 6 AM chart, #33)
var estops_left := 0  # for the whole night
var stop_left := 0.0  # seconds of emergency stop still to run
var swing_left := 0.0  # seconds until the gate finishes moving
var last_missed := false  # the latest sorted tray reached the red line mid-swing

var coffee := false  # this hour: belt slower (bought in the shop before the hour)
var earplugs := false  # this hour: no PA announcements
var mates := 0  # strikes your mate will still cover; carries over until used

var pa_left := 0.0  # seconds the current PA announcement still shows
var pa_line := ""  # what it says
var pa_count := 0  # announcements so far (main.gd plays the jingle when this goes up)
var _pa_next := INF  # seconds until the next announcement
var pa_radio := false  # the current announcement is clucking on the radio, not the PA

var strange_seen := 0  # strange trays that reached the red line, all night
var escaped := 0  # of those, sent straight on to the loading dock
var hour_strange := 0  # strange trays spawned this hour (at most strange.max_per_hour)

var _last_exit := "center"  # where the latest tray was sent; the gates start each hour closed
var _exit_run := 1  # how many trays in a row have gone there
var _route_before := "center"  # route before the latest toggle, restored by an emergency stop
var _last_press := {"left": -INF, "right": -INF}


func _init(config: Dictionary, seed := -1) -> void:
	cfg = config
	routes = cfg.routes.duplicate()
	estops_left = int(cfg.estops)
	if seed >= 0:
		rng.seed = seed


# --- hours -----------------------------------------------------------------

## Starts the next hour: per-hour counters reset, its supervisor note applies, gates close.
func start_hour() -> void:
	hour += 1
	hour_elapsed = 0.0
	strikes = 0
	hour_sorted = 0
	hour_ok = 0
	hour_pay = 0
	hour_strange = 0
	route = "center"
	_last_exit = "center"
	_exit_run = 1
	swing_left = 0.0
	note = cfg.hours[hour].get("note", {})
	changed = apply_note(note)
	pa_left = 0.0
	_pa_next = INF
	if hour >= cfg.pa.from_hour and not earplugs:
		_pa_next = cfg.note_seconds + rng.randf_range(cfg.pa.every[0], cfg.pa.every[1])
	_update_belt()


## Applies one supervisor note to the rules. Returns the kinds or stamps it changed.
## A note holds at most one of: "route" {kind: exit}, "stamp" {colour: exit or null}, "swap" [exit, exit].
func apply_note(n: Dictionary) -> Array:
	if n.has("route"):
		routes.merge(n.route, true)
		return n.route.keys()
	if n.has("stamp"):
		for s: String in n.stamp:
			if n.stamp[s] == null:
				stamps.erase(s)
				dead_stamps.append(s)
			else:
				stamps[s] = n.stamp[s]
				dead_stamps.erase(s)
		return n.stamp.keys()
	if n.has("swap"):
		var a: String = n.swap[0]
		var b: String = n.swap[1]
		var touched := []
		for table: Dictionary in [routes, stamps]:
			for key: String in table:
				if table[key] == a or table[key] == b:
					table[key] = b if table[key] == a else a
					touched.append(key)
		return touched
	return []


## Ends the hour. Adds the clean-hour bonus, uses up this hour's items, and returns the tally
## (also kept in `ledger`).
func end_hour() -> Dictionary:
	var bonus := int(cfg.clean_hour_bonus) if strikes == 0 and hour_sorted > 0 else 0
	pay += bonus
	last_bet = 0
	if bet > 0:
		last_bet = bet if strikes == 0 and hour_sorted > 0 else -bet
		winnings += bet + last_bet
		bet = 0
	coffee = false
	earplugs = false
	var tally := {"from": hour_name(hour), "to": hour_name(hour + 1), "sorted": hour_sorted, "ok": hour_ok,
		"strikes": strikes, "pay": hour_pay, "bonus": bonus, "total": pay}
	ledger.append(tally)
	return tally


# --- shop ------------------------------------------------------------------

func wallet() -> int:
	return pay - spent + winnings


func shop_item(id: String) -> Dictionary:
	for item: Dictionary in cfg.shop:
		if item.id == id:
			return item
	return {}


## Buys one item between hours. Returns false (and changes nothing) if it costs more than the wallet.
## Coffee and Earplugs work for the next hour; Mate's Help lasts until it covers a strike.
func buy(id: String) -> bool:
	var item := shop_item(id)
	if item.is_empty() or item.price > wallet():
		return false
	if id == "double" or id == "slots":
		winnings -= int(item.price)
	else:
		spent += int(item.price)
	match id:
		"coffee":
			coffee = true
		"earplugs":
			earplugs = true
		"mate":
			mates += 1
		"double":
			bet = int(item.price)
		"slots":
			_spin()
	return true


## One go on Chicken Slots: three reels, each picked on its own by slots.weights.
func _spin() -> void:
	var reels := [_weighted(cfg.slots.weights), _weighted(cfg.slots.weights), _weighted(cfg.slots.weights)]
	var payout := 0
	if reels[0] == reels[1] and reels[1] == reels[2]:
		payout = int(cfg.slots.three[reels[0]])
	elif reels[0] == reels[1] or reels[1] == reels[2] or reels[0] == reels[2]:
		payout = int(cfg.slots.pair)
	winnings += payout
	last_spin = {"reels": reels, "payout": payout}


func _weighted(weights: Dictionary) -> String:
	var total := 0.0
	for key: String in weights:
		total += weights[key]
	var roll := rng.randf() * total
	for key: String in weights:
		roll -= weights[key]
		if roll < 0.0:
			return key
	return weights.keys()[0]


func is_last_hour() -> bool:
	return hour >= cfg.hours.size() - 1


## "10 PM" for hour 0, "6 AM" for hour 8.
static func hour_name(index: int) -> String:
	var h := (22 + index) % 24
	return "%d %s" % [12 if h % 12 == 0 else h % 12, "PM" if h >= 12 else "AM"]


## The wall clock: "11:42 PM".
func clock_text() -> String:
	var minutes := mini(int(hour_elapsed / cfg.hour_seconds * 60.0), 59)
	var parts := hour_name(maxi(hour, 0)).split(" ")
	return "%s:%02d %s" % [parts[0], minutes, parts[1]]


# --- time and belt ---------------------------------------------------------

## Advances game time by `delta`. Returns how far the belt moves (0 during an emergency stop).
func tick(delta: float) -> float:
	clock += delta
	swing_left = maxf(swing_left - delta, 0.0)
	_tick_pa(delta)
	if stop_left > 0.0:
		stop_left = maxf(stop_left - delta, 0.0)
		return 0.0
	hour_elapsed += delta
	_update_belt()
	return speed * delta


## Belt speed and tray interval slide linearly from the hour's first to its second value.
## Coffee slows the belt and spaces trays out by the same factor, so gaps stay the same.
func _update_belt() -> void:
	var h: Dictionary = cfg.hours[hour]
	var p := clampf(hour_elapsed / cfg.hour_seconds, 0.0, 1.0)
	var k: float = cfg.coffee_factor if coffee else 1.0
	speed = lerpf(h.speed[0], h.speed[1], p) * k
	interval = lerpf(h.interval[0], h.interval[1], p) / k


## PA announcements: from pa.from_hour, every few seconds (random within pa.every), unless earplugs.
## They run on the game clock, emergency stops included: the PA does not stop for the belt.
func _tick_pa(delta: float) -> void:
	if pa_left > 0.0:
		pa_left = maxf(pa_left - delta, 0.0)
		return
	_pa_next -= delta
	if _pa_next <= 0.0:
		pa_left = cfg.pa.seconds
		pa_radio = is_strange_hour() and rng.randf() < cfg.strange.radio_chance
		var lines: Array = cfg.strange.radio if pa_radio else cfg.pa.lines
		pa_line = lines[rng.randi() % lines.size()]
		pa_count += 1
		_pa_next = rng.randf_range(cfg.pa.every[0], cfg.pa.every[1])


func is_stopped() -> bool:
	return stop_left > 0.0


func is_swinging() -> bool:
	return swing_left > 0.0


## From strange.from_hour (2 AM) the night gets strange: disguised trays, radio clucks, flickering lights.
func is_strange_hour() -> bool:
	return hour >= int(cfg.strange.from_hour)


## The lights are out during the strange.flicker.dark windows of every strange.flicker.every seconds.
## Runs on the game clock, so it keeps flickering through an emergency stop.
func lights_out() -> bool:
	if not is_strange_hour():
		return false
	var t := fmod(clock, cfg.strange.flicker.every)
	for w: Array in cfg.strange.flicker.dark:
		if t >= w[0] and t < w[1]:
			return true
	return false


## How the night ends at 6 AM: "secret" if strange trays came by and every one was sent straight on
## to the loading dock (The Great Escape), otherwise "normal" (the payslip and the bus home).
func ending() -> String:
	return "secret" if strange_seen > 0 and escaped == strange_seen else "normal"


## Picks the next tray. The exit comes first, every open exit equally likely, so no food is common
## just because several kinds share a bin. An exit can't repeat, because a repeat needs no key press:
## from no_repeat_from no two trays in a row share one, and before that never three. A strange tray
## (from 2 AM, a few an hour) counts as going straight on, where it wants to go.
func next_tray() -> Dictionary:
	if is_strange_hour() and hour_strange < int(cfg.strange.max_per_hour) and _last_exit != "center" \
			and rng.randf() < cfg.strange.chance:
		hour_strange += 1
		_note_exit("center")
		return {"kind": STRANGE, "stamp": ""}
	var open := EXITS.filter(func(e: String) -> bool: return e in routes.values() or e in stamps.values())
	if open.size() > 1 and _exit_run >= (1 if hour >= int(cfg.no_repeat_from) else 2):
		open.erase(_last_exit)
	var exit: String = _pick(open)
	_note_exit(exit)
	var kinds := routes.keys().filter(func(k: String) -> bool: return routes[k] == exit)
	var colours := stamps.keys().filter(func(s: String) -> bool: return stamps[s] == exit)
	if not colours.is_empty() and (kinds.is_empty() or rng.randf() < cfg.stamp_chance):
		return {"kind": _pick(routes.keys()), "stamp": _pick(colours)}
	var decoy: String = _pick(dead_stamps) if not dead_stamps.is_empty() and rng.randf() < cfg.stamp_chance else ""
	return {"kind": _pick(kinds), "stamp": decoy}


## Seconds until the next tray: this moment's interval, varied so the rhythm can't be learned.
func next_gap() -> float:
	var jitter: float = cfg.interval_jitter
	return interval * rng.randf_range(1.0 - jitter, 1.0 + jitter)


func _note_exit(exit: String) -> void:
	_exit_run = _exit_run + 1 if exit == _last_exit else 1
	_last_exit = exit


func _pick(from: Array) -> Variant:
	return from[rng.randi() % from.size()]


## Where a tray belongs. A stamp rule beats the kind rule.
func exit_for(kind: String, stamp := "") -> String:
	return stamps[stamp] if stamps.has(stamp) else routes[kind]


# --- input -----------------------------------------------------------------

## A Shift key went down ("left" or "right"). Returns what happened:
## "toggle" (gate moved), "estop" (belt stopped) or "denied" (both pressed, no stop available).
func press_shift(side: String) -> String:
	var other := "right" if side == "left" else "left"
	var both: bool = clock - _last_press[other] <= BOTH_SHIFT_WINDOW
	_last_press[side] = clock
	if not both:
		_route_before = route
		route = "center" if route == side else side
		swing_left = cfg.swing_seconds
		return "toggle"
	route = _route_before  # the first Shift already toggled a gate; undo it
	_last_press = {"left": -INF, "right": -INF}  # a third quick press starts fresh
	if estops_left == 0 or is_stopped():
		return "denied"
	estops_left -= 1
	stop_left = cfg.estop_seconds
	return "estop"


# --- scoring ---------------------------------------------------------------

## A tray reached the red line. Returns "ok", "wrong", "missed" (the gate was still swinging, so the
## tray falls off the line) or "covered" (wrong or missed, but your mate took the strike).
## Wrong and missed are strikes. last_missed says whether the tray fell, whatever the result.
## A strange tray is "escaped" (sent straight on, to the loading dock) or "caught" (anywhere else, or it
## fell): never a strike, never pay, the combo is untouched and it doesn't count towards accuracy.
func sort(kind: String, stamp := "") -> String:
	var missed := is_swinging()
	last_missed = missed
	if kind == STRANGE:
		strange_seen += 1
		if not missed and route == "center":
			escaped += 1
			return "escaped"
		return "caught"
	sorted_total += 1
	hour_sorted += 1
	if not missed and exit_for(kind, stamp) == route:
		sorted_ok += 1
		hour_ok += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		last_gain = int(cfg.pay_per_tray) * multiplier()
		pay += last_gain
		hour_pay += last_gain
		return "ok"
	combo = 0
	if mates > 0:
		mates -= 1
		return "covered"
	strikes += 1
	return "missed" if missed else "wrong"


@warning_ignore("integer_division")
func multiplier() -> int:
	return mini(1 + combo / COMBO_STEP, MAX_MULTIPLIER)


func sent_home() -> bool:
	return strikes >= int(cfg.strikes_allowed)


func accuracy() -> float:
	return 0.0 if sorted_total == 0 else float(sorted_ok) / sorted_total
