extends SceneTree
## Sanity tests for the rules (ShiftState), the tray path and data/rules.json.
## Run: godot --headless -s tests/test_logic.gd     (exit code 0 = all passed)

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var failures := 0


func _initialize() -> void:
	test_gates()
	test_gate_swing()
	test_emergency_stop()
	test_scoring_and_combo()
	test_strikes_per_hour()
	test_clock()
	test_belt_per_hour()
	test_supervisor_notes()
	test_hour_tally()
	test_next_tray()
	test_tray_path()
	test_rules_data()
	print("\n%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


## A night that has clocked in to its first hour.
func night() -> ShiftState:
	var s := ShiftState.new(cfg, 7)
	s.start_hour()
	return s


func test_gates() -> void:
	var s := night()
	check(s.route == "center", "gates start closed: trays go straight")
	s.press_shift("left")
	check(s.route == "left", "Left Shift opens the left gate")
	s.tick(0.5)
	s.press_shift("left")
	check(s.route == "center", "Left Shift again closes it")
	s.tick(0.5)
	s.press_shift("right")
	check(s.route == "right", "Right Shift opens the right gate")
	s.tick(0.5)
	s.press_shift("left")
	check(s.route == "left", "opening one gate closes the other")
	s.tick(0.5)
	s.press_shift("left")
	s.press_shift("left")
	check(s.route == "left", "same Shift twice fast is two toggles, not a stop")
	check(s.estops_left == int(cfg.estops), "...and uses no emergency stop")
	s.start_hour()
	check(s.route == "center", "gates close at the start of each hour")


func test_gate_swing() -> void:
	var s := night()
	s.press_shift("left")
	check(s.is_swinging(), "a toggle starts the gate swinging")
	check(s.sort("wing") == "missed", "a tray at the red line while the gate swings is missed")
	check(s.strikes == 1 and s.combo == 0, "a missed tray is a strike and resets the combo")
	s.tick(cfg.swing_seconds + 0.01)
	check(not s.is_swinging(), "the swing ends after swing_seconds")
	check(s.sort("wing") == "ok", "after the swing the tray goes where the gate points")
	s.route = "left"
	check(s.sort("nugget") == "wrong", "a tray in the wrong exit is wrong, not missed")


func test_emergency_stop() -> void:
	var s := night()
	s.press_shift("right")
	s.tick(1.0)
	s.press_shift("left")
	s.tick(ShiftState.BOTH_SHIFT_WINDOW / 2)
	check(s.press_shift("right") == "estop", "both Shifts within the window = emergency stop")
	check(s.route == "right", "emergency stop leaves the gate as it was before the pair")
	check(s.estops_left == int(cfg.estops) - 1, "emergency stop uses one charge")
	var speed := s.speed
	var elapsed := s.hour_elapsed
	check(s.tick(0.1) == 0.0 and s.is_stopped(), "belt does not move while stopped")
	check(s.speed == speed, "belt does not speed up while stopped")
	check(s.hour_elapsed == elapsed, "the hour does not run down while stopped")
	s.press_shift("left")
	check(s.route == "left", "gates still work during the stop")
	s.tick(0.2)
	s.press_shift("left")
	s.press_shift("right")
	check(s.estops_left == int(cfg.estops) - 1, "a second stop during a stop is refused")
	s.tick(cfg.estop_seconds)
	check(not s.is_stopped() and s.tick(0.1) > 0.0, "belt restarts after estop_seconds")

	var t := night()
	for i in int(cfg.estops):
		t.press_shift("left")
		t.press_shift("right")
		t.tick(cfg.estop_seconds + 1.0)
	t.start_hour()
	check(t.estops_left == 0, "emergency stops are per night, not per hour")
	t.press_shift("left")
	check(t.press_shift("right") == "denied" and t.route == "center", "no stops left: refused, gate unchanged")

	var u := night()
	u.press_shift("left")
	u.tick(ShiftState.BOTH_SHIFT_WINDOW + 0.05)
	check(u.press_shift("right") == "toggle", "Shifts further apart than the window are two toggles")


func test_scoring_and_combo() -> void:
	var s := night()
	var pay := int(cfg.pay_per_tray)
	s.route = "left"  # wings go left
	check(s.sort("wing") == "ok" and s.pay == pay and s.combo == 1, "correct sort pays pay_per_tray and starts a combo")
	for i in 3:
		s.sort("wing")
	check(s.multiplier() == 1 and s.pay == 4 * pay, "x1 for the first 4 in a row")
	s.sort("wing")
	check(s.multiplier() == 2 and s.pay == 6 * pay and s.last_gain == 2 * pay, "5th in a row pays x2")
	check(s.sort("nugget") == "wrong" and s.combo == 0 and s.strikes == 1, "wrong sort: strike, combo resets")
	check(s.best_combo == 5, "best combo remembered")
	check(s.pay == 6 * pay and s.hour_pay == 6 * pay, "a strike costs no pay")
	check(is_equal_approx(s.accuracy(), 5.0 / 6.0), "accuracy = correct / sorted")
	for i in 100:
		s.sort("wing")
	check(s.multiplier() == ShiftState.MAX_MULTIPLIER, "multiplier is capped")
	s.start_hour()
	check(s.combo == 100, "the combo carries into the next hour")
	check(ShiftState.new(cfg).accuracy() == 0.0, "accuracy with nothing sorted is 0, not a crash")


func test_strikes_per_hour() -> void:
	var s := night()  # gate straight: wings are wrong
	for i in int(cfg.strikes_allowed) - 1:
		s.sort("wing")
	check(not s.sent_home(), "one strike short: still working")
	s.start_hour()
	check(s.strikes == 0 and not s.sent_home(), "strikes reset at the start of each hour")
	for i in int(cfg.strikes_allowed):
		s.sort("wing")
	check(s.sent_home(), "strikes_allowed strikes in one hour: sent home")


func test_clock() -> void:
	check(ShiftState.hour_name(0) == "10 PM" and ShiftState.hour_name(2) == "12 AM" and ShiftState.hour_name(8) == "6 AM", "hours run 10 PM, 11 PM, 12 AM ... 6 AM")
	var s := night()
	check(s.clock_text() == "10:00 PM", "the night starts at 10:00 PM")
	s.tick(cfg.hour_seconds / 2.0)
	check(s.clock_text() == "10:30 PM", "half an hour in is 10:30")
	s.tick(cfg.hour_seconds)
	check(s.clock_text() == "10:59 PM", "the clock never shows the next hour early")
	for i in cfg.hours.size() - 1:
		s.start_hour()
	check(s.clock_text() == "5:00 AM" and s.is_last_hour(), "the last hour is 5 AM")


func test_belt_per_hour() -> void:
	var s := night()
	var h: Dictionary = cfg.hours[0]
	check(s.speed == h.speed[0] and s.interval == h.interval[0], "each hour starts at its first speed and interval")
	s.tick(cfg.hour_seconds / 2.0)
	check(is_equal_approx(s.speed, (h.speed[0] + h.speed[1]) / 2.0), "speed rises linearly through the hour")
	s.tick(cfg.hour_seconds * 2)
	check(s.speed == h.speed[1] and s.interval == h.interval[1], "and stops at the hour's second value")
	s.start_hour()
	check(s.speed == cfg.hours[1].speed[0], "the next hour starts at its own speed")


func test_supervisor_notes() -> void:
	var s := night()
	check(s.changed.is_empty() and s.routes == cfg.routes, "10 PM: the starting rules, nothing new")
	s.start_hour()
	check(s.routes.nugget == "right" and s.changed == ["nugget"], "11 PM: nuggets go right")
	s.start_hour()
	check(s.stamps == {"red": "center"} and s.changed == ["red"], "12 AM: red stamps go straight")
	check(s.exit_for("wing", "red") == "center" and s.exit_for("wing") == "left", "a stamp beats the kind; no stamp uses the kind")
	s.start_hour()
	check(s.routes.tender == "left", "1 AM: tenders added, going left")
	s.start_hour()
	check(s.routes == {"wing": "right", "drumstick": "left", "nugget": "left", "tender": "right"}, "2 AM: swap moves every left kind right and back")
	check(s.stamps.red == "center", "the swap leaves the straight exit alone")
	check(s.changed.size() == 4 and not "red" in s.changed, "the swap highlights exactly what moved")
	s.start_hour()
	s.start_hour()
	s.start_hour()
	check(s.stamps == {"blue": "left"} and s.routes.wing == "center", "5 AM: red stamps gone, blue stamps left, wings straight")
	var copy: Dictionary = cfg.routes.duplicate()
	check(cfg.routes == copy and ShiftState.new(cfg).routes == {"wing": "left", "drumstick": "right", "nugget": "center"}, "notes never change the data a new night starts from")


func test_hour_tally() -> void:
	var s := night()
	s.route = "left"
	s.sort("wing")
	var pay := s.pay
	var t := s.end_hour()
	check(t.bonus == int(cfg.clean_hour_bonus) and t.total == pay + t.bonus, "a clean hour earns the bonus")
	check(t.from == "10 PM" and t.to == "11 PM" and t.sorted == 1 and t.ok == 1, "the tally names the hour and counts it")
	s.start_hour()
	s.sort("wing")
	check(s.end_hour().bonus == 0, "no bonus after a strike")
	s.start_hour()
	check(s.end_hour().bonus == 0, "no bonus for an hour with nothing sorted")


func test_next_tray() -> void:
	var s := night()
	var seen := {}
	for i in 300:
		var t := s.next_tray()
		seen[t.kind] = true
		if t.stamp != "":
			seen["stamp"] = true
	check(seen.size() == 3 and not seen.has("stamp"), "before any stamp rule: only the three kinds, no stamps")
	s.start_hour()
	s.start_hour()
	s.start_hour()
	var stamped := 0
	var tenders := 0
	for i in 1000:
		var t := s.next_tray()
		stamped += int(t.stamp == "red")
		tenders += int(t.kind == "tender")
	check(abs(stamped / 1000.0 - cfg.stamp_chance) < 0.06, "about stamp_chance of trays are stamped (%d / 1000)" % stamped)
	check(tenders > 150, "a new kind starts spawning as soon as it has a rule")


func test_tray_path() -> void:
	var t := Tray.new()
	t.position = Vector2(0, 0)
	t.path = [Vector2(0, 100), Vector2(100, 100)]
	check(not t.advance(50.0) and t.position == Vector2(0, 50), "tray moves along the first leg")
	check(not t.advance(100.0) and t.position == Vector2(50, 100), "tray turns the corner without losing distance")
	check(t.advance(500.0) and t.position == Vector2(100, 100), "tray stops at the end and reports done")
	t.falling = true
	t.path = [Vector2(0, 0)]
	t.advance(10.0)
	check(t.rotation != 0.0, "a missed tray tumbles")
	t.free()


func test_rules_data() -> void:
	var kinds: Array = cfg.routes.keys()
	var stamp_colours := []
	check(cfg.hours.size() == 8, "eight hours: 10 PM to 6 AM")
	check(cfg.hour_seconds >= cfg.note_seconds + 30, "most of each hour is sorting, not reading")
	for i in cfg.hours.size():
		var h: Dictionary = cfg.hours[i]
		var name := ShiftState.hour_name(i)
		check(h.speed[1] >= h.speed[0] and h.interval[1] <= h.interval[0], "%s: belt gets faster during the hour" % name)
		# trays are 36 px tall; the gap between them is speed * interval at spawn time
		check(minf(h.speed[0] * h.interval[0], h.speed[1] * h.interval[1]) > 100, "%s: trays never overlap" % name)
		check(h.interval[1] >= 0.6, "%s: at least 0.6 s per tray" % name)
		var n: Dictionary = h.get("note", {})
		check(n.has("text"), "%s: has a supervisor note" % name)
		var changes := ["route", "stamp", "swap"].filter(func(k): return n.has(k))
		check(changes.size() == (0 if i == 0 else 1), "%s: the note changes exactly %s" % [name, "nothing" if i == 0 else "one rule"])
		if n.has("route"):
			check(n.route.size() == 1 and n.route.values()[0] in ShiftState.EXITS, "%s: route names one kind and a real exit" % name)
			kinds.append_array(n.route.keys())
		if n.has("stamp"):
			check(n.stamp.size() == 1 and (n.stamp.values()[0] == null or n.stamp.values()[0] in ShiftState.EXITS), "%s: stamp names one colour and a real exit" % name)
			stamp_colours.append_array(n.stamp.keys())
		if n.has("swap"):
			check(n.swap.size() == 2 and n.swap[0] != n.swap[1] and n.swap[0] in ShiftState.EXITS and n.swap[1] in ShiftState.EXITS, "%s: swap names two different exits" % name)
	for kind in kinds:
		check(Tray.FOOD.has(kind), "tray art exists for %s" % kind)
	for colour in stamp_colours:
		check(Tray.STAMPS.has(colour), "stamp art exists for %s" % colour)
	for kind in cfg.routes:
		check(cfg.routes[kind] in ShiftState.EXITS, "starting rule for %s names a real exit" % kind)
	check(cfg.stamp_chance > 0.0 and cfg.stamp_chance < 0.5, "stamps are the exception, not the rule")
	check(cfg.swing_seconds < ShiftState.BOTH_SHIFT_WINDOW, "the gate swing is shorter than the both-Shifts window")
