extends SceneTree
## Plays the real main scene headless, through real key events and the real Fork Area2D.
## 1) An autoplayer that sets the right gate sorts for 150 s with no strikes, using one emergency stop.
## 2) A player who never touches the keys is sent home, the belt freezes, and Enter starts a clean shift.
## Run: godot --headless --fixed-fps 60 -s tests/test_play.gd     (exit code 0 = all passed)

const LIMIT := 240 * 60  # hard stop: a broken run fails instead of hanging
const FPS := 60

var Main: Script  # loaded after autoloads exist, so main.gd can see Sfx
var main: Node
var total := 0
var frame := 0
var phase := "auto"
var last_press := -100
var frozen := {}
var failures := 0


func _initialize() -> void:
	Main = load("res://scripts/main.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(_delta: float) -> bool:
	frame += 1
	total += 1
	if total > LIMIT:
		check(false, "test finished before the frame limit")
		_finish()
	if phase == "auto":
		_auto_phase()
	else:
		_idle_phase()
	return false


func _auto_phase() -> void:
	if frame == 2:
		check(main.state == Main.State.MENU, "game opens on the menu")
		_key(KEY_ENTER)
	elif frame == 4:
		check(main.state == Main.State.PLAYING, "Enter clocks in")
	elif frame == 5 * FPS:
		frozen = _positions()
		_key(KEY_SHIFT, KEY_LOCATION_LEFT)
		_key(KEY_SHIFT, KEY_LOCATION_RIGHT)
		last_press = frame
	elif frame == 5 * FPS + 30:
		check(main.logic.is_stopped(), "both Shifts stop the belt")
		check(_positions() == frozen, "trays do not move during the stop")
		check(main.spawn_timer.paused, "no new trays during the stop")
	elif frame > 4 and frame < 150 * FPS and not (frame > 5 * FPS - 20 and frame < 5 * FPS):
		_autoplay()  # paused just before the emergency stop so its presses can't pair with the stop's
	elif frame == 150 * FPS:
		var s: ShiftState = main.logic
		print("autoplayer: sorted %d, pay $%d, best combo %d" % [s.sorted_total, s.pay, s.best_combo])
		check(s.strikes == 0, "perfect player gets no strikes")
		check(s.sorted_total >= 60, "trays keep coming (%d sorted)" % s.sorted_total)
		check(s.speed == main.cfg.belt.max_speed, "belt reached top speed")
		check(s.estops_left == int(main.cfg.estops) - 1, "exactly one emergency stop used")
		check(main.state == Main.State.PLAYING, "still on shift")
		main._enter(Main.State.PLAYING)  # fresh shift for the idle test
		frozen = {}
		phase = "idle"
		frame = 0


func _idle_phase() -> void:
	if frozen.is_empty():
		if main.state == Main.State.GAME_OVER:
			check(main.logic.strikes == int(main.cfg.strikes_allowed), "idle player is sent home on the last strike")
			check(main.dim.visible and main.message.text.begins_with("SENT HOME"), "game over screen shows")
			frozen = _positions()
			frame = 0
		elif frame > 60 * FPS:
			check(false, "idle player should have been sent home within 60 s")
			_finish()
	elif frame == 60:
		check(_positions() == frozen, "belt is frozen after game over")
		_key(KEY_SHIFT, KEY_LOCATION_LEFT)
	elif frame == 62:
		check(main.logic.route == "center", "Shift does nothing after game over")
		_key(KEY_ENTER)
	elif frame == 66:
		var s: ShiftState = main.logic
		check(main.state == Main.State.PLAYING, "Enter starts a new shift")
		check(s.strikes == 0 and s.pay == 0 and s.estops_left == int(main.cfg.estops), "new shift starts clean")
		check(main.trays.get_child_count() == 1, "old trays cleared, first new tray spawned")
		_finish()


## Presses the Shift that sends the front unrouted tray to its exit, at most every 0.25 s.
func _autoplay() -> void:
	if frame - last_press < 15:
		return
	var front: Tray = null
	for t: Tray in main.trays.get_children():
		if not t.routed and (front == null or t.position.y > front.position.y):
			front = t
	if front == null:
		return
	var want: String = main.cfg.routes[front.kind]
	var have: String = main.logic.route
	if want != have:
		var side := want if want != "center" else have
		_key(KEY_SHIFT, KEY_LOCATION_LEFT if side == "left" else KEY_LOCATION_RIGHT)
		last_press = frame


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
