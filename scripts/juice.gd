class_name Juice
extends Node2D
## Feedback that is only for show: floating popups, particle puffs and screen shake.
## main.gd calls these; nothing here changes the rules.

const SHAKE_DECAY := 3.0  # trauma lost per second
const SHAKE_PIXELS := 10.0  # offset at full trauma

@export var camera: Camera2D
var trauma := 0.0  # 0..1; shake strength is trauma squared so small knocks stay small


func _process(delta: float) -> void:
	trauma = maxf(trauma - SHAKE_DECAY * delta, 0.0)
	if camera:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SHAKE_PIXELS * trauma * trauma


func shake(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


## Text that floats up from `at` and fades out.
func popup(text: String, at: Vector2, color: Color, size := 22) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 40)
	label.position = at - Vector2(120, 20)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 50.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## A one-shot burst of little squares (feathers, crumbs) at `at`.
func puff(at: Vector2, color: Color, amount := 16) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.6
	p.direction = Vector2.UP
	p.spread = 75.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 190.0
	p.gravity = Vector2(0, 420)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = color
	p.finished.connect(p.queue_free)
	add_child(p)
	p.emitting = true
