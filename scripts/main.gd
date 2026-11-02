extends Node2D
## Scene glue: game state machine, Shift input, spawning and moving trays, HUD.
## The rules themselves live in ShiftState (scripts/shift_state.gd).

enum State { MENU, PLAYING, HOUR_END, GAME_OVER, WIN }

const TRAY := preload("res://scenes/tray.tscn")
const ROUTE_NAMES := {"left": "LEFT", "center": "STRAIGHT", "right": "RIGHT"}
const RESULT_SOUNDS := {"ok": "ding", "wrong": "strike_buzz", "missed": "missed"}

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state := State.MENU
var logic := ShiftState.new(cfg)

@onready var belt: Belt = $Belt
@onready var trays: Node2D = $Trays
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hour_timer: Timer = $HourTimer
@onready var stats: Label = $HUD/Stats
@onready var rules: Label = $HUD/Rules
@onready var note_card: ColorRect = $HUD/NoteCard
@onready var dim: ColorRect = $HUD/Dim
@onready var message: Label = $HUD/Dim/Message


func _ready() -> void:
	$Fork.position = Belt.FORK + Vector2(0, -25)
	$Fork.area_entered.connect(_on_tray_at_fork)
	spawn_timer.timeout.connect(_spawn)
	hour_timer.timeout.connect(_on_hour_over)
	_enter(State.MENU)


# --- state machine ---------------------------------------------------------

func _enter(new_state: State) -> void:
	state = new_state
	if state != State.PLAYING:
		spawn_timer.stop()
		hour_timer.stop()
		note_card.hide()
	match state:
		State.MENU:
			logic = ShiftState.new(cfg)
			_clear_trays()
			_show("CLUCK SHIFT\n\nNight shift on the packing line, 10 PM to 6 AM.\nSet the gate before each tray touches the red line.\n"
				+ "The supervisor changes one rule every hour.\n\n"
				+ "LEFT SHIFT  -  open / close the left gate\nRIGHT SHIFT  -  open / close the right gate\n"
				+ "BOTH SHIFTS  -  emergency stop (%d per night)\n\nPress Enter to clock in" % logic.estops_left)
		State.PLAYING:
			_start_hour()
		State.HOUR_END:
			_clear_trays()
			var t := logic.end_hour()
			Sfx.play("hour_end")
			_show("%s - %s DONE\n\nTrays sorted: %d\nCorrect: %d\nStrikes: %d\nPay this hour: $%d\nClean hour bonus: $%d\n\nNight total: $%d\n\nPress Enter to %s"
				% [t.from, t.to, t.sorted, t.ok, t.strikes, t.pay, t.bonus, t.total,
				"clock off" if logic.is_last_hour() else "start the next hour"])
		State.GAME_OVER:
			_show("SENT HOME at %s!\n\nPay: $%d\nTrays sorted: %d\nAccuracy: %d%%\nBest combo: %d\n\nPress Enter"
				% [logic.clock_text(), logic.pay, logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo])
		State.WIN:
			Sfx.play("clock_in")
			_show("6 AM. YOU MADE IT!\n\nTotal pay: $%d\nTrays sorted: %d\nAccuracy: %d%%\nBest combo: %d\n\nPress Enter"
				% [logic.pay, logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo])
	_refresh_rules()
	_update_hud()


func _start_hour() -> void:
	_clear_trays()
	logic.start_hour()
	_show("")
	note_card.get_node("Text").text = "SUPERVISOR NOTE - %s\n\n%s" % [ShiftState.hour_name(logic.hour), logic.note.get("text", "")]
	note_card.show()
	spawn_timer.paused = false
	hour_timer.paused = false
	hour_timer.start(cfg.hour_seconds)
	spawn_timer.start(cfg.note_seconds)  # first tray once the note has been read
	Sfx.play("clock_in")


func _on_hour_over() -> void:
	if state == State.PLAYING:
		_enter(State.HOUR_END)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if state != State.PLAYING:
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			match state:
				State.MENU:
					_enter(State.PLAYING)
				State.HOUR_END:
					_enter(State.WIN if logic.is_last_hour() else State.PLAYING)
				State.GAME_OVER, State.WIN:
					_enter(State.MENU)
		return
	if key.keycode != KEY_SHIFT:
		return
	var result := logic.press_shift("left" if key.location == KEY_LOCATION_LEFT else "right")
	Sfx.play({"toggle": "gate_click", "estop": "estop", "denied": "strike_buzz"}[result])
	_update_hud()


# --- belt ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	var step := logic.tick(delta)
	spawn_timer.paused = logic.is_stopped()
	hour_timer.paused = logic.is_stopped()
	note_card.visible = logic.hour_elapsed < cfg.note_seconds
	belt.scroll += step
	for t: Tray in trays.get_children():
		if not t.is_queued_for_deletion() and t.advance(step) and t.routed:
			if not t.falling:
				Sfx.play("tray_thunk")
			t.queue_free()
	_update_hud()


func _spawn() -> void:
	var spec := logic.next_tray()
	var t: Tray = TRAY.instantiate()
	t.kind = spec.kind
	t.stamp = spec.stamp
	t.position = Belt.SPAWN
	t.path = [Belt.FORK]
	trays.add_child(t)
	spawn_timer.start(logic.interval)


func _on_tray_at_fork(area: Area2D) -> void:
	var t := area as Tray
	if state != State.PLAYING or t == null or t.routed:
		return
	t.routed = true
	var result := logic.sort(t.kind, t.stamp)
	t.falling = result == "missed"
	t.path.append(Belt.FLOOR if t.falling else Belt.EXITS[logic.route])
	t.result = 1 if result == "ok" else -1
	t.queue_redraw()
	Sfx.play(RESULT_SOUNDS[result])
	if logic.sent_home():
		_enter(State.GAME_OVER)


func _clear_trays() -> void:
	for t in trays.get_children():
		t.queue_free()


# --- HUD -------------------------------------------------------------------

func _show(text: String) -> void:
	message.text = text
	dim.visible = text != ""


## Rebuilds the rules board and the bin labels from the current rules.
func _refresh_rules() -> void:
	var lines := PackedStringArray(["SUPERVISOR SAYS:"])
	var bins := {"left": [], "center": [], "right": []}
	for s: String in logic.stamps:
		lines.append("%s%s STAMP -> %s" % ["* " if s in logic.changed else "", s.to_upper(), ROUTE_NAMES[logic.stamps[s]]])
		bins[logic.stamps[s]].append(s.to_upper() + " STAMP")
	for kind: String in logic.routes:
		lines.append("%s%s -> %s" % ["* " if kind in logic.changed else "", kind.to_upper(), ROUTE_NAMES[logic.routes[kind]]])
		bins[logic.routes[kind]].append(kind.to_upper() + "S")
	for key: String in logic.changed:  # a rule this hour's note removed
		if not logic.stamps.has(key) and not logic.routes.has(key):
			lines.append("* %s STAMP: cancelled" % key.to_upper())
	if not logic.stamps.is_empty():
		lines.append("(a stamp beats the chicken)")
	if not logic.changed.is_empty():
		lines.append("* new this hour")
	rules.text = "\n".join(lines)
	belt.labels = bins


func _update_hud() -> void:
	var allowed := int(cfg.strikes_allowed)
	stats.text = "%s   HOUR %d/%d\nPAY  $%d\nCOMBO  %d   (x%d pay)\nSTRIKES  %s\nE-STOPS  %d\nBELT  %.1fx%s" % [
		logic.clock_text(), maxi(logic.hour + 1, 1), cfg.hours.size(),
		logic.pay, logic.combo, logic.multiplier(),
		"X ".repeat(logic.strikes) + "_ ".repeat(maxi(allowed - logic.strikes, 0)),
		logic.estops_left, logic.speed / cfg.hours[0].speed[0],
		"    STOPPED!" if logic.is_stopped() else ""]
	belt.route = logic.route
	belt.swinging = logic.is_swinging()
	belt.queue_redraw()
