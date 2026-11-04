class_name Records
extends RefCounted
## The record book and the mute setting, kept between sessions in user://records.cfg
## (on the web, the browser's IndexedDB) (#32). merge() is pure, so the tests drive it without files.

const PATH := "user://records.cfg"
const BLANK := {"nights": 0, "survived": 0, "best_pay": 0, "best_combo": 0, "best_accuracy": 0.0,
	"secret": false, "muted": false}


static func load_file(path := PATH) -> Dictionary:
	var rec := BLANK.duplicate()
	var file := ConfigFile.new()
	if file.load(path) == OK:
		for key: String in rec:
			rec[key] = file.get_value("records", key, rec[key])
	return rec


static func save_file(rec: Dictionary, path := PATH) -> void:
	var file := ConfigFile.new()
	for key: String in rec:
		file.set_value("records", key, rec[key])
	file.save(path)


## Folds one finished night into `rec` and returns the records it beat. Best combo counts any night;
## take-home pay, accuracy and the secret ending only count a night that reached 6 AM.
static func merge(rec: Dictionary, night: ShiftState, survived: bool) -> Array:
	var beaten := []
	rec.nights += 1
	if night.best_combo > rec.best_combo:
		rec.best_combo = night.best_combo
		beaten.append("best_combo")
	if not survived:
		return beaten
	rec.survived += 1
	if night.wallet() > rec.best_pay:
		rec.best_pay = night.wallet()
		beaten.append("best_pay")
	if night.accuracy() > rec.best_accuracy:
		rec.best_accuracy = night.accuracy()
		beaten.append("best_accuracy")
	if night.ending() == "secret" and not rec.secret:
		rec.secret = true
		beaten.append("secret")
	return beaten


## "take-home pay, best combo" for a NEW BEST line; "" if nothing was beaten.
static func describe(beaten: Array) -> String:
	var names := {"best_pay": "take-home pay", "best_combo": "best combo", "best_accuracy": "accuracy",
		"secret": "secret ending found"}
	return ", ".join(beaten.map(func(key): return names[key]))
