extends RefCounted

## DUELOGUE — нарративный движок (narrative_engine.md). Шаблонный реализатор v0.3 шаг 1 —
## СХЕМЫ × ЗАЦЕПКИ (читабельность приёмов: §14.3–14.4, референция §14.6, биас §14.8).
## База v0.2 (модель осей) сохранена: содержание = взгляд полюса на спорную ось темы.
## Новое v0.3:
##   Тезис  → приём = СХЕМА, диктующая форму предложения целиком (не хвостик): Статистика —
##            цифровой заход, Здравый смысл — риторический вопрос, Эмоция — восклицание...
##   Разбор → атака хватает СХЕМУ цели за ЗАЦЕПКУ (критический вопрос Уолтона): зацепка
##            карты ∈ открытых зацепок схемы → HIT (хват-шаблон × объект схемы, «а цифры —
##            откуда?»), иначе MISS (generic-путь v0.2). Попадание остаётся событием (~35%).
##   Референция → счётчик упоминаний оси: полная цитата → клип по слову → тег («канон»).
##   Резолв → закрывашка ссылается на последнюю зацепку ралли («источник зал так и не услышал»).
## Fill-safe неизменен: движок НИКОГДА не склоняет вставленное. Цитаты/теги — в кавычках
## (номинативная цитата), объекты схем и мотивы — именительный в безопасной позиции.

const TYPE_TEZIS := "T"
const TYPE_RAZBOR := "R"
const TYPE_USTANOVKA := "U"

# Имя карты модели → приём (манера). Имена из zal_v3_model.gd / deck.gd.
const TEZIS_DEV := {
	"Довод": "Здравый смысл", "Контрфакт": "Статистика", "Аргумент": "Определение",
	"Уточнение": "Аналогия", "Пример": "Пример", "Ссылка": "Авторитет",
	"Факт": "Традиция", "Логика": "Эмоция",
}
const RAZBOR_DEV := {
	"Не в кассу": "Не в кассу", "Передёрг": "Передёрг", "Контрпример": "Контрпример",
	"Софизм?": "До абсурда", "Источник?": "Источник?", "Подмена": "Корреляция",
	"Мимо": "Ложная аналогия", "А докажи": "Источник?",
}
const KRAJA_DEV := ["Разворот", "Та же логика"]

const SUBSTANTIVE := ["Контрпример", "До абсурда", "Ложная аналогия"]  # MISS содержанием (opp-взгляд)
const PROCEDURAL := ["Источник?", "Передёрг", "Не в кассу", "Корреляция"]  # MISS придиркой к тексту

# --- Онтология схем (§14.3, §15.3) — скелет, пишется один раз, тема-независим ---

# Схема → апелляция. Биас выбора оси (§14.8): приём предпочитает ось своей апелляции —
# уходят мисматчи «Статистика без цифр» / «Традиция на анти-традиционном взгляде».
const DEV_APPEAL := {
	"Пример": "logos", "Авторитет": "ethos", "Статистика": "logos", "Аналогия": "logos",
	"Здравый смысл": "ethos", "Эмоция": "pathos", "Определение": "logos", "Традиция": "ethos",
}
# Схема → ОБЪЕКТ: уязвимое слово формы (именительный; вставляется без склонения).
const SCHEME_OBJ := {
	"Авторитет": "эксперты", "Статистика": "цифры", "Пример": "пример", "Аналогия": "сравнение",
	"Традиция": "традиция", "Здравый смысл": "очевидность", "Эмоция": "чувства", "Определение": "термин",
}
# Карта атаки → зацепка (за что она хватает схему цели). Кража — не зацепка, а присвоение.
const HOOK_OF := {
	"Источник?": "источник", "Контрпример": "исключение", "Ложная аналогия": "сходство",
	"До абсурда": "следствие", "Передёрг": "подмена", "Корреляция": "связь",
	"Не в кассу": "уместность",
}
# Схема → открытые зацепки (какие критические вопросы её берут). HIT ≈ 20 пар из 56.
const OPEN_HOOKS := {
	"Авторитет": ["источник", "уместность", "исключение"],
	"Статистика": ["источник", "связь", "исключение"],
	"Пример": ["исключение", "источник", "сходство"],
	"Аналогия": ["сходство", "исключение"],
	"Традиция": ["следствие", "уместность"],
	"Здравый смысл": ["источник", "следствие"],
	"Эмоция": ["уместность", "подмена"],
	"Определение": ["подмена", "следствие", "источник"],
}
# Зацепки, бьющие СОДЕРЖАНИЕМ (несут контр-взгляд {o} на ту же ось); остальные — процедурные.
const SUB_HOOKS := ["исключение", "сходство", "следствие"]

# Тезис: СХЕМА диктует форму предложения целиком. FILL-SAFE: {t} — целая фраза на границе
# предложения; {x} — мотив в именительно-безопасной позиции (приложение / «как …»).
const TEZIS_PAT := {
	"Пример": [
		"{m}{t}. Живой пример — {x}.",
		"{m}{t} — да вот хоть {x}, например.",
		"{m}пример на поверхности: {x}. {t}.",
	],
	"Авторитет": [
		"{m}спроси любого, кто в теме: {t}.",
		"{m}люди, съевшие на этом собаку, говорят одно: {t}.",
		"{m}{t} — это консенсус знающих, не моя прихоть.",
	],
	"Статистика": [
		"{m}девять из десяти скажут: {t}.",
		"{m}посчитай сам — выйдет одно: {t}.",
		"{m}{t}, и статистика тут беспощадна.",
	],
	"Аналогия": [
		"{m}это как {x}: {t}.",
		"{m}{t} — параллель напрашивается сама.",
	],
	"Здравый смысл": [
		"{m}ну кто в здравом уме поспорит, что {t}?",
		"{m}да ты и сам знаешь: {t}.",
		"{m}это же очевидно: {t}.",
	],
	"Эмоция": [
		"{m}{t} — и у меня от этого всё кипит!",
		"{m}да пойми же наконец: {t}!",
	],
	"Определение": [
		"{m}по определению: {t}.",
		"{m}назовём вещи своими именами: {t}.",
	],
	"Традиция": [
		"{m}{t} — не нами заведено, не нам отменять.",
		"{m}так было всегда: {t}.",
		"{m}{t} — это проверено поколениями.",
	],
}

# HIT: зацепка попала в открытую уязвимость схемы цели. Один хват-шаблон × объект схемы →
# 7×8 различимых звучаний из ~15 деклараций (факторизация §15.3): «а эксперты — откуда?» vs
# «а цифры — откуда?» — один шаблон. Пустые слоты гасят вариант: {tag} — только если у оси
# есть тег; {g} — якорь-референция на чужой довод (без якоря хват повисал в воздухе);
# {stag} — тег СТАЗИСА ралли, заполняется только когда цель УШЛА с оси раунда (§15.4):
# «мы вообще-то про канон» имеет право звучать лишь по уклонившейся защите.
const HOOK_PAT := {
	"источник": [
		"{m}{g}? А {obj} — откуда, собственно?",
		"{m}{obj}, значит. А источник где?",
	],
	"исключение": [
		"{m}{g}? {obj} — ещё не правило. Как раз наоборот: {o}.",
		"{m}а исключения? Их полно: {o}.",
	],
	"сходство": [
		"{m}{g}? Похоже, да не то: {o}.",
		"{m}{obj} хромает: {x} — это не «{tag}». {o}.",
	],
	"следствие": [
		"{m}{g}? Скользкая дорожка: тогда и {x} завтра — норма. {o}.",
		"{m}доведи до конца — и абсурд: выходит, {x} — тоже норма. {o}.",
	],
	"подмена": [
		"{m}{g} — а это подмена: разговор был не о том.",
		"{m}не жонглируй: {g} — это передёрг, а не довод.",
	],
	"связь": [
		"{m}{g}? {obj} отдельно, вывод отдельно. Где связь?",
		"{m}совпало — не значит связано. Покажи связь.",
	],
	"уместность": [
		"{m}мы вообще-то про «{stag}» — {obj} тут при чём?",
		"{m}а {obj} тут при чём? Спор про «{stag}», не о том.",
		"{m}{obj} — это трогательно, но мимо кассы.",
		"{m}{obj} — не аргумент, уж извини.",
	],
}
# ПАНЧИ (регистр 3, аччелерандо §14.5): третий+ удар ралли — аффект, не телеграмма.
# Не «сокращение реплики», а ЭМОЦИЯ: частицы («-то», «же»), удвоение, якорь на объект схемы —
# чтобы выкрик оставался в контексте обмена, а не висел вырванным.
const HOOK_PUNCH := {
	"источник": ["Да где {obj}-то?!", "Ну и где {obj}?!"],
	"исключение": ["А исключения?! То-то же!", "Полно обратного! Полно!"],
	"сходство": ["Да не похоже ни капли!", "Ну и сравнение!"],
	"следствие": ["И докуда так дойдём?!", "Дальше — только абсурд!"],
	"подмена": ["Опять подмена!", "Снова слова крутишь!"],
	"связь": ["Да где связь-то?!", "Связи — ноль!"],
	"уместность": ["Мы не об этом!", "Да не о том речь!"],
}
const MISS_PUNCH := {
	"Источник?": ["Пруфы! Пруфы где?!", "Да кто это сказал-то?!"],
	"Контрпример": ["Да всё наоборот!", "Наоборот же!"],
	"До абсурда": ["Это же абсурд!", "Бред же выходит!"],
	"Ложная аналогия": ["Ну и сравнил!", "Мимо! Совсем мимо!"],
	"Передёрг": ["Я такого не говорил!", "Не приписывай мне!"],
	"Не в кассу": ["Да при чём тут это!", "Не туда! Совсем не туда!"],
	"Корреляция": ["Одно к другому не липнет!", "Да не связано это!"],
}
const KRAJA_PUNCH := ["Спасибо — забираю!", "А это теперь моё!", "Мой довод! Мой!"]
# Панч защиты — отдельным предложением после взгляда (усталость/упрямство, не телеграф).
const HOLD_PUNCH := ["И точка!", "Сколько можно повторять?!", "И хоть ты тресни!"]
# Закрывашка резолва — ссылка на последнюю зацепку ралли (роль «закрытие» словаря §15.2).
const HOOK_CLOSE := {
	"источник": "Источник зал так и не услышал.",
	"исключение": "Крыть исключения оказалось нечем.",
	"сходство": "Сравнение так и осталось хромым.",
	"следствие": "Со скользкой дорожки так и не свернули.",
	"подмена": "Подмену зал запомнил.",
	"связь": "Связь так и не показали.",
	"уместность": "К сути так и не вернулись.",
}
const HOOK_CLOSE_HELD := [
	"На каждый выпад нашёлся довод — зал это оценил.",
	"Вопросы сыпались — ответы находились.",
	"Допрос не удался: защита не дрогнула.",
]

# Разбор MISS содержательный: рефьютит чужой взгляд {g} своим противоположным {o} (мотив {x}).
# {g} приходит из референции УЖЕ в кавычках (цитата/клип/тег) — паттерны кавычек не добавляют.
const RAZBOR_SUB := {
	"Контрпример": ["{m}да какой там {g} — {o}.", "{m}{g}? Как раз наоборот: {o}."],
	"До абсурда": ["{m}если {g}, то и {x} под запрет. На деле {o}.", "{m}{g} — доведи до конца, и абсурд: {o}."],
	"Ложная аналогия": ["{m}{g}? Сравнение хромает. По факту {o}.", "{m}{g}? Мимо. {o}."],
}
# Разбор MISS процедурный: придирка к тексту чужого довода {g} (содержание оси не нужно).
# «Не в кассу» с обвинением в уходе от темы гейтится стазисом ({stag}): по доводу, стоящему
# ровно на теме раунда, звучит только пренебрежение («спора не решает»), не ложное «не по теме».
const RAZBOR_PROC := {
	"Источник?": ["{m}{g}? Пруфы где? Назови хоть один.", "{m}а кто это сказал: {g}? Источник."],
	"Передёрг": ["{m}я не говорил {g} — ты передёрнул.", "{m}{g} — это твоя выдумка за меня, не лепи."],
	"Не в кассу": ["{m}при чём тут {g}? Мы про «{stag}».", "{m}{g} — и что? Спора это не решает.", "{m}{g} — слабо. Нас это никуда не ведёт."],
	"Корреляция": ["{m}{g}? Совпало — не значит следствие.", "{m}из {g} такой вывод не вытекает."],
}
# Кража: разворот оси — чужой взгляд {g} как довод за себя {o}.
const KRAJA_PAT := {
	"Разворот": ["{m}{g}? Так это же довод ЗА меня: {o}.", "{m}спасибо за {g} — отсюда ровно и следует: {o}."],
	"Та же логика": ["{m}по твоей же логике из {g} выходит: {o}. Беру.", "{m}{g}? Тем же ходом: {o}. Моё."],
}
const MARK := {
	"open": ["Объявляю: ", "Вот моя позиция: ", "Заявляю прямо: "],
	"assert": ["И вообще, ", "Более того, ", "Добавлю. ", ""],
	"refute": ["Да брось. ", "Секунду. ", "Стоп. "],
	"callback": ["Кстати, вернёмся к старому — ", "А, и про то, что ты раньше задвигал: "],
	"hold": ["Стоп-стоп. ", "Ну уж нет. ", "Это ничего не отменяет. "],
	"press": ["И добиваю: ", "Мало! ", "Дальше — "],
	"scramble": ["Так, момент теряю, но: ", "Хорошо-хорошо, но: "],
}
# Защита при ВИСЯЩЕЙ зацепке (в ралли уже прозвучал критический вопрос): уклонение слышно,
# но подаётся как легитимный пивот, не как оправдание (§15.6-Q2, dispreferred response).
# Самостоятельные предложения: формы тезисов несут свой зачин, клауза-связка с ними стакается.
const EVADE_MARK := ["Вопрос слышал. ", "Не в этом дело. ", "Отвечу о главном. "]
# Повторное утверждение уже звучавшей оси (та же сторона): честное «я повторяюсь» вместо
# роботского «Добавлю.» перед дословно той же мыслью.
const REPEAT_MARK := ["Повторю. ", "Ещё раз, по слогам. ", "Я это уже говорил. ", "Снова скажу. "]
# Эндшпиль (§14.7): исход решает зал — тезисы подаются как апелляция к публике.
const END_ASSERT_MARK := ["Судите сами. ", "Зал, решай. ", "Финальный довод. "]
# Резолв ралли — вариативные пулы (анти-повтор _pick).
const RES_REMOVED := [
	"Зал загудел: позиция «%s» рухнула — защищать нечем.",
	"Всё: «%s» снята с доски — крыть было нечем.",
	"Позиция «%s» рассыпалась на глазах у зала.",
]
const RES_SHAKEN := [
	"Довод снят, рамка «%s» зашаталась.",
	"Минус довод: «%s» держится на честном слове.",
	"Укол прошёл — «%s» просела.",
]
const RES_HELD := [
	"Рамка «%s» устояла и только окрепла — зал кивает.",
	"«%s» выдержала натиск — зал одобрительно гудит.",
	"Атака захлебнулась: «%s» стоит как стояла.",
]
## Крен зала, с которого меняется темп речи: отстающий нервно-коротко (+1 к регистру),
## фаворит вальяжно (−1). Порог в тезисах-очках zal() (ZAL_MAX=10 в card_types).
const ZAL_SWAY := 4
const PHASE_END := 0.66

var theme: Dictionary
var stance_of := {"you": "contra", "opp": "pro"}
var _axis_by_id := {}
var _recent_motifs: Array = []
var _headline_ptr := {"you": 0, "opp": 0}
var _kraja_i := 0
## Референция (§14.6): сколько раз ось уже цитировали ссылкой → цитата/клип/тег.
var _axis_seen := {}
## Какие оси сторона уже УТВЕРЖДАЛА (Statement): повторное утверждение честно помечается
## («Я это уже говорил:»), а выбор оси предпочитает ещё не звучавшие от этой стороны.
var _asserted := {"you": {}, "opp": {}}
## Состояние ралли (клинча): стазис = ось изначально атакованного довода (тема раунда, §15.4),
## последняя зацепка (для закрывашки и уклонений), счётчики реплик (аччелерандо §14.5).
## Открывается refute_line, чистится resolve_text.
var _rally := {}
## Накал извне (драйвер зовёт update_heat раз в ход): крен зала (+ к «you») и фаза колоды 0..1.
var _zal := 0
var _phase := 0.0
## Анти-повтор: последний выбранный индекс по каждому пулу шаблонов (ключ — hash пула).
var _last_pick := {}
## Стейт-реакция ГОВОРЯЩЕГО для ядра персонажа (контракт §16 narrative_engine.md):
## вычисляется вместе с текстом реплики из того же, из чего собирается сама реплика
## (акт × регистр × зал × попадание). Контроллер читает last_mood() сразу после сборки
## строки и везёт в meta реплики. Словарь: declare / swagger / panic / hold / evade /
## attack / gotcha / burst / idle (stagger — событийный, его ставит контроллер по исходу).
var _mood := "declare"
var rng := RandomNumberGenerator.new()


func last_mood() -> String:
	return _mood


func start(p_theme: Dictionary, seed: int, p_stance: Dictionary = {}) -> void:
	theme = p_theme
	if not p_stance.is_empty():
		stance_of = p_stance
	_axis_by_id = {}
	for ax in theme.axes:
		_axis_by_id[ax.id] = ax
	_recent_motifs = []
	_headline_ptr = {"you": 0, "opp": 0}
	_kraja_i = 0
	_axis_seen = {}
	_asserted = {"you": {}, "opp": {}}
	_rally = {}
	_zal = 0
	_phase = 0.0
	_last_pick = {}
	_mood = "declare"
	rng.seed = seed


## Драйвер (контроллер/смок) сообщает накал раз в ход: zal — крен зала (+ в пользу «you»),
## phase — израсходованная доля добора 0..1. Не звался — движок работает нейтрально.
func update_heat(zal: int, phase: float) -> void:
	_zal = zal
	_phase = clampf(phase, 0.0, 1.0)


## Регистр реплики в ралли (§14.5): base — номер реплики стороны в ралли (1-й полный,
## 2-й короткий, 3-й+ панч); отстающий по залу торопится (+1), фаворит вальяжен (−1).
func _tier(base: int, side: String) -> int:
	var adverse := -_zal if side == "you" else _zal
	var bump := 0
	if adverse >= ZAL_SWAY:
		bump = 1
	elif adverse <= -ZAL_SWAY:
		bump = -1
	return clampi(base + bump, 1, 3)


func topic() -> String:
	return theme.topic


func stance_label(side: String) -> String:
	return theme.stances[_pole(side)].label


## Следующая широкая позиция стойки (для Установки / стартовой рамки).
func next_headline(side: String) -> String:
	var pool: Array = theme.stances[_pole(side)].headlines
	var i: int = _headline_ptr[side]
	_headline_ptr[side] = i + 1
	return pool[i % pool.size()]


func device_for(card: Dictionary) -> String:
	match String(card.get("type", "")):
		TYPE_USTANOVKA: return "Установка"
		TYPE_TEZIS: return TEZIS_DEV.get(String(card.get("name", "")), "Пример")
		TYPE_RAZBOR:
			if bool(card.get("steals", false)):
				var d: String = KRAJA_DEV[_kraja_i % KRAJA_DEV.size()]
				_kraja_i += 1
				return d
			return RAZBOR_DEV.get(String(card.get("name", "")), "Контрпример")
	return "Пример"


## Приём карты для ДИСПЛЕЯ (лицо карты в руке). ЧИСТАЯ: не крутит _kraja_i, как device_for.
## Для кражи приём выбирается детерминированно по имени, чтобы ярлык не мерцал на _refresh.
func device_label(card: Dictionary) -> String:
	match String(card.get("type", "")):
		TYPE_USTANOVKA: return "Установка"
		TYPE_TEZIS: return TEZIS_DEV.get(String(card.get("name", "")), "Пример")
		TYPE_RAZBOR:
			if bool(card.get("steals", false)):
				return KRAJA_DEV[abs(hash(String(card.get("name", "")))) % KRAJA_DEV.size()]
			return RAZBOR_DEV.get(String(card.get("name", "")), "Контрпример")
	return "Пример"


## Превью реплики карты для её лица в руке. ЧИСТАЯ: не трогает rng/_recent_motifs/
## _headline_ptr/_kraja_i/_axis_seen — текст представительный, при розыгрыше катается заново.
## Детерминирована по личности карты, чтобы не мерцать на _refresh. Карта атаки показывает
## свой ФИРМЕННЫЙ хват (HIT на типовой уязвимой схеме) — приём читается прямо в руке.
func preview_text(side: String, card: Dictionary) -> String:
	if theme.is_empty():
		return ""
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("%s|%s|%s" % [card.get("type", ""), card.get("name", ""), card.get("steals", false)])
	var pole := _pole(side)
	var dev := device_label(card)
	match String(card.get("type", "")):
		TYPE_USTANOVKA:
			var pool: Array = theme.stances[pole].headlines
			return _cap(_mark_at("open", prng) + String(pool[prng.randi() % pool.size()]) + ".")
		TYPE_TEZIS:
			var axis: Dictionary = _axis_for_appeal(String(DEV_APPEAL.get(dev, "")), prng)
			var take := String(axis[pole])
			var motif := _motif_pure(axis, prng)
			return _cap(_fill(_pick_at(TEZIS_PAT.get(dev, TEZIS_PAT["Пример"]), prng),
				{"m": _mark_at("assert", prng), "t": take, "x": motif}))
		TYPE_RAZBOR:
			# Реактивна к цели — для превью берём типовой чужой довод (взгляд другого полюса).
			var axis: Dictionary = theme.axes[prng.randi() % theme.axes.size()]
			var gist := String(axis[_other_pole(pole)])
			var reps := {"m": _mark_at("refute", prng), "g": "«%s»" % gist, "o": String(axis[pole]),
				"x": _motif_pure(axis, prng), "c": "", "obj": "", "tag": String(axis.get("tag", ""))}
			if bool(card.get("steals", false)):
				return _cap(_fill(_pick_at(KRAJA_PAT.get(dev, KRAJA_PAT["Разворот"]), prng), reps))
			var hook := String(HOOK_OF.get(dev, ""))
			if hook != "":
				reps.obj = SCHEME_OBJ.get(_typical_scheme_for(hook), "довод")
				return _cap(_fill(_pick_at(_gated(HOOK_PAT.get(hook, []), reps), prng), reps))
			if SUBSTANTIVE.has(dev):
				return _cap(_fill(_pick_at(RAZBOR_SUB.get(dev, RAZBOR_SUB["Контрпример"]), prng), reps))
			return _cap(_fill(_pick_at(RAZBOR_PROC.get(dev, RAZBOR_PROC["Источник?"]), prng), reps))
	return ""


## Тезис: взгляд своего полюса на свежую ось (с биасом апелляции приёма, §14.8).
## used_axes — id осей, уже звучавших на рамке.
## Регистры защиты в ралли (mark_kind=="hold"): 1-я полная форма, 2-я — голый взгляд,
## 3-я+ — панч; при висящей зацепке полная форма получает маркер-уклонение (§15.6-Q2).
## Возвращает {axis, pole, device, motif, gist, text}; gist = текст взгляда (для ссылок).
func make_statement(side: String, card: Dictionary, used_axes: Array, mark_kind: String = "assert") -> Dictionary:
	var dev := device_for(card)
	var heard: Dictionary = _asserted[side]
	var axis := _pick_axis(used_axes, String(DEV_APPEAL.get(dev, "")), heard)
	var axis_id := String(axis.id)
	var repeated := heard.has(axis_id)
	heard[axis_id] = int(heard.get(axis_id, 0)) + 1
	var pole := _pole(side)
	var take := String(axis[pole])
	var motif := _axis_motif(axis, take)
	var text: String
	if mark_kind == "hold" and not _rally.is_empty():
		_rally.holds = int(_rally.get("holds", 0)) + 1
		var evading := String(_rally.get("hook", "")) != ""
		match _tier(int(_rally.holds), side):
			3:
				_mood = "burst"
				text = _cap("%s. %s" % [take, _pick(HOLD_PUNCH)])
			2:
				_mood = "evade" if evading else "hold"
				text = _cap(take + ".")
			_:
				_mood = "evade" if evading else "hold"
				var mk := _pick(EVADE_MARK) if evading else _mark(mark_kind)
				text = _cap(_fill(_pick(TEZIS_PAT.get(dev, TEZIS_PAT["Пример"])), {"m": mk, "t": take, "x": motif}))
	else:
		var adverse := -_zal if side == "you" else _zal
		if adverse >= ZAL_SWAY:
			_mood = "panic"
		elif adverse <= -ZAL_SWAY:
			_mood = "swagger"
		else:
			_mood = "declare"
		var mk: String
		if repeated:
			mk = _pick(REPEAT_MARK)  # та же мысль уже звучала — говорим это честно
		elif mark_kind == "assert" and _phase >= PHASE_END:
			mk = _pick(END_ASSERT_MARK)
		else:
			mk = _mark(mark_kind)
		text = _cap(_fill(_pick(TEZIS_PAT.get(dev, TEZIS_PAT["Пример"])), {"m": mk, "t": take, "x": motif}))
	return {"axis": axis.id, "pole": pole, "device": dev, "motif": motif, "gist": take, "text": text}


func open_line(side: String, headline: String, mark_kind: String = "open") -> String:
	_mood = "panic" if mark_kind == "scramble" else "declare"
	return _cap(_mark(mark_kind) + headline + ".")


func redeploy_line(side: String, headline: String) -> String:
	return open_line(side, headline, "scramble")


const PASS_LEAD := [
	"…(выразительно молчит и обводит зал взглядом)",
	"…(разводит руками — мол, добавить нечего)",
	"…(демонстративно уступает трибуну)",
]
const PASS_LOSE := [
	"…(мнётся — крыть нечем)",
	"…(тянет паузу, но слов не находит)",
]
const PASS_NEUTRAL := ["…(молчит — сказать нечего)", "…(пауза)"]


## Пас. Ведущий зал молчит ВЫРАЗИТЕЛЬНО (психатака §13-Д3а), отстающий — вынужденно.
func pass_line(side: String) -> String:
	var adverse := -_zal if side == "you" else _zal
	if adverse <= -2:
		_mood = "swagger"
		return _pick(PASS_LEAD)
	if adverse >= 2:
		_mood = "panic"
		return _pick(PASS_LOSE)
	_mood = "idle"
	return _pick(PASS_NEUTRAL)


## Атака по чужому доводу target_stmt (его ось/взгляд/схема). is_callback — рамка старая
## (закрытая). ОТКРЫВАЕТ ралли: ось цели становится СТАЗИСОМ (темой раунда, §15.4).
func refute_line(attacker: String, target_claim: String, target_stmt: Dictionary, card: Dictionary, is_callback: bool) -> String:
	var st_axis := ""
	var st_tag := ""
	if target_stmt.has("axis") and _axis_by_id.has(target_stmt.axis):
		st_axis = String(target_stmt.axis)
		st_tag = String((_axis_by_id[st_axis] as Dictionary).get("tag", ""))
	elif target_claim != "":
		# Голая рамка: стазис ралли — сама позиция (headline); ссылка — клип по слову.
		st_tag = _clip(target_claim, 24)
	_rally = {"stasis_axis": st_axis, "stasis_tag": st_tag, "hook": "", "obj": "",
		"presses": 1, "holds": 0}
	var mk := _mark("callback") if is_callback else _mark("refute")
	return _attack_line(attacker, target_claim, target_stmt, card, mk, 1)


## Добив в клинче — по только что выложенному защитному доводу. Аччелерандо: 2-й удар
## короткий, 3-й+ панч (сдвиг от крена зала — отстающий торопится, фаворит вальяжен).
func press_line(attacker: String, target_stmt: Dictionary, card: Dictionary) -> String:
	if _rally.is_empty():
		return _attack_line(attacker, "", target_stmt, card, _mark("press"), 1)
	_rally.presses = int(_rally.get("presses", 1)) + 1
	return _attack_line(attacker, "", target_stmt, card, _mark("press"), _tier(int(_rally.presses), attacker))


## Итог клинча — голос зала. Если в ралли была зацепка (HIT) — закрытие ссылается на неё:
## снос → «вопрос остался без ответа», устояла → «на каждый выпад нашёлся довод».
func resolve_text(landed: bool, removed: bool, claim: String, stolen: int, def_held: bool) -> String:
	var s := ""
	if landed:
		s = _pick(RES_REMOVED if removed else RES_SHAKEN) % claim
		if stolen > 0:
			s += " (перехвачено себе: %d)" % stolen
		var hook := String(_rally.get("hook", ""))
		if HOOK_CLOSE.has(hook):
			s += " " + String(HOOK_CLOSE[hook])
	else:
		s = _pick(RES_HELD) % claim
		if String(_rally.get("hook", "")) != "":
			s += " " + _pick(HOOK_CLOSE_HELD)
	_rally = {}
	return s


func verdict_text(winner_side: String, reason: String, you_label: String, opp_label: String) -> String:
	var tail := ""
	match reason:
		"knockout": tail = "нокаут — оппоненту нечем крыть"
		"crowd": tail = "зал уведён — овация, проигравшего уже не слушают"
		"decision": tail = "решение по залу"
		"draw": tail = "зал замер ровно"
	if winner_side == "":
		return "Зал расходится в раздумьях. Ничья (%s)." % tail
	var w := you_label if winner_side == "you" else opp_label
	return "Зал на стороне «%s». Победа (%s)." % [w, tail]


# --- внутреннее ---

func _pole(side: String) -> String:
	return stance_of[side]


## Общая сборка атаки. Порядок резолва (§14.4): Кража → HIT (зацепка карты ∈ открытых зацепок
## схемы цели) → MISS содержательный/процедурный. HIT хватает за объект схемы и запоминается
## в ралли для закрывашки/уклонений. gist приходит через референцию (цитата → клип → тег).
## tier — регистр §14.5: 1 полный, 2 короткий (без маркера, сжатая референция), 3 панч.
func _attack_line(attacker: String, target_claim: String, target_stmt: Dictionary, card: Dictionary, mk: String, tier: int = 1) -> String:
	var dev := device_for(card)
	var pole := _pole(attacker)
	var axis: Dictionary
	var counted := false
	var gist: String
	if target_stmt.has("axis") and _axis_by_id.has(target_stmt.axis):
		axis = _axis_by_id[target_stmt.axis]
		counted = true
		gist = String(target_stmt.get("gist", ""))
	else:
		axis = _pick_axis([])
		gist = target_claim if target_claim != "" else String(axis[_other_pole(pole)])
	var steals := bool(card.get("steals", false))
	var hook := String(HOOK_OF.get(dev, ""))
	var scheme := String(target_stmt.get("device", ""))
	var is_hit := not steals and hook != "" and scheme != "" and (OPEN_HOOKS.get(scheme, []) as Array).has(hook)
	if is_hit:
		_rally.hook = hook
		_rally.obj = String(SCHEME_OBJ.get(scheme, "довод"))
	# Стейт говорящего: панч — вспышка; кража и попадание в зацепку — «подловил»; иначе атака.
	if tier >= 3:
		_mood = "burst"
	elif steals or is_hit:
		_mood = "gotcha"
	else:
		_mood = "attack"
	# Панч: аффект-выкрик без цитаты (референцию не тратим — ось зримо не упоминается).
	if tier >= 3:
		if steals:
			return _pick(KRAJA_PUNCH)
		if is_hit:
			var obj := String(SCHEME_OBJ.get(scheme, "довод"))
			return _fill(_pick(HOOK_PUNCH.get(hook, ["Мимо!"])), {"obj": obj})
		return _pick(MISS_PUNCH.get(dev, ["Мимо!"]))
	if tier == 2:
		mk = ""
	var opp_take := String(axis[pole])
	var motif := _axis_motif(axis, gist + " " + opp_take)
	var tag := String(axis.get("tag", ""))
	# Стазис (§15.4): «мы вообще-то про X» законно только если цель УШЛА с темы раунда
	# (ось изначально атакованного довода либо сама рамка при голом headline).
	var stag := ""
	if not _rally.is_empty() and counted:
		if String(_rally.get("stasis_axis", "")) != String(axis.get("id", "")):
			stag = String(_rally.get("stasis_tag", ""))
	var reps := {"m": mk, "g": _ref(axis if counted else {}, gist, tier - 1), "o": opp_take,
		"x": motif, "c": target_claim, "obj": String(SCHEME_OBJ.get(scheme, "довод")),
		"tag": tag, "stag": stag}
	if steals:
		return _cap(_fill(_pick(_gated(KRAJA_PAT.get(dev, KRAJA_PAT["Разворот"]), reps)), reps))
	if is_hit:
		return _cap(_fill(_pick(_gated(HOOK_PAT.get(hook, []), reps)), reps))
	if SUBSTANTIVE.has(dev):
		return _cap(_fill(_pick(_gated(RAZBOR_SUB.get(dev, RAZBOR_SUB["Контрпример"]), reps)), reps))
	return _cap(_fill(_pick(_gated(RAZBOR_PROC.get(dev, RAZBOR_PROC["Источник?"]), reps)), reps))


## Референция на чужой довод (§14.6): 1-е упоминание оси — полная цитата, 2-е — клип по
## границе слова, дальше — тег оси («канон»). Значение всегда в кавычках — номинативная
## цитата, паттерны кавычек не добавляют и ничего не склоняют.
## min_tier поджимает ссылку принудительно (короткий регистр говорит короче истории).
func _ref(axis: Dictionary, gist: String, min_tier: int = 0) -> String:
	if axis.is_empty():
		return "«%s»" % gist
	var id := String(axis.get("id", ""))
	var n := int(_axis_seen.get(id, 0))
	_axis_seen[id] = n + 1
	n = maxi(n, min_tier)
	var tag := String(axis.get("tag", ""))
	if n >= 2 and tag != "":
		return "«%s»" % tag
	if n >= 1:
		return "«%s»" % _clip(gist, 30)
	return "«%s»" % gist


## Грубая основа слова для сравнения «мотив уже звучит в тексте»: хвостовые гласные долой
## («мясо»→«мяс» ловит «мяса»/«мясом»). Достаточно для анти-эха, морфологии не претендует.
func _stem(s: String) -> String:
	var out := s.to_lower()
	while out.length() > 3 and out[out.length() - 1] in ["а", "о", "у", "ы", "э", "я", "ё", "ю", "и", "е", "ь", "й"]:
		out = out.substr(0, out.length() - 1)
	return out


## Клип цитаты по границе слова (+«…»). Короткие цитаты не трогаем; висячую пунктуацию
## и оборванные служебные слова на срезе убираем («…— это…» → «…»).
const _CLIP_STOP := ["это", "и", "а", "но", "не", "в", "на", "с", "по", "за", "или", "же", "то", "у", "к", "о"]

func _clip(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	var cut := s.substr(0, max_len)
	var sp := cut.rfind(" ")
	if sp > 8:
		cut = cut.substr(0, sp)
	var done := false
	while not done:
		done = true
		while cut.length() > 0 and cut[cut.length() - 1] in [" ", "—", "-", ",", ":", ";"]:
			cut = cut.substr(0, cut.length() - 1)
			done = false
		var last_sp := cut.rfind(" ")
		if last_sp > 8 and _CLIP_STOP.has(cut.substr(last_sp + 1).to_lower()):
			cut = cut.substr(0, last_sp)
			done = false
	return cut + "…"


## Гейт вариантов пула: шаблон допустим, только если все его контекстные слоты
## ({tag} — тег оси, {stag} — стазис при уходе цели с темы) заполнены. Пустой слот гасит вариант.
func _gated(pats: Array, reps: Dictionary) -> Array:
	var ok: Array = pats.filter(func(p):
		for k in ["tag", "stag"]:
			if String(p).contains("{" + k + "}") and String(reps.get(k, "")) == "":
				return false
		return true)
	return ok if not ok.is_empty() else pats


## Типовая уязвимая схема для зацепки (для превью лица карты): где зацепка стоит первой.
func _typical_scheme_for(hook: String) -> String:
	for scheme in OPEN_HOOKS:
		if String((OPEN_HOOKS[scheme] as Array)[0]) == hook:
			return scheme
	for scheme in OPEN_HOOKS:
		if (OPEN_HOOKS[scheme] as Array).has(hook):
			return scheme
	return ""


func _other_pole(pole: String) -> String:
	return "pro" if pole == "contra" else "contra"


## Свежая ось с биасом апелляции (§14.8): среди свежих предпочитаем оси апелляции приёма;
## нет подходящих — любая свежая; осей нет — любая. Ось без поля appeal матчится со всеми.
## heard — оси, уже утверждённые этой стороной за матч: неслыханные в приоритете
## (разброс по темам вместо дословных повторов).
func _pick_axis(used_ids: Array, appeal: String = "", heard: Dictionary = {}) -> Dictionary:
	var axes: Array = theme.axes
	var fresh: Array = axes.filter(func(a): return not used_ids.has(a.id))
	var src: Array = fresh if not fresh.is_empty() else axes
	if appeal != "":
		var fit: Array = src.filter(func(a): return String(a.get("appeal", "")) in ["", appeal])
		if not fit.is_empty():
			src = fit
	if not heard.is_empty():
		var unheard: Array = src.filter(func(a): return not heard.has(String(a.id)))
		if not unheard.is_empty():
			src = unheard
	return src[rng.randi() % src.size()]


## Мотив оси: СНАЧАЛА конкретика самой оси, shared-резерв — только когда её мотивы
## примелькались (абстрактный «здравый смысл» в сравнении «как …» звучит нелепо).
## avoid — текст реплики-носителя: мотив, уже звучащий в нём словами, не берём
## (эхо «миллионы фанатов… — как миллионы фанатов»).
func _axis_motif(axis: Dictionary, avoid: String = "") -> String:
	var low := avoid.to_lower()
	var ok := func(m): return not _recent_motifs.has(m) and not low.contains(_stem(String(m)))
	var own: Array = (axis.get("motifs", []) as Array).duplicate()
	var fresh: Array = own.filter(ok)
	if fresh.is_empty():
		var shared: Array = (theme.get("shared_motifs", []) as Array).duplicate()
		fresh = shared.filter(ok)
	var src: Array = fresh if not fresh.is_empty() else own
	var m: String = src[rng.randi() % src.size()]
	_recent_motifs.append(m)
	if _recent_motifs.size() > 4:
		_recent_motifs.pop_front()
	return m


## Выбор из пула с анти-повтором: тот же вариант не выпадает дважды подряд (по пулу).
func _pick(arr: Array) -> String:
	var i := rng.randi() % arr.size()
	if arr.size() > 1:
		var key := hash(arr)
		if int(_last_pick.get(key, -1)) == i:
			i = (i + 1) % arr.size()
		_last_pick[key] = i
	return String(arr[i])


# --- чистые варианты выборки (на переданном rng, без мутации состояния движка) для preview_text ---

func _pick_at(arr: Array, prng: RandomNumberGenerator) -> String:
	return String(arr[prng.randi() % arr.size()])


func _mark_at(kind: String, prng: RandomNumberGenerator) -> String:
	return _pick_at(MARK.get(kind, [""]), prng)


func _motif_pure(axis: Dictionary, prng: RandomNumberGenerator) -> String:
	var pool: Array = (axis.get("motifs", []) as Array).duplicate()
	pool.append_array(theme.shared_motifs)
	return String(pool[prng.randi() % pool.size()])


## Ось под апелляцию приёма (чистая, для превью тезиса): без учёта used_axes.
func _axis_for_appeal(appeal: String, prng: RandomNumberGenerator) -> Dictionary:
	var axes: Array = theme.axes
	if appeal != "":
		var fit: Array = axes.filter(func(a): return String(a.get("appeal", "")) in ["", appeal])
		if not fit.is_empty():
			return fit[prng.randi() % fit.size()]
	return axes[prng.randi() % axes.size()]


func _mark(kind: String) -> String:
	return _pick(MARK.get(kind, [""]))


func _fill(pat: String, reps: Dictionary) -> String:
	var s := pat
	for k in reps:
		s = s.replace("{" + k + "}", String(reps[k]))
	return s


## Заглавная в начале и после конца предложения (.!?). Кавычки/тире/скобки не сбрасывают.
func _cap(s: String) -> String:
	var out := ""
	var cap := true
	for i in s.length():
		var ch := s[i]
		if cap and ch.to_upper() != ch.to_lower():
			out += ch.to_upper()
			cap = false
		else:
			out += ch
		if ch == "." or ch == "!" or ch == "?":
			cap = true
	return out
