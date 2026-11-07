extends Node2D
## Scene glue: game state machine, Shift input, spawning and moving trays, HUD, shop, juice,
## the pause menu and the record book.
## The rules themselves live in ShiftState (scripts/shift_state.gd).

enum State { MENU, PLAYING, SHOP, SLOTS, GAME_OVER, WIN }

const TRAY := preload("res://scenes/tray.tscn")
const ROUTE_NAMES := {"left": "LEFT", "center": "STRAIGHT", "right": "RIGHT"}
const RESULT_SOUNDS := {"ok": "ding", "wrong": "strike_buzz", "missed": "missed", "covered": "select"}
const TRAY_EDGE := {"ok": 1, "wrong": -1, "missed": -1, "covered": -1}  # strange trays keep a plain edge
const LIGHTS_OUT := Color(0.28, 0.3, 0.42)  # the line under a flickering light
const RADIO_COLOUR := Color(0.12, 0.3, 0.16, 0.97)  # the PA banner when it picks up clucking
const SKIP := {"id": "skip", "name": "Skip", "price": 0, "text": "Keep your pay. Straight back to the line."}
const POPUP_AT := Belt.FORK + Vector2(0, -70)
const MUSIC_STEP := 0.03  # the music plays this much faster every hour (#34)

var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state := State.MENU
var logic := ShiftState.new(cfg)
var _pa_seen := 0  # logic.pa_count when the banner last updated
var backup_keys := false  # Z and / stand in for the Shifts; see _side()
var lights_out := false  # the flicker as last shown
var _pa_colour: Color
var paused := false  # Esc / P during a shift (#31)
var records_path := Records.PATH  # the tests point this at a scratch file before _ready
var records: Dictionary  # the record book and the mute setting (#32)

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
@onready var slots: Control = $HUD/Slots
@onready var title: Control = $HUD/Title
@onready var ending: Control = $HUD/Ending


func _ready() -> void:
	$Fork.position = Belt.FORK + Vector2(0, -25)
	$Fork.area_entered.connect(_on_tray_at_fork)
	spawn_timer.timeout.connect(_spawn)
	hour_timer.timeout.connect(_on_hour_over)
	shop.items = cfg.shop + [SKIP]
	slots.settled.connect(_on_spin_settled)
	_pa_colour = pa_banner.color
	records = Records.load_file(records_path)
	AudioServer.set_bus_mute(0, records.muted)
	title.records = records
	_enter(State.MENU)


# --- state machine ---------------------------------------------------------

func _enter(new_state: State) -> void:
	state = new_state
	paused = false
	if state != State.PLAYING:
		_set_loops(false)
		spawn_timer.stop()
		hour_timer.stop()
		note_card.hide()
		pa_banner.hide()
		hazard.hide()
		_set_lights(false)
	title.visible = state == State.MENU
	shop.visible = state == State.SHOP
	slots.visible = state == State.SLOTS
	ending.visible = state == State.WIN
	_show("")
	match state:
		State.MENU:
			logic = ShiftState.new(cfg)
			_pa_seen = 0
			_clear_trays()
		State.PLAYING:
			_start_hour()
		State.SHOP:
			shop.selected = shop.items.size() - 1  # start on Skip, so Enter alone never spends
			_refresh_shop()
		State.SLOTS:
			slots.wallet = logic.wallet() - logic.last_spin.payout  # the win shows when the reels stop
			slots.start(logic.last_spin, cfg.slots.weights)
		State.GAME_OVER:
			juice.shake(1.0)
			var beaten := _record_night(false)
			_show("SENT HOME at %s!\n\nEarned: $%d    Spent: $%d%s\nTrays sorted: %d\nAccuracy: %d%%\nBest combo: %d\n%s\nPress Enter to clock in again"
				% [logic.clock_text(), logic.pay, logic.spent, "    Bets: %s" % _signed(logic.winnings) if logic.winnings != 0 else "",
				logic.sorted_total, roundi(logic.accuracy() * 100), logic.best_combo,
				"NEW BEST: %s\n" % beaten if beaten != "" else ""])
		State.WIN:
			var which := logic.ending()
			Sfx.play("clock_in")
			if which == "secret":
				Sfx.play("cluck", 1.1)
			var rows := [["Earned", "$%d" % logic.pay], ["Break room", "-$%d" % logic.spent]]
			if logic.winnings != 0:
				rows.append(["Bets and slots", _signed(logic.winnings)])
			rows += [["Take-home pay", "$%d" % logic.wallet()], ["Trays sorted", str(logic.sorted_total)],
				["Accuracy", "%d%%" % roundi(logic.accuracy() * 100)], ["Best combo", str(logic.best_combo)]]
			if logic.strange_seen > 0:
				rows.append(["Let through to the dock", "%d of %d" % [logic.escaped, logic.strange_seen]])
			ending.show_ending(which == "secret", cfg.endings[which], rows, logic.ledger, _record_night(true))
	_refresh_rules()
	_update_hud()


func _signed(amount: int) -> String:
	return "%s$%d" % ["+" if amount >= 0 else "-", absi(amount)]


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
	_set_loops(true)


## The factory hum and the music run only while working; the music gets a little faster every hour.
func _set_loops(on: bool) -> void:
	Sfx.loop("hum", on)
	Sfx.loop("music", on, 1.0 + MUSIC_STEP * maxi(logic.hour, 0))


## Esc / P during a shift (#31). Everything on the game clock (belt, PA, flicker, emergency stop)
## stops because _physics_process skips logic.tick(); the two Timers are paused by hand.
func _set_paused(on: bool) -> void:
	paused = on
	spawn_timer.paused = on or logic.is_stopped()
	hour_timer.paused = spawn_timer.paused
	_set_loops(not on)
	if on:  # out of the card's way; _physics_process brings them back on resume
		note_card.hide()
		pa_banner.hide()
	_show_pause()


func _show_pause() -> void:
	_show("PAUSED\n\nEsc / P    back to work\nM    sound: %s\nQ    quit to the title (this night won't count)"
		% ("OFF" if records.muted else "ON") if paused else "")


## M on the title or the pause menu. Mutes the master bus and remembers it.
func _toggle_mute() -> void:
	records.muted = not records.muted
	AudioServer.set_bus_mute(0, records.muted)
	Records.save_file(records, records_path)
	_show_pause()


## Folds the finished night into the record book and saves it. Returns what it beat, for a NEW BEST line.
func _record_night(survived: bool) -> String:
	var beaten := Records.describe(Records.merge(records, logic, survived))
	Records.save_file(records, records_path)
	return beaten


## Losing focus mid-shift (alt-tab, clicking off the browser tab) pauses, so the belt doesn't run on unseen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and not paused:
		_set_paused(true)


## The hour's tally goes on the break-room heading (and the 6 AM ledger), so there is no screen to Enter past.
func _on_hour_over() -> void:
	if state == State.PLAYING:
		_clear_trays()
		logic.end_hour()
		Sfx.play("hour_end")
		_enter(State.WIN if logic.is_last_hour() else State.SHOP)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var side := _side(key)
	if state == State.PLAYING:
		if key.keycode in [KEY_ESCAPE, KEY_P]:
			_set_paused(not paused)
		elif paused and key.keycode == KEY_M:
			_toggle_mute()
		elif paused and key.keycode == KEY_Q:
			_enter(State.MENU)
		elif side != "" and not paused:
			_on_shift(side)
		return
	if state == State.MENU and key.keycode == KEY_M:
		_toggle_mute()
		return
	if state == State.SLOTS and side != "":
		slots.stop_next()
		return
	if state == State.SHOP and side != "":
		shop.selected = wrapi(shop.selected + (-1 if side == "left" else 1), 0, shop.items.size())
		Sfx.play("select")
		_refresh_shop()
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		match state:
			State.MENU:
				_enter(State.PLAYING)
			State.SHOP:
				_checkout()
			State.SLOTS:
				if slots.done:
					_enter(State.PLAYING)
			State.GAME_OVER:  # one key to try again
				_enter(State.MENU)
				_enter(State.PLAYING)
			State.WIN:
				_enter(State.MENU)


## Which gate a key works: "left", "right" or "" (not a gate key). Some setups (remote desktop,
## some browsers) send Shift with no left/right location (#22). Guessing would make one gate
## unreachable, so that Shift does nothing and Z / slash, the keys beside each Shift, take over.
func _side(key: InputEventKey) -> String:
	if key.keycode == KEY_SHIFT:
		match key.location:
			KEY_LOCATION_LEFT:
				return "left"
			KEY_LOCATION_RIGHT:
				return "right"
		if not backup_keys:
			backup_keys = true
			title.backup_keys = true
			_update_hud()
		return ""
	if backup_keys:
		match key.keycode:
			KEY_Z:
				return "left"
			KEY_SLASH:
				return "right"
	return ""


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


## Enter in the shop: buy the selected item (or skip) and start the next hour, or spin the slots first.
func _checkout() -> void:
	var item: Dictionary = shop.items[shop.selected]
	if item.id == "skip":
		_enter(State.PLAYING)
	elif logic.buy(item.id):
		Sfx.play("cash")
		if item.id == "slots":
			_enter(State.SLOTS)
			return
		_enter(State.PLAYING)
		juice.popup(item.name.to_upper() + "!", Vector2(480, 380), Color("ffca28"), 26)
	else:
		Sfx.play("strike_buzz")
		juice.shake(0.2)


## The reels have stopped: pay out, as loudly as the win deserves.
func _on_spin_settled() -> void:
	slots.wallet = logic.wallet()
	var spin: Dictionary = logic.last_spin
	if spin.payout >= cfg.slots.three.stranger:
		Sfx.play("jackpot")
	elif spin.payout > cfg.slots.pair:
		Sfx.play("jackpot", 1.3)
	elif spin.payout > 0:
		Sfx.play("cash")
	else:
		Sfx.play("missed")


# --- belt ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state != State.PLAYING or paused:
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
	_set_lights(logic.lights_out())
	hazard.visible = logic.is_stopped()
	hazard.color.a = 0.12 + 0.1 * sin(logic.clock * 14.0)
	_update_hud()


func _update_pa() -> void:
	pa_banner.visible = logic.pa_left > 0.0
	if logic.pa_count != _pa_seen:
		_pa_seen = logic.pa_count
		pa_banner.get_node("Text").text = ("RADIO?  " if logic.pa_radio else "PA:  ") + logic.pa_line
		pa_banner.color = RADIO_COLOUR if logic.pa_radio else _pa_colour
		Sfx.play("radio" if logic.pa_radio else "pa_jingle")


## The flickering lights from 2 AM: the belt and trays go dark, with an electric buzz as they cut out.
func _set_lights(out: bool) -> void:
	if out and not lights_out:
		Sfx.play("flicker")
	lights_out = out
	belt.modulate = LIGHTS_OUT if out else Color.WHITE
	trays.modulate = belt.modulate


func _spawn() -> void:
	var spec := logic.next_tray()
	var t: Tray = TRAY.instantiate()
	t.kind = spec.kind
	t.stamp = spec.stamp
	t.position = Belt.SPAWN
	t.path = [Belt.FORK]
	trays.add_child(t)
	spawn_timer.start(logic.next_gap())


func _on_tray_at_fork(area: Area2D) -> void:
	var t := area as Tray
	if state != State.PLAYING or t == null or t.routed:
		return
	t.routed = true
	var result := logic.sort(t.kind, t.stamp)
	t.falling = logic.last_missed
	t.path.append(Belt.FLOOR if t.falling else Belt.EXITS[logic.route])
	t.result = TRAY_EDGE.get(result, 0)
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
		"escaped":
			Sfx.play("cluck", 1.25)
			juice.popup("PSST... THANKS.", POPUP_AT, Color("ce93d8"), 22)
		"caught":
			Sfx.play("cluck", 0.8)
			juice.popup("BAWK?!", POPUP_AT, Color("b0bec5"), 24)
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
	var t: Dictionary = logic.ledger.back()
	shop.heading = "%s - %s done: %d of %d right, %d strike%s, $%d pay + $%d clean bonus" % [t.from, t.to, t.ok, t.sorted, t.strikes, "" if t.strikes == 1 else "s", t.pay, t.bonus]
	shop.owned = "Mate's Help x%d" % logic.mates if logic.mates > 0 else ""
	shop.bet_result = logic.last_bet
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
	if logic.bet > 0:
		items.append("BET $%d" % logic.bet)
	if logic.mates > 0:
		items.append("MATE x%d" % logic.mates)
	stats.text = "%s   HOUR %d/%d\nPAY  $%d\nCOMBO  %d   (x%d pay)\nSTRIKES  %s\nE-STOPS  %d\nBELT  %.1fx%s\n%s" % [
		logic.clock_text(), maxi(logic.hour + 1, 1), cfg.hours.size(),
		logic.wallet(), logic.combo, logic.multiplier(),
		"X ".repeat(logic.strikes) + "_ ".repeat(maxi(allowed - logic.strikes, 0)),
		logic.estops_left, logic.speed / cfg.hours[0].speed[0],
		"    STOPPED!" if logic.is_stopped() else "", "  ".join(items)]
	if backup_keys:
		stats.text += "\nGATES  Z  and  /"
	belt.route = logic.route
	belt.swinging = logic.is_swinging()
	belt.queue_redraw()
