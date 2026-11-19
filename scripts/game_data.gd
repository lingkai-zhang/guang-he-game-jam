extends Node

const ROUND_LIMIT := 12
const DIST_IDEAL_MIN := 35.0
const DIST_IDEAL_MAX := 65.0

const SUBJECTS := [
	{"id": "self", "text": "我"},
	{"id": "other", "text": "你"},
	{"id": "both", "text": "我们"},
	{"id": "none", "text": "没人"},
	{"id": "time", "text": "时间"},
	{"id": "lamp", "text": "灯"},
]

const VERBS := [
	{"id": "blame", "text": "责备", "delta": 8.0},
	{"id": "leave", "text": "离开", "delta": 12.0},
	{"id": "forget", "text": "忘记", "delta": 9.0},
	{"id": "remember", "text": "记得", "delta": -6.0},
	{"id": "wait", "text": "等待", "delta": -2.0},
	{"id": "forgive", "text": "原谅", "delta": -10.0},
]

const OBJECTS := [
	{"id": "knot_rain", "text": "那天的雨"},
	{"id": "knot_letter", "text": "没寄的信"},
	{"id": "knot_door", "text": "没关的门"},
	{"id": "name", "text": "你的名字"},
	{"id": "silence", "text": "沉默"},
	{"id": "myself", "text": "自己"},
]

# need_subject / need_speaker 取值: "self"=说话者自己, "any"=不限
# need_speaker 的 "self"/"other" 指现实身份: self=玩家(现在的我), other=ta(过去的我)
const KNOTS := [
	{
		"id": "knot_rain", "noun": "那天的雨",
		"need_verb": "remember", "need_subject": "self", "need_speaker": "other",
		"tear_verb": "blame",
		"hint": "等 ta 亲口说：我 记得 那天的雨",
	},
	{
		"id": "knot_letter", "noun": "没寄的信",
		"need_verb": "forgive", "need_subject": "self", "need_speaker": "self",
		"tear_verb": "blame",
		"hint": "需要你亲口说：我 原谅 没寄的信",
	},
	{
		"id": "knot_door", "noun": "没关的门",
		"need_verb": "leave", "need_subject": "any", "need_speaker": "any",
		"tear_verb": "wait",
		"hint": "谁都可以说：…… 离开 没关的门",
	},
]

const KNOT_STATES := ["未触碰", "被提起", "已解开", "被撕裂"]

const MOOD_ORDER := ["倔强", "委屈", "疲惫", "柔软"]

const TOOL_INFO := {
	"peek": "偷看：看穿 ta 下一步的格数与方向",
	"cuff": "手铐：跳过 ta 的下一回合",
	"saw": "锯子：你下一句话的距离效果 ×2",
	"cig": "香烟：修复一个磨旧最深的词",
}

# start: 主/谓/宾轮盘开局停在第几格（0-5）
const LEVELS := [
	{
		"title": "第一幕 · 坐下",
		"intro": "你们很久没说话了。先别谈那件事——先让距离回到能开口地方。",
		"goal_text": "目标：把距离降到 65 以下",
		"goal": {"type": "distance_at_most", "value": 65.0},
		"start_distance": 85.0, "rounds": 6, "mood": "疲惫",
		"start": {"s": 3, "v": 0, "o": 4},
		"tools": {},
		"ui": {},
	},
	{
		"title": "第二幕 · 那天的雨",
		"intro": "雨声又来了。提起不等于解开——这句话必须从 ta 嘴里说出来才算。",
		"goal_text": "目标：让 ta 亲口说「我 记得 那天的雨」",
		"goal": {"type": "knot", "id": "knot_rain"},
		"start_distance": 60.0, "rounds": 8, "mood": "倔强",
		"start": {"s": 0, "v": 2, "o": 0},
		"tools": {"peek": 1},
		"ui": {"silence": true, "knots": true, "telegraph": true},
	},
	{
		"title": "第三幕 · 没寄的信",
		"intro": "信在抽屉里睡了三年。词开始磨旧——说过的话不会一直等你。",
		"goal_text": "目标：你亲口说「我 原谅 没寄的信」",
		"goal": {"type": "knot", "id": "knot_letter"},
		"start_distance": 55.0, "rounds": 8, "mood": "委屈",
		"start": {"s": 1, "v": 4, "o": 1},
		"tools": {"cuff": 1, "cig": 1},
		"ui": {"silence": true, "knots": true, "telegraph": true, "negate": true, "unsaid": true, "wear": true},
	},
	{
		"title": "第四幕 · 没关的门",
		"intro": "门一直没关。你们都在等对方先走，或者先留下。",
		"goal_text": "目标：任何人说出「…… 离开 没关的门」",
		"goal": {"type": "knot", "id": "knot_door"},
		"start_distance": 50.0, "rounds": 9, "mood": "倔强",
		"start": {"s": 4, "v": 3, "o": 3},
		"tools": {"saw": 1, "peek": 1},
		"ui": {"silence": true, "knots": true, "telegraph": true, "negate": true, "unsaid": true, "wear": true, "invert": true},
	},
	{
		"title": "第五幕 · 最后一句",
		"intro": "词快用完了。最后一句话必须由你说，而且主语必须是「我们」。",
		"goal_text": "目标：在舒适距离内，由你说出以「我们」开头的句子",
		"goal": {"type": "final_we"},
		"start_distance": 50.0, "rounds": 10, "mood": "柔软",
		"start": {"s": 0, "v": 1, "o": 5},
		"tools": {"peek": 1, "cuff": 1, "saw": 1, "cig": 1},
		"ui": {"silence": true, "knots": true, "telegraph": true, "negate": true, "unsaid": true, "wear": true, "invert": true},
	},
]

const MOOD_HINTS := {
	"倔强": "只甩冷词，步幅大",
	"委屈": "小步磨宾语轮",
	"疲惫": "只把主语轮转 1 格",
	"柔软": "步轻，不固定轮",
}

# wheel 键: subject / verb / object；steps 键: 格数
const MOODS := {
	"倔强": {"wheel": {"subject": 1, "verb": 3, "object": 2}, "steps": {1: 1, 2: 2, 3: 3}},
	"委屈": {"wheel": {"subject": 1, "verb": 1, "object": 3}, "steps": {1: 3, 2: 2, 3: 1}},
	"疲惫": {"wheel": {"subject": 3, "verb": 1, "object": 1}, "steps": {1: 3, 2: 1}},
	"柔软": {"wheel": {"subject": 2, "verb": 2, "object": 2}, "steps": {1: 2, 2: 2, 3: 1}},
}

const ENDINGS := {
	"和解": "三个心结都解开了。词快用完了，但你们还坐在桌边。",
	"你忘记了 ta": "距离拉到了最远。你想不起自己为什么要坐在这里。",
	"ta 放弃了你": "有些话太重了，有些结被撕开了。ta 不再等了。",
	"没说完的话": "轮次用完了。有些话，这辈子没轮到。",
	"ta 替你说完": "你的词磨光了。ta 叹了口气，替你把后半句说完。",
	"分不清你和我": "靠得太近了，字都烫着了。你们又变回了同一个人。",
}

const LAST_SUBJECT_LINES := {
	"self": "最后一句，是现在的你先开的口。",
	"other": "最后一句，是 ta 先开的口。",
	"both": "最后一句，主语是「我们」。",
	"none": "最后一句没有主语，像一句自言自语。",
	"time": "最后一句的主语是时间。时间不说话，时间只是经过。",
	"lamp": "最后一句的主语是灯。灯还亮着。",
}


func verb_delta(verb_id: String) -> float:
	for v in VERBS:
		if v["id"] == verb_id:
			return v["delta"]
	return 0.0


func knot_by_object(object_id: String) -> Dictionary:
	for k in KNOTS:
		if k["id"] == object_id:
			return k
	return {}


func shift_mood(current: String, steps: int) -> String:
	var idx := MOOD_ORDER.find(current)
	idx = clampi(idx + steps, 0, MOOD_ORDER.size() - 1)
	return MOOD_ORDER[idx]


func weighted_pick(weights: Dictionary):
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return weights.keys()[0]
	var roll := randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys().back()
