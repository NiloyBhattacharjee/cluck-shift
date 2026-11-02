extends SceneTree
## Plays the real main scene headless, through real key events, the real Timers and the real Fork Area2D.
## 1) Full night: an autoplayer sets the right gate for every tray from 10 PM to 6 AM, uses one
##    emergency stop, buys Coffee, Mate's Help and Earplugs in the break room, makes one deliberate
##    mistake for the mate to cover, and must finish with no strikes and a clean-hour bonus every hour.
## 2) Idle night: a late Shift press makes a tray miss the gate; with no other presses the player
##    is sent home in the first hour, the belt freezes, and Enter goes back to the title for a clean start.
## Run: godot --headless --fixed-fps 60 -s tests/test_play.gd     (exit code 0 = all passed)

const FPS := 60
const LIMIT := 12 * 80 * FPS  # hard stop: a broken run fails instead of hanging
const SHOP_PLAN := {1: ["coffee", 1], 2: ["mate", 2], 3: ["earplugs", -1]}  # after hour n: item, Right(+)/Left(-) presses from Skip

var Main: Script  # loaded after autoloads exist, so main.gd can see Sfx
var main: Node
var cfg: Dictionary
var total := 0
var phase := "night"
var last_state := -1
var in_state := 0  # frames since main.state last changed
var last_press := -100
var frozen := {}
var hours_done := 0
var bonuses := 0
var stop_checked := false
var missed_checked := false
var puffs_seen := false
var pa_seen_by_hour := {}
var sabotage: Tray = null  # the tray sent wrong on purpose for the mate to cover
var failures := 0


func _initialize() -> void:
	Main = load("res://scripts/main.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cfg = main.cfg


func _physics_process(_delta: float) -> bool:
	total += 1
	if main.state != last_state:
		last_state = main.state
		in_state = 0
	in_state += 1
	if total > LIMIT:
		check(false, "test finished before the frame limit")
		_finish()
	elif phase == "night":
		_night()
	else:
		_idle()
	return false


# --- run 1: a full night with a perfect player ------------------------------

func _night() -> void:
	match main.state:
		Main.State.MENU:
			if in_state == 2:
				check(main.title.visible and not main.dim.visible and not main.shop.visible, "game opens on the title screen")
				check(not _hum(), "no factory hum on the title")
				_key(KEY_ENTER)
		Main.State.PLAYING:
			_night_playing()
		Main.State.HOUR_END:
			if in_state == 2:
				var name := ShiftState.hour_name(main.logic.hour)
				hours_done += 1
				bonuses += int(("Clean hour bonus: $%d" % int(cfg.clean_hour_bonus)) in main.message.text)
				check(main.trays.get_children().all(func(t): return t.is_queued_for_deletion()), "%s: belt cleared at the end of the hour" % name)
				check(not main.pa_banner.visible and not _hum(), "%s: PA banner and hum off on the tally" % name)
				if main.logic.hour == int(cfg.pa.from_hour):
					check(pa_seen_by_hour.get(main.logic.hour, false), "%s: the PA banner interrupted this hour" % name)
				if main.logic.hour == int(cfg.pa.from_hour) + 1:
					check(not pa_seen_by_hour.get(main.logic.hour, false), "%s: earplugs kept the PA quiet all hour" % name)
				_key(KEY_ENTER)
				if not main.logic.is_last_hour():
					check(main.state == Main.State.SHOP, "%s: Enter goes to the break room" % name)
		Main.State.SHOP:
			if in_state == 2:
				_shop()
		Main.State.WIN:
			if in_state == 2:
				var s: ShiftState = main.logic
				print("night: sorted %d, earned $%d, spent $%d, best combo %d" % [s.sorted_total, s.pay, s.spent, s.best_combo])
				check(hours_done == cfg.hours.size(), "all %d hours played" % cfg.hours.size())
				check(s.sorted_ok == s.sorted_total - 1 and s.sorted_total > 200, "every tray right except the one the mate covered (%d of %d)" % [s.sorted_ok, s.sorted_total])
				check(bonuses == cfg.hours.size(), "no strikes all night: a clean-hour bonus every hour")
				var spent := 0
				for item: Dictionary in cfg.shop:
					spent += int(item.price)
				check(s.spent == spent and s.wallet() == s.pay - spent, "bought all three items: $%d spent" % spent)
				check(main.message.text.begins_with("6 AM") and ("Take-home pay: $%d" % s.wallet()) in main.message.text, "the win screen shows earned, spent and take-home pay")
				check(s.estops_left == int(cfg.estops) - 1, "exactly one emergency stop used")
				_key(KEY_ENTER)  # handled at once, so main is already on the title
				check(main.state == Main.State.MENU and main.title.visible, "Enter after the win goes back to the title")
				phase = "idle"


func _night_playing() -> void:
	var s: ShiftState = main.logic
	var name := ShiftState.hour_name(s.hour)
	if in_state == 1:
		check(s.hour == hours_done, "%s: hour starts in order" % name)
		check(main.note_card.visible and s.note.text in main.note_card.get_node("Text").text, "%s: supervisor note shows" % name)
		check(s.strikes == 0 and s.route == "center", "%s: strikes reset, gates closed" % name)
		check(not main.title.visible and not main.shop.visible and not main.dim.visible, "%s: only the line is on screen" % name)
		for key: String in s.changed:
			check(("* " + key.to_upper()) in main.rules.text, "%s: the board marks %s as new" % [name, key])
		if s.hour == 1:
			check(s.coffee and absf(s.speed - cfg.hours[1].speed[0] * cfg.coffee_factor) < 1.0, "%s: coffee slows the belt (%.0f px/s)" % [name, s.speed])
		if s.hour == 2:
			check(s.mates == 1 and not s.coffee, "%s: the mate is standing by; the coffee wore off" % name)
		if s.hour == 3:
			check(s.earplugs, "%s: earplugs in" % name)
	if in_state == 10:
		check(_hum(), "%s: factory hum while working" % name)
	if main.pa_banner.visible:
		pa_seen_by_hour[s.hour] = true
	if s.hour == 0:
		if in_state == int(cfg.note_seconds * FPS) - 5:
			check(main.trays.get_child_count() == 0, "no trays while the note is up")
		if in_state == int(cfg.note_seconds * FPS) + 5:
			check(not main.note_card.visible, "the note goes away after note_seconds")
		if not puffs_seen and main.juice.get_children().any(func(n): return n is CPUParticles2D):
			puffs_seen = true
			check(true, "a puff of feathers when a tray lands in its bin")
			check(main.juice.get_children().any(func(n): return n is Label and n.text.begins_with("+$")), "a +$ popup for a correct tray")
		if not stop_checked:
			_check_emergency_stop()
			if not stop_checked:
				return
	if s.hour == 2 and s.mates == 1 and sabotage == null:
		_sabotage()
		return
	if sabotage != null and sabotage.routed and not frozen.has("covered"):
		frozen["covered"] = true
		check(s.mates == 0 and s.strikes == 0 and sabotage.result == -1, "a wrong tray with the mate standing by: covered, no strike")
		check(main.juice.get_children().any(func(n): return n is Label and n.text == "YOUR MATE COVERED IT!"), "the mate's popup shows")
		check(main.juice.trauma > 0.0, "and the screen shakes")
	_autoplay()


## At 6 s into the first hour press both Shifts, then check the belt, spawner and hour clock froze.
func _check_emergency_stop() -> void:
	var at := 6 * FPS
	if in_state == at:
		frozen = _positions()
		frozen["hour_left"] = main.hour_timer.time_left
		_key(KEY_SHIFT, KEY_LOCATION_LEFT)
		_key(KEY_SHIFT, KEY_LOCATION_RIGHT)
		last_press = total
	elif in_state == at + 30:
		var now := _positions()
		now["hour_left"] = main.hour_timer.time_left
		check(main.logic.is_stopped() and main.hazard.visible, "both Shifts stop the belt and flash the hazard light")
		check(now == frozen, "trays and the hour clock do not move during the stop")
		check(main.spawn_timer.paused and main.hour_timer.paused, "spawn and hour timers are paused")
		check(main.juice.get_children().any(func(n): return n is Label and n.text == "EMERGENCY STOP!"), "an EMERGENCY STOP popup")
		stop_checked = true
		frozen = {}
	elif in_state < at - 20 and in_state > 1:
		_autoplay()


## Sends the front tray to a wrong exit on purpose, once, for the mate to cover.
func _sabotage() -> void:
	var front := _front()
	if front == null or total - last_press < 15 or front.position.y > 150.0:
		return
	var want: String = main.logic.exit_for(front.kind, front.stamp)
	var wrong := "left" if want != "left" else "right"
	if main.logic.route != wrong:
		_key(KEY_SHIFT, KEY_LOCATION_LEFT if wrong == "left" else KEY_LOCATION_RIGHT)
		last_press = total
	sabotage = front


## The break room after hour n: check the screen, then follow SHOP_PLAN (or skip).
func _shop() -> void:
	var s: ShiftState = main.logic
	check(main.shop.visible and main.shop.selected == main.shop.items.size() - 1, "%s break: the shop opens on Skip" % ShiftState.hour_name(s.hour))
	check(main.shop.wallet == s.wallet(), "%s break: the shop shows your pay" % ShiftState.hour_name(s.hour))
	if hours_done == 1:  # can't-afford check: empty the wallet, try Coffee, then put it back
		var spent := s.spent
		s.spent = s.pay
		main.shop.selected = 0
		_key(KEY_ENTER)
		check(main.state == Main.State.SHOP and s.spent == s.pay and not s.coffee, "Enter on an item you can't afford: refused, still in the shop")
		s.spent = spent
		main.shop.selected = main.shop.items.size() - 1
	if SHOP_PLAN.has(hours_done):
		var plan: Array = SHOP_PLAN[hours_done]
		for i in absi(plan[1]):
			_key(KEY_SHIFT, KEY_LOCATION_RIGHT if plan[1] > 0 else KEY_LOCATION_LEFT)
		check(main.shop.items[main.shop.selected].id == plan[0], "Shifts move the selection to %s" % plan[0])
		var before := s.wallet()
		_key(KEY_ENTER)
		check(main.state == Main.State.PLAYING and s.wallet() == before - int(s.shop_item(plan[0]).price), "Enter buys %s and starts the next hour" % plan[0])
	else:
		var before := s.wallet()
		_key(KEY_ENTER)
		check(main.state == Main.State.PLAYING and s.wallet() == before, "Enter on Skip spends nothing")


# --- run 2: a player who does nothing (and one late press) ----------------

func _idle() -> void:
	var s: ShiftState = main.logic
	match main.state:
		Main.State.PLAYING:
			if not missed_checked:
				for t: Tray in main.trays.get_children():
					if not t.routed and t.position.y > 268.0:
						_key(KEY_SHIFT, KEY_LOCATION_LEFT)  # far too late: the gate is still swinging at the red line
						missed_checked = true
						frozen = {"tray": t}
			elif frozen.has("tray") and frozen.tray.routed:
				check(frozen.tray.falling and s.strikes == 1, "a press just before the red line: the tray misses the gate (strike)")
				check(main.juice.get_children().any(func(n): return n is Label and n.text == "MISSED!"), "a MISSED! popup")
				frozen = {}
			if in_state > cfg.hour_seconds * FPS:
				check(false, "idle player should have been sent home in the first hour")
				_finish()
		Main.State.GAME_OVER:
			if in_state == 1:
				check(s.strikes == int(cfg.strikes_allowed) and s.hour == 0, "idle player is sent home in the first hour")
				check(main.message.text.begins_with("SENT HOME at 10:"), "game over screen shows the time")
				check(main.juice.trauma > 0.5, "being sent home shakes the screen")
				frozen = _positions()
			elif in_state == 60:
				check(_positions() == frozen, "belt is frozen after game over")
				_key(KEY_SHIFT, KEY_LOCATION_RIGHT)
			elif in_state == 62:
				check(main.state == Main.State.GAME_OVER and s.route != "right", "Shift does nothing after game over")
				_key(KEY_ENTER)
		Main.State.MENU:
			if in_state == 2:
				var after_game_over := missed_checked
				_key(KEY_ENTER)  # handled at once
				if after_game_over:
					check(main.state == Main.State.PLAYING, "Enter from the title starts a new night")
					var n: ShiftState = main.logic
					check(n.hour == 0 and n.strikes == 0 and n.pay == 0 and n.spent == 0 and n.mates == 0 and n.estops_left == int(cfg.estops), "the new night starts clean at 10 PM")
					check(main.trays.get_children().all(func(t): return t.is_queued_for_deletion()), "old trays are cleared")
					_finish()


## Presses the Shift that sends the front unrouted tray to its exit, at most every 0.25 s.
func _autoplay() -> void:
	if total - last_press < 15:
		return
	var front := _front()
	if front == null or front == sabotage:
		return
	var want: String = main.logic.exit_for(front.kind, front.stamp)
	var have: String = main.logic.route
	if want != have:
		var side := want if want != "center" else have
		_key(KEY_SHIFT, KEY_LOCATION_LEFT if side == "left" else KEY_LOCATION_RIGHT)
		last_press = total


func _hum() -> bool:  # Sfx is an autoload; looked up at runtime because this script compiles before it exists
	return root.get_node("Sfx")._players.hum.playing


func _front() -> Tray:
	var front: Tray = null
	for t: Tray in main.trays.get_children():
		if not t.routed and not t.is_queued_for_deletion() and (front == null or t.position.y > front.position.y):
			front = t
	return front


func _positions() -> Dictionary:
	var out := {}
	for t in main.trays.get_children():
		out[t.get_instance_id()] = t.position
	return out


func _key(code: Key, location := KEY_LOCATION_UNSPECIFIED) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.location = location
	e.pressed = true
	root.push_input(e)


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _finish() -> void:
	print("\n%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
