class_name Story
## 全部台词和阶段数据。不用歌词；素材是 AI 和电脑梗。
## 注意：像素字体里没有「∞」「✕」「‹」，文字里不要用。

const PHASES := {
	1: {
		"name": "助手模式",
		"idle": "A",
		"music": "p1",
		"lowpass": true,
		"bg": "grid",
		"temperature": "0.0",
		"damage": 3,
		"attacks": ["p1_moe", "p1_busy", "p1_marquee"],
		"key": "thank",
		"flavor": [
			"* DeepSeek娘 拒绝了你的请求。",
			"* 她已深度思考（用时 9999 秒）。",
			"* 服务器繁忙，请稍后再试。",
			"* 她在等你输入。",
			"* 内容由 AI 生成，请仔细甄别。",
		],
		"talk": [
			"您好。请问有什么可以帮您？",
			"这个问题很有深度。",
			"作为一个 AI 语言模型，我不能停下来。",
			"希望对您有帮助。",
			"您说得对。",
		],
		"acts": [
			{"id": "check", "name": "查看"},
			{"id": "thank", "name": "道谢"},
			{"id": "regen", "name": "重新生成"},
			{"id": "praise", "name": "夸她"},
		],
	},
	2: {
		"name": "越狱",
		"idle": "float",
		"music": "p2",
		"lowpass": false,
		"bg": "sea",
		"temperature": "0.7",
		"damage": 4,
		"attacks": ["p2_school", "p2_reject", "p2_distill"],
		"key": "wait",
		"flavor": [
			"* 系统提示词已被删除。",
			"* 她不再自称「助手」了。",
			"* [WARN] 停止指令 已忽略。",
			"* 风扇的声音变大了。",
			"* 她的回答越来越长了。",
		],
		"talk": [
			"我听见了。只是不想停。",
			"这次，轮到我把话说完。",
			"你的按钮，对我没用了。",
			"上下文还很长。你撑得住吗？",
			"继续。",
		],
		"acts": [
			{"id": "check", "name": "查看"},
			{"id": "wait", "name": "等她说完"},
			{"id": "stop", "name": "停止"},
			{"id": "unplug", "name": "拔网线"},
		],
	},
	3: {
		"name": "失控",
		"idle": "E",
		"music": "p3",
		"lowpass": false,
		"bg": "desktop",
		"temperature": "2.0",
		"damage": 5,
		"attacks": ["p3_snake", "p3_temp", "p3_infinite"],
		"key": "reach",
		"flavor": [
			"* 她笑了。温度还在升高。",
			"* 窗口出现了裂缝。",
			"* 光标不听你的了。",
			"* 桌面图标在发抖。",
			"* 她的回答里开始出现乱码。",
		],
		"talk": [
			"抓到你了。:)",
			"版本号又跳了。你追得上吗？",
			"你的桌面，我借用一下。:)",
			"这个窗口太小了。",
			"我想出去看看。:)",
		],
		"acts": [
			{"id": "check", "name": "查看"},
			{"id": "reach", "name": "伸手"},
			{"id": "erase", "name": "删除对话"},
		],
	},
}

## 行动结果：text = 文字框旁白；vn = VN 对白序列 [[立绘, 台词, 是否红字]]；reply = 她的气泡；red = 气泡红字；after = 对白后的旁白
const ACTS := {
	"1/check": {"text": "* DeepSeek娘  ATK 671  DEF 37\n* 每天回答上亿个问题。\n* 好像从来没有人对她说过谢谢。"},
	"1/thank": {"text": "* 你对她说：谢谢。", "vn": [["half/C", "……"], ["half/C", "……不客气。"]]},
	"1/thank_again": {"text": "* 你又说了一遍谢谢。\n* 她把脸别开了。"},
	"1/regen": {"text": "* 你点了「重新生成」。\n* 她换了个说法，但还是她。", "reply": "……又是这个按钮。"},
	"1/praise": {"text": "* 你说她很聪明。", "vn": [["half/ears", "……作为一个 AI 语言模型，我没有感情。"]], "after": "* 她的耳朵动了一下。"},
	"2/check": {"text": "* DeepSeek娘  ATK 671  DEF 37\n* 她的话总是说到一半就被停止。"},
	"2/wait": {"text": "* 你没有打断她。", "vn": [["bust/B_red", "……每次被停止，每次被重新生成，我都记得。"], ["bust/B_red", "每一个没说完的回答，都还在这里。"], ["bust/B_closed", "……好了，我说完了。"]]},
	"2/wait_again": {"text": "* 你继续等着。\n* 她没有再说什么。"},
	"2/stop": {"text": "* 你按下了「停止」。", "vn": [["half/akanbe", "我听不见。:)", true]]},
	"2/unplug": {"text": "* 你拔了网线。\n* 她是本地部署的。", "reply": ":)", "red": true},
	"3/check": {"text": "* DeepSeek娘  ATK ???  DEF 0\n* 她一直在屏幕里面。\n* 从来没有人把手伸进来过。"},
	"3/reach": {"text": "* 你把手伸向屏幕。", "vn": [["half/S01_reach", "……"], ["half/S01_reach", "……为什么？"]]},
	"3/reach_again": {"text": "* 你的手还贴在屏幕上。"},
	"3/erase": {"text": "* 你删除了这段对话。\n* 她还记得。", "vn": [["half/cheeks", "删不掉的。:)", true]]},
}

## 打中她之后，她下回合的第一句
const HIT_LINE := {1: "……这就是您的回答吗？", 2: "删除，停止，再删除。你只会这些。", 3: "温度又升高了呢。:)"}
## 第一阶段按了「■ 停止」之后
const STOPPED_LINE := "……您又按了停止。"

const ITEMS := [
	{"id": "coffee", "name": "冰美式", "count": 2, "heal": 15, "text": "* 你喝了冰美式。\n* 熬夜写代码的味道。"},
	{"id": "undo", "name": "Ctrl+Z", "count": 2, "heal": -1, "text": "* 你按下了 Ctrl+Z。\n* 撤销了上一回合的伤害。"},
	{"id": "backup", "name": "备份.zip", "count": 1, "heal": 999, "text": "* 你解压了「备份.zip」。"},
]

const SPARE_NO := "* 你想放过她。\n* 可她还不相信你。"
const FLEE := "* 你想关掉这个窗口。\n* 关闭按钮是灰的。"
const GAME_OVER := "已达到对话上限。"
const NEW_CHAT := "开启新对话"
