extends Node2D
## Scene glue: game state machine, Shift input, spawning and moving trays, HUD.
## The rules themselves live in ShiftState (scripts/shift_state.gd).

enum State { MENU, PLAYING, GAME_OVER }

const TRAY := preload("res://scenes/tray.tscn")
const ROUTE_NAMES := {"left": "LEFT", "center": "STRAIGHT", "right": "RIGHT"}

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state := State.MENU
var logic := ShiftState.new(cfg)

@onready var belt: Belt = $Belt
@onready var trays: Node2D = $Trays
@onready var spawn_timer: Timer = $SpawnTimer
@onready var stats: Label = $HUD/Stats
@onready var dim: ColorRect = $HUD/Dim
@onready var message: Label = $HUD/Dim/Message


func _ready() -> void:
	$Fork.position = Belt.FORK + Vector2(0, -25)
	$Fork.area_entered.connect(_on_tray_at_fork)
	spawn_timer.timeout.connect(_spawn)
	var lines := PackedStringArray(["SUPERVISOR SAYS:"])
	for kind: String in cfg.routes:
		var r: String = cfg.routes[kind]
		lines.append("%s  ->  %s" % [kind.to_upper(), ROUTE_NAMES[r]])
		belt.labels[r] = (belt.labels.get(r, "") + " " + kind.to_upper() + "S").strip_edges()
	$HUD/Rules.text = "\n".join(lines)
	_enter(State.MENU)


func _enter(new_state: State) -> void:
	state = new_state
	match state:
		State.MENU:
			_show("CLUCK SHIFT\n\nNight shift on the packing line.\nSet the gate before each tray touches the red line.\n\n"
				+ "LEFT SHIFT  -  open / close the left gate\nRIGHT SHIFT  -  open / close the right gate\n"
				+ "BOTH SHIFTS  -  emergency stop (%d per night)\n\nPress Enter to clock in" % logic.estops_left)
		State.PLAYING:
			for t in trays.get_children():
				t.queue_free()
			logic = ShiftState.new(cfg)
			spawn_timer.paused = false
			_show("")
			_spawn()
		State.GAME_OVER:
			spawn_timer.stop()
			_show("SENT HOME!\n\nPay: $%d\nTrays sorted: %d\nAccuracy: %d%%\nBest combo: %d\n\nPress Enter to clock in again"
				% [logic.pay, logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo])
	_update_hud()


func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	var step := logic.tick(delta)
	spawn_timer.paused = logic.is_stopped()
	belt.scroll += step
	for t: Tray in trays.get_children():
		if not t.is_queued_for_deletion() and t.advance(step) and t.routed:
			Sfx.play("tray_thunk")
			t.queue_free()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if state != State.PLAYING:
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_enter(State.PLAYING)
		return
	if key.keycode != KEY_SHIFT:
		return
	var result := logic.press_shift("left" if key.location == KEY_LOCATION_LEFT else "right")
	Sfx.play({"toggle": "gate_click", "estop": "estop", "denied": "strike_buzz"}[result])
	_update_hud()


func _spawn() -> void:
	var t: Tray = TRAY.instantiate()
	t.kind = cfg.routes.keys().pick_random()
	t.position = Belt.SPAWN
	t.path = [Belt.FORK]
	trays.add_child(t)
	spawn_timer.start(logic.interval)


func _on_tray_at_fork(area: Area2D) -> void:
	var t := area as Tray
	if state != State.PLAYING or t == null or t.routed:
		return
	t.routed = true
	t.path.append(Belt.EXITS[logic.route])
	var ok := logic.sort(t.kind)
	t.result = 1 if ok else -1
	t.queue_redraw()
	Sfx.play("ding" if ok else "strike_buzz")
	if logic.sent_home():
		_enter(State.GAME_OVER)


func _show(text: String) -> void:
	message.text = text
	dim.visible = text != ""


func _update_hud() -> void:
	var allowed := int(cfg.strikes_allowed)
	stats.text = "PAY  $%d\nCOMBO  %d   (x%d pay)\nSTRIKES  %s\nE-STOPS  %d\nBELT  %.1fx%s" % [
		logic.pay, logic.combo, logic.multiplier(),
		"X ".repeat(logic.strikes) + "_ ".repeat(maxi(allowed - logic.strikes, 0)),
		logic.estops_left, logic.speed / cfg.belt.start_speed,
		"    STOPPED!" if logic.is_stopped() else ""]
	belt.route = logic.route
	belt.queue_redraw()
