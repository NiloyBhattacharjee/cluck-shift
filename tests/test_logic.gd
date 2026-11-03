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
	test_shop()
	test_items()
	test_pa()
	test_strange_trays()
	test_radio_and_flicker()
	test_endings()
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


func test_shop() -> void:
	var s := night()
	check(s.wallet() == 0 and not s.buy("coffee"), "can't buy with an empty wallet")
	check(s.spent == 0 and not s.coffee, "a refused purchase changes nothing")
	s.pay = 1000
	check(s.buy("coffee") and s.spent == s.shop_item("coffee").price, "buying takes the price off the wallet")
	check(s.wallet() == 1000 - s.spent and s.pay == 1000, "spending lowers the wallet, not what you earned")
	check(not s.buy("pizza"), "unknown items can't be bought")
	s.pay = s.spent + s.shop_item("mate").price - 1
	check(not s.buy("mate"), "one dollar short is still too short")


func test_items() -> void:
	var s := night()
	s.pay = 10000
	s.end_hour()
	s.buy("coffee")
	s.start_hour()
	var h: Dictionary = cfg.hours[1]
	check(is_equal_approx(s.speed, h.speed[0] * cfg.coffee_factor), "coffee: the belt runs slower all hour")
	check(is_equal_approx(s.interval, h.interval[0] / cfg.coffee_factor), "coffee: trays come less often")
	check(is_equal_approx(s.speed * s.interval, h.speed[0] * h.interval[0]), "coffee keeps the gap between trays the same")
	s.end_hour()
	s.start_hour()
	check(s.speed == cfg.hours[2].speed[0], "coffee lasts one hour")

	s.buy("mate")
	s.route = "right"
	check(s.sort("wing") == "covered" and s.strikes == 0 and s.mates == 0, "your mate covers a wrong tray: no strike")
	check(s.combo == 0 and s.hour_ok == 0, "a covered tray still breaks the combo and doesn't pay")
	check(s.sort("wing") == "wrong" and s.strikes == 1, "the mate only covers one")
	s.buy("mate")
	s.end_hour()
	s.start_hour()
	check(s.mates == 1, "Mate's Help lasts until used, across hours")
	s.press_shift("left")
	check(s.sort("wing") == "covered" and s.last_missed, "the mate covers a missed tray too, and it still falls")


func test_pa() -> void:
	var s := night()
	_play_hour(s)
	check(s.pa_count == 0, "no PA before pa.from_hour")
	while s.hour < int(cfg.pa.from_hour):
		s.start_hour()
	var first: float = cfg.note_seconds + cfg.pa.every[1] + 0.1
	for i in int(first * 10):
		s.tick(0.1)
	check(s.pa_count >= 1 and s.pa_line in cfg.pa.lines, "from pa.from_hour the PA interrupts within %.1f s" % first)
	var count := s.pa_count
	_play_hour(s)
	check(s.pa_count >= count + int((cfg.hour_seconds - first) / cfg.pa.every[1]), "and keeps interrupting every few seconds (%d this hour)" % s.pa_count)
	check(s.pa_left <= cfg.pa.seconds, "an announcement lasts pa.seconds")
	s.pay = 1000
	s.end_hour()
	s.buy("earplugs")
	s.start_hour()
	var with_plugs := s.pa_count
	_play_hour(s)
	check(s.pa_count == with_plugs and s.pa_left == 0.0, "earplugs: no PA all hour")
	s.end_hour()
	s.start_hour()
	_play_hour(s)
	check(s.pa_count > with_plugs, "earplugs last one hour")


## A night that has clocked in to strange.from_hour (2 AM).
func strange_night() -> ShiftState:
	var s := night()
	while not s.is_strange_hour():
		s.start_hour()
	return s


func test_strange_trays() -> void:
	var s := night()
	var early := 0
	while not s.is_strange_hour():
		for i in 1000:
			early += int(s.next_tray().kind == ShiftState.STRANGE)
		s.start_hour()
	check(early == 0 and s.hour == int(cfg.strange.from_hour), "no strange trays before strange.from_hour (%s)" % ShiftState.hour_name(s.hour))
	var strange := 0
	for i in 1000:
		strange += int(s.next_tray().kind == ShiftState.STRANGE)
	check(strange == int(cfg.strange.max_per_hour), "at most strange.max_per_hour strange trays an hour (%d)" % strange)
	s.start_hour()
	var first_at := -1
	for i in 1000:
		if s.next_tray().kind == ShiftState.STRANGE and first_at < 0:
			first_at = i
	check(s.hour_strange == int(cfg.strange.max_per_hour) and first_at >= 0, "the count resets every hour (first one after %d trays)" % first_at)

	s = strange_night()
	s.combo = 7
	var before := [s.pay, s.sorted_total, s.sorted_ok, s.hour_sorted]
	check(s.sort(ShiftState.STRANGE) == "escaped" and s.escaped == 1 and s.strange_seen == 1, "a strange tray sent straight on escapes to the dock")
	check([s.pay, s.sorted_total, s.sorted_ok, s.hour_sorted] == before and s.combo == 7, "escaping pays nothing and doesn't count as sorting; the combo is untouched")
	s.press_shift("left")
	s.tick(cfg.swing_seconds + 0.01)
	check(s.sort(ShiftState.STRANGE) == "caught" and s.strikes == 0 and s.combo == 7, "a strange tray sent left is caught: no strike, combo untouched")
	s.mates = 1
	s.press_shift("left")  # back to straight on, but the gate is still swinging at the red line
	check(s.sort(ShiftState.STRANGE) == "caught" and s.last_missed and s.mates == 1, "a strange tray that misses the gate is caught too, and the mate isn't used")
	check(s.strange_seen == 3 and s.escaped == 1 and s.accuracy() == 0.0, "3 seen, 1 escaped, and accuracy ignores them")


func test_radio_and_flicker() -> void:
	var s := night()
	var dark := 0
	for i in int(cfg.hour_seconds * 10):
		s.tick(0.1)
		dark += int(s.lights_out())
	check(dark == 0, "the lights hold steady before strange.from_hour")
	s = strange_night()
	var f: Dictionary = cfg.strange.flicker
	var dark_share := 0.0
	for w: Array in f.dark:
		dark_share += (w[1] - w[0]) / f.every
	var steps := int(f.every * 100)
	dark = 0
	var radio := 0
	var normal := 0
	for i in steps:
		s.tick(0.01)
		dark += int(s.lights_out())
	check(absf(dark / float(steps) - dark_share) < 0.02, "from 2 AM the lights are out %.0f%% of the time (%d of %d steps)" % [dark_share * 100, dark, steps])
	s.stop_left = 1.0
	var t0 := s.clock
	var flickered := false
	while s.clock - t0 < f.every:
		s.tick(0.01)
		flickered = flickered or s.lights_out()
	check(flickered, "the lights flicker through an emergency stop too")
	var start := s.pa_count
	var seen := start
	for hour in 2:  # 2 AM and 3 AM; 4 AM gets earplugs below
		for i in int(cfg.hour_seconds * 10):
			s.tick(0.1)
			if s.pa_count != seen:
				seen = s.pa_count
				radio += int(s.pa_radio and s.pa_line in cfg.strange.radio)
				normal += int(not s.pa_radio and s.pa_line in cfg.pa.lines)
		s.start_hour()
	check(radio > 0 and normal > 0 and radio + normal == s.pa_count - start, "from 2 AM the PA sometimes picks up clucking on the radio (%d radio, %d PA)" % [radio, normal])
	s.pay = 1000
	s.end_hour()
	s.buy("earplugs")
	s.start_hour()
	var with_plugs := s.pa_count
	_play_hour(s)
	check(s.pa_count == with_plugs, "earplugs mute the radio clucks too")


func test_endings() -> void:
	var s := strange_night()
	check(s.ending() == "normal", "no strange trays seen: the normal ending")
	s.sort(ShiftState.STRANGE)
	s.sort(ShiftState.STRANGE)
	check(s.ending() == "secret", "every strange tray sent straight on: the secret ending")
	s.press_shift("right")
	s.tick(cfg.swing_seconds + 0.01)
	s.sort(ShiftState.STRANGE)
	check(s.ending() == "normal", "one strange tray caught: back to the normal ending")


## Ticks a whole hour in 0.1 s steps (PA timing included).
func _play_hour(s: ShiftState) -> void:
	for i in int(cfg.hour_seconds * 10):
		s.tick(0.1)


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
	var ids := []
	for item: Dictionary in cfg.shop:
		check(item.has("name") and item.has("text") and item.price > 0, "shop item %s has a name, a description and a price" % item.id)
		ids.append(item.id)
	ids.sort()
	check(ids == ["coffee", "earplugs", "mate"], "the shop sells exactly the three items the rules know")
	check(cfg.coffee_factor > 0.5 and cfg.coffee_factor < 1.0, "coffee slows the belt, but not to a crawl")
	check(cfg.pa.from_hour > 0 and cfg.pa.from_hour < cfg.hours.size(), "the PA starts partway through the night")
	check(cfg.pa.every[0] > cfg.pa.seconds and cfg.pa.every[1] >= cfg.pa.every[0], "announcements never overlap")
	check(cfg.pa.lines.size() >= 4, "enough PA lines not to repeat constantly")
	var st: Dictionary = cfg.strange
	check(st.from_hour >= cfg.pa.from_hour and st.from_hour < cfg.hours.size(), "the strange night starts after the PA does (so the radio has a PA to cut into)")
	check(st.chance > 0.0 and st.chance <= 0.1 and st.max_per_hour >= 1, "strange trays are rare, but there is at least one an hour")
	check(st.radio_chance > 0.0 and st.radio_chance < 1.0 and st.radio.size() >= 3, "radio clucks mix with normal announcements")
	check(st.radio.any(func(l): return "STRAIGHT" in l) and st.radio.any(func(l): return "DOCK" in l), "the radio hints at straight on and the dock")
	var dark := 0.0
	for w: Array in st.flicker.dark:
		check(w[0] < w[1] and w[0] >= 0.0 and w[1] <= st.flicker.every, "flicker window %s fits in the cycle" % [w])
		dark += w[1] - w[0]
	check(dark / st.flicker.every < 0.25, "the lights are on most of the time (%.0f%% dark)" % (dark / st.flicker.every * 100))
	for w: Array in st.flicker.dark:  # photosensitivity: WCAG 2.3.1 allows at most 3 flashes in any second
		var flashes: int = st.flicker.dark.filter(func(o): return o[0] >= w[0] and o[0] < w[0] + 1.0).size()
		check(flashes <= 2, "at most 2 flashes in the second from %.2f s (%d)" % [w[0], flashes])
	check(Tray.FOOD.has(ShiftState.STRANGE) and not cfg.routes.has(ShiftState.STRANGE), "strange trays have art and no rule")
	for which in ["normal", "secret"]:
		check(cfg.endings.has(which) and cfg.endings[which].title != "" and cfg.endings[which].text != "", "the %s ending has a title and text" % which)
