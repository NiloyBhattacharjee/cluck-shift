extends Node2D
## Scene glue: game state machine, Shift input, spawning and moving trays, HUD, shop and juice.
## The rules themselves live in ShiftState (scripts/shift_state.gd).

enum State { MENU, PLAYING, HOUR_END, SHOP, GAME_OVER, WIN }

const TRAY := preload("res://scenes/tray.tscn")
const ROUTE_NAMES := {"left": "LEFT", "center": "STRAIGHT", "right": "RIGHT"}
const RESULT_SOUNDS := {"ok": "ding", "wrong": "strike_buzz", "missed": "missed", "covered": "select"}
const SKIP := {"id": "skip", "name": "Skip", "price": 0, "text": "Keep your pay. Straight back to the line."}
const POPUP_AT := Belt.FORK + Vector2(0, -70)

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state := State.MENU
var logic := ShiftState.new(cfg)
var _pa_seen := 0  # logic.pa_count when the banner last updated

@onready var belt: Belt = $Belt
@onready var trays: Node2D = $Trays
@onready var juice: Juice = $Juice
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hour_timer: Timer = $HourTimer
@onready var stats: Label = $HUD/Stats
@onready var rules: Label = $HUD/Rules
@onready var note_card: ColorRect = $HUD/NoteCard
@onready var pa_banner: ColorRect = $HUD/PABanner
@onready var hazard: ColorRect = $HUD/Hazard
@onready var dim: ColorRect = $HUD/Dim
@onready var message: Label = $HUD/Dim/Message
@onready var shop: Control = $HUD/Shop
@onready var title: Control = $HUD/Title


func _ready() -> void:
	$Fork.position = Belt.FORK + Vector2(0, -25)
	$Fork.area_entered.connect(_on_tray_at_fork)
	spawn_timer.timeout.connect(_spawn)
	hour_timer.timeout.connect(_on_hour_over)
	shop.items = cfg.shop + [SKIP]
	_enter(State.MENU)


# --- state machine ---------------------------------------------------------

func _enter(new_state: State) -> void:
	state = new_state
	if state != State.PLAYING:
		spawn_timer.stop()
		hour_timer.stop()
		note_card.hide()
		pa_banner.hide()
		hazard.hide()
	Sfx.loop("hum", state == State.PLAYING)
	title.visible = state == State.MENU
	shop.visible = state == State.SHOP
	_show("")
	match state:
		State.MENU:
			logic = ShiftState.new(cfg)
			_pa_seen = 0
			_clear_trays()
		State.PLAYING:
			_start_hour()
		State.HOUR_END:
			_clear_trays()
			var t := logic.end_hour()
			Sfx.play("hour_end")
			_show("%s - %s DONE\n\nTrays sorted: %d\nCorrect: %d\nStrikes: %d\nPay this hour: $%d\nClean hour bonus: $%d\n\nNight total: $%d\n\nPress Enter to %s"
				% [t.from, t.to, t.sorted, t.ok, t.strikes, t.pay, t.bonus, t.total,
				"clock off" if logic.is_last_hour() else "go to the break room"])
		State.SHOP:
			shop.selected = shop.items.size() - 1  # start on Skip, so Enter alone never spends
			_refresh_shop()
		State.GAME_OVER:
			juice.shake(1.0)
			_show("SENT HOME at %s!\n\nEarned: $%d    Spent: $%d\nTrays sorted: %d\nAccuracy: %d%%\nBest combo: %d\n\nPress Enter"
				% [logic.clock_text(), logic.pay, logic.spent, logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo])
		State.WIN:
			Sfx.play("clock_in")
			_show("6 AM. YOU MADE IT!\n\nEarned: $%d\nSpent in the break room: $%d\nTake-home pay: $%d\n\nTrays sorted: %d    Accuracy: %d%%    Best combo: %d\n\nPress Enter"
				% [logic.pay, logic.spent, logic.wallet(), logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo])
	_refresh_rules()
	_update_hud()


func _start_hour() -> void:
	_clear_trays()
	logic.start_hour()
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
	var side := "left" if key.location == KEY_LOCATION_LEFT else "right"
	if state == State.PLAYING:
		if key.keycode == KEY_SHIFT:
			_on_shift(side)
		return
	if state == State.SHOP and key.keycode == KEY_SHIFT:
		shop.selected = wrapi(shop.selected + (-1 if side == "left" else 1), 0, shop.items.size())
		Sfx.play("select")
		_refresh_shop()
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		match state:
			State.MENU:
				_enter(State.PLAYING)
			State.HOUR_END:
				_enter(State.WIN if logic.is_last_hour() else State.SHOP)
			State.SHOP:
				_checkout()
			State.GAME_OVER, State.WIN:
				_enter(State.MENU)


func _on_shift(side: String) -> void:
	var result := logic.press_shift(side)
	match result:
		"toggle":
			Sfx.play("gate_click")
		"estop":
			Sfx.play("estop")
			juice.shake(0.35)
			juice.popup("EMERGENCY STOP!", Vector2(480, 200), Color("ff7043"), 28)
		"denied":
			Sfx.play("strike_buzz")
			juice.popup("NO E-STOPS LEFT" if logic.estops_left == 0 else "ALREADY STOPPED", Vector2(480, 200), Color("ef5350"))
	_update_hud()


## Enter in the shop: buy the selected item (or skip) and start the next hour.
func _checkout() -> void:
	var item: Dictionary = shop.items[shop.selected]
	if item.id == "skip":
		_enter(State.PLAYING)
	elif logic.buy(item.id):
		Sfx.play("cash")
		_enter(State.PLAYING)
		juice.popup(item.name.to_upper() + "!", Vector2(480, 380), Color("ffca28"), 26)
	else:
		Sfx.play("strike_buzz")
		juice.shake(0.2)


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
				juice.puff(t.position, Tray.FOOD.get(t.kind, Color.WHITE))
			t.queue_free()
	_update_pa()
	hazard.visible = logic.is_stopped()
	hazard.color.a = 0.12 + 0.1 * sin(logic.clock * 14.0)
	_update_hud()


func _update_pa() -> void:
	pa_banner.visible = logic.pa_left > 0.0
	if logic.pa_count != _pa_seen:
		_pa_seen = logic.pa_count
		pa_banner.get_node("Text").text = "PA:  " + logic.pa_line
		Sfx.play("pa_jingle")


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
	t.falling = logic.last_missed
	t.path.append(Belt.FLOOR if t.falling else Belt.EXITS[logic.route])
	t.result = 1 if result == "ok" else -1
	t.queue_redraw()
	match result:
		"ok":
			var milestone := logic.combo % ShiftState.COMBO_STEP == 0
			Sfx.play("ding", 1.0 + 0.08 * (logic.multiplier() - 1) + (0.15 if milestone else 0.0))
			juice.popup("+$%d" % logic.last_gain, POPUP_AT, Color("9ccc65"))
			if milestone:
				juice.popup("COMBO %d!  x%d PAY" % [logic.combo, logic.multiplier()], Vector2(480, 180), Color("ffca28"), 30)
		"wrong", "missed":
			Sfx.play(RESULT_SOUNDS[result])
			juice.shake(0.6)
			juice.popup("STRIKE!" if result == "wrong" else "MISSED!", POPUP_AT, Color("ef5350"), 28)
			juice.puff(Belt.FORK, Color("ef5350"), 10)
		"covered":
			Sfx.play(RESULT_SOUNDS[result])
			juice.shake(0.25)
			juice.popup("YOUR MATE COVERED IT!", POPUP_AT, Color("4fc3f7"), 24)
	if logic.sent_home():
		_enter(State.GAME_OVER)


func _clear_trays() -> void:
	for t in trays.get_children():
		t.queue_free()


# --- HUD -------------------------------------------------------------------

func _show(text: String) -> void:
	message.text = text
	dim.visible = text != ""


func _refresh_shop() -> void:
	shop.wallet = logic.wallet()
	shop.heading = "%s - %s break. One item, or skip." % [ShiftState.hour_name(logic.hour), ShiftState.hour_name(logic.hour + 1)]
	shop.owned = "Mate's Help x%d" % logic.mates if logic.mates > 0 else ""
	shop.queue_redraw()


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
	var items := PackedStringArray()
	if logic.coffee:
		items.append("COFFEE")
	if logic.earplugs:
		items.append("EARPLUGS")
	if logic.mates > 0:
		items.append("MATE x%d" % logic.mates)
	stats.text = "%s   HOUR %d/%d\nPAY  $%d\nCOMBO  %d   (x%d pay)\nSTRIKES  %s\nE-STOPS  %d\nBELT  %.1fx%s\n%s" % [
		logic.clock_text(), maxi(logic.hour + 1, 1), cfg.hours.size(),
		logic.wallet(), logic.combo, logic.multiplier(),
		"X ".repeat(logic.strikes) + "_ ".repeat(maxi(allowed - logic.strikes, 0)),
		logic.estops_left, logic.speed / cfg.hours[0].speed[0],
		"    STOPPED!" if logic.is_stopped() else "", "  ".join(items)]
	belt.route = logic.route
	belt.swinging = logic.is_swinging()
	belt.queue_redraw()
