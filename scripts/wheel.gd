extends Control

signal rotate_requested(dir: int)

@export var wheel_title := "主语"
@export var step_cost := 1
@export var style_normal: StyleBoxFlat
@export var style_active: StyleBoxFlat

var words: Array = []
var wear: Array = []
var index := 0
var interactive := false

var _rot_deg := 0.0
var _busy := false
var _slot_nodes: Array = []

@onready var rotor: Node2D = $Rotor
@onready var hub_label: Label = $Hub/TitleLabel
@onready var left_btn: Button = $LeftBtn
@onready var right_btn: Button = $RightBtn
@onready var cost_label: Label = $CostLabel


func _ready() -> void:
	for c in rotor.get_children():
		if c.name.begins_with("Slot"):
			_slot_nodes.append(c)
	_slot_nodes.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	hub_label.text = wheel_title
	cost_label.text = "每格 %d 点" % step_cost
	left_btn.pressed.connect(func() -> void: rotate_requested.emit(-1))
	right_btn.pressed.connect(func() -> void: rotate_requested.emit(1))
	_refresh()


func setup(list: Array) -> void:
	words = list.duplicate(true)
	wear.resize(words.size())
	wear.fill(0)
	index = 0
	_rot_deg = 0.0
	rotor.rotation_degrees = 0.0
	for s in _slot_nodes:
		s.rotation_degrees = 0.0
	for i in words.size():
		_slot_label(i).text = words[i]["text"]
	_refresh()


func rotate(dir: int, steps := 1) -> void:
	if _busy:
		return
	_busy = true
	var target := _rot_deg - 60.0 * dir * steps
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(rotor, "rotation_degrees", target, 0.4)
	for s in _slot_nodes:
		tween.parallel().tween_property(s, "rotation_degrees", -target, 0.4)
	await tween.finished
	_rot_deg = target
	index = posmod(-int(_rot_deg / 60.0), words.size())
	_busy = false
	_refresh()


func goto_index(i: int) -> void:
	index = i
	_rot_deg = -60.0 * i
	rotor.rotation_degrees = _rot_deg
	for s in _slot_nodes:
		s.rotation_degrees = -_rot_deg
	_refresh()


func set_interactive(v: bool) -> void:
	interactive = v
	_refresh()


func current_word():
	if words.is_empty() or wear[index] >= 3:
		return null
	return words[index]


func exhausted() -> bool:
	for w in wear:
		if w < 3:
			return false
	return true


func wear_current() -> void:
	wear[index] += 1
	_refresh()


func restore_worst() -> void:
	var worst := -1
	var worst_val := 0
	for i in wear.size():
		if wear[i] > worst_val:
			worst_val = wear[i]
			worst = i
	if worst >= 0:
		wear[worst] -= 1
		_refresh()


func swap_words(other: Control) -> void:
	var w := words
	words = other.words
	other.words = w
	var r := wear
	wear = other.wear
	other.wear = r
	for i in words.size():
		_slot_label(i).text = words[i]["text"]
	for i in other.words.size():
		other._slot_label(i).text = other.words[i]["text"]
	_refresh()
	other._refresh()
	var tween := create_tween()
	tween.tween_property($Hub, "scale", Vector2(1.15, 1.15), 0.12)
	tween.tween_property($Hub, "scale", Vector2.ONE, 0.12)


func _slot_label(i: int) -> Label:
	return _slot_nodes[i].get_node("WordLabel") as Label


func _refresh() -> void:
	if not words.is_empty():
		for i in _slot_nodes.size():
			var base := 1.0 if i == index else 0.55
			var w: int = wear[i]
			var active := i == index and w < 3
			_slot_nodes[i].set("theme_override_styles/panel", style_active if active else style_normal)
			_slot_label(i).add_theme_color_override("font_color", Color(0.16, 0.12, 0.07) if active else Color(0.93, 0.92, 0.86))
			if w >= 3:
				_slot_label(i).text = "……"
				_slot_nodes[i].modulate = Color(1, 1, 1, 0.25)
			else:
				_slot_label(i).text = words[i]["text"]
				var alpha := base * (0.45 if w == 2 else (0.75 if w == 1 else 1.0))
				_slot_nodes[i].modulate = Color(1, 1, 1, alpha)
	left_btn.disabled = not interactive or _busy
	right_btn.disabled = not interactive or _busy
