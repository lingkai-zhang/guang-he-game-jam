extends Control

enum Speaker { SELF, OTHER }

const WHEEL_NAMES := {"subject": "主语轮", "verb": "谓语轮", "object": "宾语轮"}
const TOOL_IDS := ["peek", "cuff", "saw", "cig"]

var level_idx := -1
var level: Dictionary = {}
var player_turn := false
var busy := true
var ended := false
var turn_points := 4
var round_num := 1
var mood := "倔强"
var distance := 50.0
var insincere := 0
var negate_left := 2
var negated := false
var ai_target_key := "verb"
var ai_next_steps := 1
var ai_next_dir := 1
var peeked := false
var skip_ai := false
var saw_armed := false
var tools := {}
var scars := 0
var knot_state := {}
var tear_progress := {}
var display_log: Array = []
var spoken_log: Array = []
var unsaid_log: Array = []
var last_subject_id := "none"
var last_speaker := Speaker.SELF
var interstitial_mode := ""
var pending_next := -1

@onready var wheel_s: Control = $WheelsRow/WheelS
@onready var wheel_v: Control = $WheelsRow/WheelV
@onready var wheel_o: Control = $WheelsRow/WheelO
@onready var title_label: Label = $TitleLabel
@onready var mood_label: Label = $TopBar/MoodLabel
@onready var round_label: Label = $TopBar/RoundLabel
@onready var points_label: Label = $TopBar/PointsLabel
@onready var dist_info_label: Label = $Row2/DistInfoLabel
@onready var distance_bar: ProgressBar = $Row2/DistanceBar
@onready var telegraph_label: Label = $Row2/MoodTelegraphLabel
@onready var sentence_label: Label = $SentenceStrip/SentenceLabel
@onready var btn_speak: Button = $ActionBar/BtnSpeak
@onready var btn_negate: Button = $ActionBar/BtnNegate
@onready var btn_invert: Button = $ActionBar/BtnInvert
@onready var btn_unsaid: Button = $ActionBar/BtnUnsaid
@onready var btn_silence: Button = $ActionBar/BtnSilence
@onready var tool_buttons := {
	"peek": $ToolBar/BtnPeek,
	"cuff": $ToolBar/BtnCuff,
	"saw": $ToolBar/BtnSaw,
	"cig": $ToolBar/BtnCig,
}
@onready var goal_label: Label = $KnotsPanel/KnotsVBox/GoalLabel
@onready var knot_labels: Array = [$KnotsPanel/KnotsVBox/Knot0, $KnotsPanel/KnotsVBox/Knot1, $KnotsPanel/KnotsVBox/Knot2]
@onready var unsaid_label: Label = $UnsaidPanel/UnsaidVBox/UnsaidLabel
@onready var unsaid_panel: Control = $UnsaidPanel
@onready var log_label: Label = $LogPanel/LogLabel
@onready var level_panel: ColorRect = $LevelPanel
@onready var level_title: Label = $LevelPanel/Center/LevelVBox/LevelTitle
@onready var level_body: Label = $LevelPanel/Center/LevelVBox/LevelBody
@onready var btn_continue: Button = $LevelPanel/Center/LevelVBox/BtnContinue
@onready var btn_retry: Button = $LevelPanel/Center/LevelVBox/BtnRetry
@onready var end_panel: ColorRect = $EndPanel
@onready var end_title: Label = $EndPanel/Center/EndVBox/EndTitle
@onready var end_story: Label = $EndPanel/Center/EndVBox/EndStory
@onready var btn_restart: Button = $EndPanel/Center/EndVBox/BtnRestart


func _ready() -> void:
	for k in GameData.KNOTS:
		knot_state[k["id"]] = 0
		tear_progress[k["id"]] = 0
	wheel_s.rotate_requested.connect(_on_rotate.bind(wheel_s))
	wheel_v.rotate_requested.connect(_on_rotate.bind(wheel_v))
	wheel_o.rotate_requested.connect(_on_rotate.bind(wheel_o))
	btn_speak.pressed.connect(_on_speak)
	btn_negate.pressed.connect(_on_negate)
	btn_invert.pressed.connect(_on_invert)
	btn_unsaid.pressed.connect(_on_unsaid)
	btn_silence.pressed.connect(_on_silence)
	for id in TOOL_IDS:
		tool_buttons[id].pressed.connect(_on_tool.bind(id))
	btn_continue.pressed.connect(_on_continue)
	btn_retry.pressed.connect(_on_retry)
	btn_restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_load_level(0)
	_show_interstitial("intro", level["title"], level["intro"] + "\n\n" + level["goal_text"])


func _load_level(i: int) -> void:
	level_idx = i
	level = GameData.LEVELS[i]
	round_num = 1
	turn_points = 4
	distance = level["start_distance"]
	mood = level["mood"]
	negated = false
	negate_left = 2
	peeked = false
	skip_ai = false
	saw_armed = false
	tools = level["tools"].duplicate()
	wheel_s.setup(GameData.SUBJECTS)
	wheel_v.setup(GameData.VERBS)
	wheel_o.setup(GameData.OBJECTS)
	wheel_s.goto_index(level["start"]["s"])
	wheel_v.goto_index(level["start"]["v"])
	wheel_o.goto_index(level["start"]["o"])
	display_log.append("—— %s ——" % level["title"])
	_commit_ai_target()
	player_turn = false
	busy = true
	_update_ui()


func _begin_play() -> void:
	level_panel.visible = false
	player_turn = true
	busy = false
	_update_ui()


func _show_interstitial(mode: String, t: String, body: String) -> void:
	interstitial_mode = mode
	level_title.text = t
	level_body.text = body
	btn_retry.visible = mode == "fail"
	btn_continue.visible = mode != "fail"
	btn_continue.text = "坐下，开始" if mode == "intro" else "继续"
	level_panel.visible = true
	player_turn = false
	busy = true
	_update_ui()


func _on_continue() -> void:
	if interstitial_mode == "clear":
		_load_level(pending_next)
	_begin_play()


func _on_retry() -> void:
	var g: Dictionary = level["goal"]
	if g["type"] == "knot":
		knot_state[g["id"]] = 1
		tear_progress[g["id"]] = 1
	scars += 1
	_load_level(level_idx)
	_begin_play()


func _on_rotate(dir: int, wheel: Control) -> void:
	if not player_turn or busy or ended:
		return
	if turn_points < wheel.step_cost:
		return
	turn_points -= wheel.step_cost
	busy = true
	_update_ui()
	await wheel.rotate(dir)
	busy = false
	_update_ui()


func _on_speak() -> void:
	var line := _current_line(negated)
	if line == "":
		return
	_resolve(Speaker.SELF, negated, line)
	_after_player_action()


func _on_unsaid() -> void:
	var line := _current_line(negated)
	if line == "":
		return
	unsaid_log.append(line)
	display_log.append("（没说出口）" + line)
	_after_player_action()


func _on_silence() -> void:
	wheel_s.restore_worst()
	wheel_v.restore_worst()
	wheel_o.restore_worst()
	display_log.append("……（沉默。磨旧的词恢复了一点。）")
	if mood == "柔软":
		distance = clampf(distance - 2.0, 0.0, 100.0)
	else:
		distance = clampf(distance + 2.0, 0.0, 100.0)
	_after_player_action()


func _on_negate() -> void:
	if negated:
		negated = false
	elif negate_left > 0:
		negated = true
		negate_left -= 1
	_update_ui()


func _on_invert() -> void:
	if turn_points < 3:
		return
	turn_points -= 3
	wheel_s.swap_words(wheel_o)
	display_log.append("（倒装）主语和宾语换了位置。")
	busy = true
	_update_ui()
	await get_tree().create_timer(0.3).timeout
	busy = false
	_update_ui()


func _on_tool(id: String) -> void:
	if not player_turn or busy or ended:
		return
	if int(tools.get(id, 0)) <= 0:
		return
	match id:
		"peek":
			peeked = true
		"cuff":
			skip_ai = true
		"saw":
			saw_armed = true
		"cig":
			_restore_one_global()
	tools[id] = int(tools[id]) - 1
	display_log.append("（道具：%s）" % GameData.TOOL_INFO[id])
	_update_ui()


func _restore_one_global() -> void:
	var target: Control = null
	var worst_val := 0
	for w in [wheel_s, wheel_v, wheel_o]:
		for val in w.wear:
			if val > worst_val:
				worst_val = val
				target = w
	if target != null:
		target.restore_worst()


func _after_player_action() -> void:
	negated = false
	player_turn = false
	_update_ui()
	if _check_level():
		return
	_ai_turn()


func _ai_turn() -> void:
	busy = true
	_update_ui()
	await get_tree().create_timer(0.7).timeout
	if ended:
		return
	if skip_ai:
		skip_ai = false
		display_log.append("（手铐。ta 这一回合没有说话。）")
		peeked = false
		_after_ai_done()
		return
	var key := ai_target_key
	var wheels := {"subject": wheel_s, "verb": wheel_v, "object": wheel_o}
	var w: Control = wheels[key]
	display_log.append("（ta 的情绪：%s。ta 把%s转了 %s%d 格）" % [mood, WHEEL_NAMES[key], "+" if ai_next_dir > 0 else "-", ai_next_steps])
	await w.rotate(ai_next_dir, ai_next_steps)
	peeked = false
	var line := _current_line(false)
	if line == "":
		display_log.append("ta 张了张嘴，没说出话。")
	else:
		_resolve(Speaker.OTHER, false, line)
	_update_ui()
	_after_ai_done()


func _after_ai_done() -> void:
	if _check_level():
		return
	round_num += 1
	if round_num > level["rounds"]:
		_fail("轮次用完了。这一段话没说完。")
		return
	_commit_ai_target()
	_start_player_turn()


func _start_player_turn() -> void:
	player_turn = true
	turn_points = 4
	busy = false
	_update_ui()
	if _feat("wear") and (wheel_s.exhausted() or wheel_v.exhausted() or wheel_o.exhausted()):
		_fail("词磨光了。你们再也拼不出一句话。")


func _commit_ai_target() -> void:
	var m: Dictionary = GameData.MOODS[mood]
	ai_target_key = GameData.weighted_pick(m["wheel"])
	ai_next_steps = GameData.weighted_pick(m["steps"])
	ai_next_dir = 1 if randf() < 0.5 else -1


func _resolve(speaker: int, is_negated: bool, line: String) -> void:
	var s: Dictionary = wheel_s.current_word()
	var v: Dictionary = wheel_v.current_word()
	var o: Dictionary = wheel_o.current_word()
	var fx: Array = []
	var mood_before := mood
	display_log.append(("你说：" if speaker == Speaker.SELF else "ta 说：") + line)
	spoken_log.append(line)
	last_subject_id = s["id"]
	last_speaker = speaker

	var base := GameData.verb_delta(v["id"])
	var delta := base
	if s["id"] == "both":
		delta *= 1.5
	elif s["id"] in ["none", "time", "lamp"]:
		delta *= 0.5
	if o["id"] == "silence":
		delta *= 0.5
	if is_negated:
		delta *= -1.0
	if saw_armed and speaker == Speaker.SELF:
		delta *= 2.0
		saw_armed = false
		fx.append("锯子×2")
	distance = clampf(distance + delta, 0.0, 100.0)
	var di := roundi(delta)
	fx.append("距离 " + ("+%d" % di if di > 0 else "%d" % di))
	_float_text(distance_bar, ("+%d" % di if di > 0 else "%d" % di), Color(0.95, 0.78, 0.42))

	var knot := GameData.knot_by_object(o["id"])
	if not knot.is_empty() and knot_state[knot["id"]] < 2:
		var st: int = knot_state[knot["id"]]
		if st == 0:
			knot_state[knot["id"]] = 1
			display_log.append("「%s」被提起了。" % knot["noun"])
			mood = GameData.shift_mood(mood, -1)
		elif v["id"] == knot["tear_verb"]:
			tear_progress[knot["id"]] += 1
			if tear_progress[knot["id"]] >= 2:
				knot_state[knot["id"]] = 3
				display_log.append("「%s」被撕开了。" % knot["noun"])
			else:
				display_log.append("「%s」的伤口又深了一点。" % knot["noun"])
				mood = GameData.shift_mood(mood, -1)
		elif v["id"] == "forget":
			knot_state[knot["id"]] = 0
			distance = clampf(distance + 4.0, 0.0, 100.0)
			display_log.append("话又咽了回去。「%s」重新沉底。" % knot["noun"])
		elif v["id"] == knot["need_verb"] and _subject_ok(knot, s) and _speaker_ok(knot, speaker):
			knot_state[knot["id"]] = 2
			distance = move_toward(distance, 50.0, 10.0)
			display_log.append("「%s」解开了。" % knot["noun"])
			mood = GameData.shift_mood(mood, 2)
		elif v["id"] == knot["need_verb"]:
			display_log.append("（这句话没落在对的人嘴里。）")

	if is_negated:
		insincere += 1
		if insincere >= 2:
			display_log.append("ta 看着你，像在看一个说谎的人。")
	elif base < 0.0:
		mood = GameData.shift_mood(mood, 1)
	elif base > 0.0:
		mood = GameData.shift_mood(mood, -1)
	if mood != mood_before:
		fx.append("ta 的情绪→" + mood)
		_float_text(mood_label, "→" + mood, Color(0.78, 0.86, 0.92))
	if not fx.is_empty():
		display_log.append("　→ " + " · ".join(fx))

	if _feat("wear"):
		wheel_s.wear_current()
		wheel_v.wear_current()
		wheel_o.wear_current()


func _feat(name: String) -> bool:
	return bool(level.get("ui", {}).get(name, false))


func _subject_ok(knot: Dictionary, s: Dictionary) -> bool:
	return knot["need_subject"] == "any" or knot["need_subject"] == s["id"]


func _speaker_ok(knot: Dictionary, speaker: int) -> bool:
	if knot["need_speaker"] == "any":
		return true
	return (knot["need_speaker"] == "self") == (speaker == Speaker.SELF)


func _check_level() -> bool:
	if ended or level.is_empty():
		return true
	var g: Dictionary = level["goal"]
	if g["type"] == "knot" and knot_state[g["id"]] == 3:
		_fail("「%s」被撕开了。" % _knot_noun(g["id"]))
		return true
	if insincere >= 3:
		_fail("ta 不再相信你的任何一个字。")
		return true
	if distance >= 100.0:
		_fail("距离太远了。ta 的声音听不见了。")
		return true
	if distance <= 0.0:
		_fail("靠得太近了，字都烫着了。")
		return true
	var cleared := false
	match g["type"]:
		"distance_at_most":
			cleared = distance <= g["value"]
		"knot":
			cleared = knot_state[g["id"]] == 2
		"final_we":
			cleared = last_speaker == Speaker.SELF and last_subject_id == "both" and distance >= GameData.DIST_IDEAL_MIN and distance <= GameData.DIST_IDEAL_MAX
	if cleared:
		_clear()
		return true
	return false


func _knot_noun(id: String) -> String:
	for k in GameData.KNOTS:
		if k["id"] == id:
			return k["noun"]
	return ""


func _clear() -> void:
	display_log.append("—— 这一幕结束了 ——")
	player_turn = false
	busy = true
	if level_idx >= GameData.LEVELS.size() - 1:
		_finish_game()
		return
	pending_next = level_idx + 1
	var nx: Dictionary = GameData.LEVELS[pending_next]
	_show_interstitial("clear", "「%s」 完" % level["title"], "下一幕：" + nx["title"] + "\n" + nx["intro"] + "\n\n" + nx["goal_text"])


func _fail(reason: String) -> void:
	display_log.append("（这一幕失败了：%s）" % reason)
	player_turn = false
	busy = true
	_show_interstitial("fail", "「%s」 没能说完" % level["title"], reason + "\n\n重新想起这一段会留下疤：心结的伤口会更深一格。")


func _finish_game() -> void:
	ended = true
	var title := "和解"
	if insincere >= 2:
		title = "ta 放弃了你"
	elif scars >= 2:
		title = "没说完的话"
	_end(title)


func _end(title: String) -> void:
	ended = true
	player_turn = false
	busy = true
	var story := "\n".join(spoken_log)
	story += "\n\n" + str(GameData.LAST_SUBJECT_LINES.get(last_subject_id, ""))
	story += "\n\n" + str(GameData.ENDINGS.get(title, ""))
	if scars > 0:
		story += "\n\n留下的疤：%d 道。" % scars
	if unsaid_log.is_empty():
		story += "\n\n心底没有藏话。"
	else:
		story += "\n\n心底没说的话：\n" + "\n".join(unsaid_log)
	end_title.text = title
	end_story.text = story
	end_panel.visible = true
	_update_ui()


func _current_line(with_negation: bool) -> String:
	var s = wheel_s.current_word()
	var v = wheel_v.current_word()
	var o = wheel_o.current_word()
	if s == null or v == null or o == null:
		return ""
	if with_negation:
		return "%s 不 %s %s" % [s["text"], v["text"], o["text"]]
	return "%s %s %s" % [s["text"], v["text"], o["text"]]


func _float_text(anchor: Control, text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 18)
	lb.add_theme_color_override("font_color", color)
	add_child(lb)
	lb.global_position = anchor.global_position + Vector2(anchor.size.x * 0.5 - 24.0, -8.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lb, "global_position:y", lb.global_position.y - 34.0, 0.9)
	tw.tween_property(lb, "modulate:a", 0.0, 0.9)
	tw.finished.connect(lb.queue_free)


func _update_ui() -> void:
	title_label.text = str(level.get("title", ""))
	mood_label.text = "ta 的情绪：%s" % mood
	round_label.text = "第 %d / %d 轮" % [round_num, int(level.get("rounds", 12))]
	points_label.text = "转动值：%d" % turn_points
	distance_bar.value = distance
	dist_info_label.text = "距离 %d · 舒适 %d-%d" % [roundi(distance), int(GameData.DIST_IDEAL_MIN), int(GameData.DIST_IDEAL_MAX)]
	var tele := "ta 下一步：%s" % WHEEL_NAMES[ai_target_key]
	if peeked:
		tele += " %s%d 格" % ["+" if ai_next_dir > 0 else "-", ai_next_steps]
	tele += "（%s）" % GameData.MOOD_HINTS[mood]
	telegraph_label.text = tele
	var line := _current_line(negated)
	sentence_label.text = line if line != "" else "（轮盘上有磨光的词，先转开它）"
	btn_negate.text = "取消「不」" if negated else "不……（剩 %d）" % negate_left
	var can_act := player_turn and not busy and not ended
	var speak_ok := can_act and _current_line(false) != ""
	btn_speak.disabled = not speak_ok
	btn_unsaid.disabled = not speak_ok
	btn_silence.disabled = not can_act
	btn_negate.disabled = not (can_act and (negated or negate_left > 0))
	btn_invert.disabled = not (can_act and turn_points >= 3)
	btn_silence.visible = _feat("silence")
	btn_negate.visible = _feat("negate")
	btn_invert.visible = _feat("invert")
	btn_unsaid.visible = _feat("unsaid")
	unsaid_panel.visible = _feat("unsaid")
	telegraph_label.visible = _feat("telegraph")
	for kl in knot_labels:
		kl.visible = _feat("knots")
	wheel_s.set_interactive(can_act and turn_points >= wheel_s.step_cost)
	wheel_v.set_interactive(can_act and turn_points >= wheel_v.step_cost)
	wheel_o.set_interactive(can_act and turn_points >= wheel_o.step_cost)
	for id in TOOL_IDS:
		var btn: Button = tool_buttons[id]
		var count: int = int(tools.get(id, 0))
		btn.visible = tools.has(id)
		btn.text = "%s ×%d" % [GameData.TOOL_INFO[id].split("：")[0], count]
		btn.disabled = not (can_act and count > 0)
		btn.tooltip_text = GameData.TOOL_INFO[id]
	goal_label.text = str(level.get("goal_text", ""))
	for i in knot_labels.size():
		var k: Dictionary = GameData.KNOTS[i]
		var st: int = knot_state[k["id"]]
		var txt := "%s —— %s" % [k["noun"], GameData.KNOT_STATES[st]]
		if st < 2:
			txt += "\n" + k["hint"]
		knot_labels[i].text = txt
	unsaid_label.text = "\n".join(unsaid_log) if not unsaid_log.is_empty() else "（空）"
	log_label.text = "\n".join(display_log.slice(maxi(0, display_log.size() - 12)))
