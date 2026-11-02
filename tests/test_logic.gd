extends SceneTree
## Sanity tests for the rules (ShiftState), the tray path and data/rules.json.
## Run: godot --headless -s tests/test_logic.gd     (exit code 0 = all passed)

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var failures := 0


func _initialize() -> void:
	test_gates()
	test_emergency_stop()
	test_scoring_and_combo()
	test_strikes()
	test_belt_ramp()
	test_tray_path()
	test_rules_data()
	print("\n%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func test_gates() -> void:
	var s := ShiftState.new(cfg)
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


func test_emergency_stop() -> void:
	var s := ShiftState.new(cfg)
	s.press_shift("right")
	s.tick(1.0)
	s.press_shift("left")
	s.tick(ShiftState.BOTH_SHIFT_WINDOW / 2)
	check(s.press_shift("right") == "estop", "both Shifts within the window = emergency stop")
	check(s.route == "right", "emergency stop leaves the gate as it was before the pair")
	check(s.estops_left == int(cfg.estops) - 1, "emergency stop uses one charge")
	var speed := s.speed
	check(s.tick(0.1) == 0.0 and s.is_stopped(), "belt does not move while stopped")
	check(s.speed == speed, "belt does not speed up while stopped")
	s.press_shift("left")
	check(s.route == "left", "gates still work during the stop")
	s.tick(0.2)
	s.press_shift("left")
	s.press_shift("right")
	check(s.estops_left == int(cfg.estops) - 1, "a second stop during a stop is refused")
	s.tick(cfg.estop_seconds)
	check(not s.is_stopped() and s.tick(0.1) > 0.0, "belt restarts after estop_seconds")

	var t := ShiftState.new(cfg)
	for i in int(cfg.estops):
		t.press_shift("left")
		t.press_shift("right")
		t.tick(cfg.estop_seconds + 1.0)
	check(t.estops_left == 0, "all emergency stops used")
	t.press_shift("left")
	check(t.press_shift("right") == "denied" and t.route == "center", "no stops left: refused, gate unchanged")

	var u := ShiftState.new(cfg)
	u.press_shift("left")
	u.tick(ShiftState.BOTH_SHIFT_WINDOW + 0.05)
	check(u.press_shift("right") == "toggle", "Shifts further apart than the window are two toggles")


func test_scoring_and_combo() -> void:
	var s := ShiftState.new(cfg)
	var pay := int(cfg.pay_per_tray)
	s.press_shift("left")  # wings go left
	check(s.sort("wing") and s.pay == pay and s.combo == 1, "correct sort pays pay_per_tray and starts a combo")
	for i in 3:
		s.sort("wing")
	check(s.multiplier() == 1 and s.pay == 4 * pay, "x1 for the first 4 in a row")
	s.sort("wing")
	check(s.multiplier() == 2 and s.pay == 4 * pay + 2 * pay, "5th in a row pays x2")
	check(not s.sort("nugget") and s.combo == 0 and s.strikes == 1, "wrong sort: strike, combo resets")
	check(s.best_combo == 5, "best combo remembered")
	check(s.pay == 6 * pay, "a strike costs no pay")
	check(is_equal_approx(s.accuracy(), 5.0 / 6.0), "accuracy = correct / sorted")
	for i in 100:
		s.sort("wing")
	check(s.multiplier() == ShiftState.MAX_MULTIPLIER, "multiplier is capped")
	check(ShiftState.new(cfg).accuracy() == 0.0, "accuracy with nothing sorted is 0, not a crash")


func test_strikes() -> void:
	var s := ShiftState.new(cfg)  # gate straight: wings are wrong
	for i in int(cfg.strikes_allowed) - 1:
		s.sort("wing")
	check(not s.sent_home(), "one strike short: still working")
	s.sort("wing")
	check(s.sent_home(), "strikes_allowed strikes: sent home")


func test_belt_ramp() -> void:
	var s := ShiftState.new(cfg)
	var b: Dictionary = cfg.belt
	check(s.speed == b.start_speed and s.interval == b.start_interval, "belt starts at start_speed / start_interval")
	s.tick(10.0)
	check(s.speed > b.start_speed and s.interval < b.start_interval, "belt speeds up and trays come faster")
	s.tick(10000.0)
	check(s.speed == b.max_speed and s.interval == b.min_interval, "ramp stops at max_speed / min_interval")


func test_tray_path() -> void:
	var t := Tray.new()
	t.position = Vector2(0, 0)
	t.path = [Vector2(0, 100), Vector2(100, 100)]
	check(not t.advance(50.0) and t.position == Vector2(0, 50), "tray moves along the first leg")
	check(not t.advance(100.0) and t.position == Vector2(50, 100), "tray turns the corner without losing distance")
	check(t.advance(500.0) and t.position == Vector2(100, 100), "tray stops at the end and reports done")
	t.free()


func test_rules_data() -> void:
	var b: Dictionary = cfg.belt
	for kind: String in cfg.routes:
		check(cfg.routes[kind] in ["left", "center", "right"], "rule for %s names a real exit" % kind)
		check(Tray.FOOD.has(kind), "tray art exists for %s" % kind)
	# trays are 36 px tall; the gap between them is speed * interval at spawn time
	check(b.start_speed * b.start_interval > 100 and b.max_speed * b.min_interval > 100, "trays never overlap on the belt")
	# time between trays reaching the red line = interval; keep it humanly possible
	check(b.min_interval >= 0.6, "at full speed there is at least 0.6 s per tray")
	check(b.max_speed >= b.start_speed and b.min_interval <= b.start_interval, "ramp goes the right way")
