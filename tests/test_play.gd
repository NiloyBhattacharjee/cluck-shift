extends SceneTree
## Plays the real main scene headless, through real key events, the real Timers and the real Fork Area2D.
## 1) Full night: an autoplayer sets the right gate for every tray from 10 PM to 6 AM, uses one
##    emergency stop, and must finish with no strikes and a clean-hour bonus every hour.
## 2) Idle night: a late Shift press makes a tray miss the gate; with no other presses the player
##    is sent home in the first hour, the belt freezes, and Enter goes back to the menu for a clean start.
## Run: godot --headless --fixed-fps 60 -s tests/test_play.gd     (exit code 0 = all passed)

const FPS := 60
const LIMIT := 12 * 80 * FPS  # hard stop: a broken run fails instead of hanging

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
				check(main.dim.visible and main.message.text.begins_with("CLUCK SHIFT"), "game opens on the menu")
				_key(KEY_ENTER)
		Main.State.PLAYING:
			_night_playing()
		Main.State.HOUR_END:
			if in_state == 2:
				hours_done += 1
				var bonus := "Clean hour bonus: $%d" % int(cfg.clean_hour_bonus)
				bonuses += int(bonus in main.message.text)
				check(main.trays.get_child_count() == 0 or main.trays.get_children().all(func(t): return t.is_queued_for_deletion()), "%s: belt cleared at the end of the hour" % ShiftState.hour_name(main.logic.hour))
				_key(KEY_ENTER)
		Main.State.WIN:
			if in_state == 2:
				var s: ShiftState = main.logic
				print("night: sorted %d, pay $%d, best combo %d" % [s.sorted_total, s.pay, s.best_combo])
				check(hours_done == cfg.hours.size(), "all %d hours played" % cfg.hours.size())
				check(s.sorted_ok == s.sorted_total and s.sorted_total > 200, "perfect player: %d of %d trays right, no strikes" % [s.sorted_ok, s.sorted_total])
				check(bonuses == cfg.hours.size(), "a clean-hour bonus every hour")
				check(main.message.text.begins_with("6 AM"), "the win screen shows at 6 AM")
				check(s.estops_left == int(cfg.estops) - 1, "exactly one emergency stop used")
				_key(KEY_ENTER)  # handled at once, so main is already on the menu
				check(main.state == Main.State.MENU, "Enter after the win goes back to the menu")
				phase = "idle"
		Main.State.GAME_OVER:
			check(false, "perfect player was sent home at %s" % main.logic.clock_text())
			_finish()


func _night_playing() -> void:
	var s: ShiftState = main.logic
	if in_state == 1:
		check(s.hour == hours_done, "%s: hour starts in order" % ShiftState.hour_name(s.hour))
		check(main.note_card.visible and s.note.text in main.note_card.get_node("Text").text, "%s: supervisor note shows" % ShiftState.hour_name(s.hour))
		check(s.strikes == 0 and s.route == "center", "%s: strikes reset, gates closed" % ShiftState.hour_name(s.hour))
		for key: String in s.changed:
			check(("* " + key.to_upper()) in main.rules.text, "%s: the board marks %s as new" % [ShiftState.hour_name(s.hour), key])
	if in_state == int(cfg.note_seconds * FPS) - 5 and s.hour == 0:
		check(main.trays.get_child_count() == 0, "no trays while the note is up")
	if in_state == int(cfg.note_seconds * FPS) + 5 and s.hour == 0:
		check(not main.note_card.visible, "the note goes away after note_seconds")
	if s.hour == 0 and not stop_checked:
		_check_emergency_stop()
		if not stop_checked:
			return
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
		check(main.logic.is_stopped(), "both Shifts stop the belt")
		check(now == frozen, "trays and the hour clock do not move during the stop")
		check(main.spawn_timer.paused and main.hour_timer.paused, "spawn and hour timers are paused")
		stop_checked = true
	elif in_state < at - 20 and in_state > 1:
		_autoplay()


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
				frozen = {}
			if in_state > cfg.hour_seconds * FPS:
				check(false, "idle player should have been sent home in the first hour")
				_finish()
		Main.State.GAME_OVER:
			if in_state == 1:
				check(s.strikes == int(cfg.strikes_allowed) and s.hour == 0, "idle player is sent home in the first hour")
				check(main.message.text.begins_with("SENT HOME at 10:"), "game over screen shows the time")
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
					check(main.state == Main.State.PLAYING, "Enter from the menu starts a new night")
					var n: ShiftState = main.logic
					check(n.hour == 0 and n.strikes == 0 and n.pay == 0 and n.estops_left == int(cfg.estops), "the new night starts clean at 10 PM")
					check(main.trays.get_children().all(func(t): return t.is_queued_for_deletion()), "old trays are cleared")
					_finish()


## Presses the Shift that sends the front unrouted tray to its exit, at most every 0.25 s.
func _autoplay() -> void:
	if total - last_press < 15:
		return
	var front: Tray = null
	for t: Tray in main.trays.get_children():
		if not t.routed and (front == null or t.position.y > front.position.y):
			front = t
	if front == null:
		return
	var want: String = main.logic.exit_for(front.kind, front.stamp)
	var have: String = main.logic.route
	if want != have:
		var side := want if want != "center" else have
		_key(KEY_SHIFT, KEY_LOCATION_LEFT if side == "left" else KEY_LOCATION_RIGHT)
		last_press = total


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
