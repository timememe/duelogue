extends RefCounted

## DUELOGUE — нарративный движок (narrative_engine.md). Шаблонный реализатор v0.2 — МОДЕЛЬ ОСЕЙ.
## Корневая правка: приём больше НЕ содержание. Содержание = взгляд полюса на спорную ОСЬ
## (из графа темы). Приём = лишь МАНЕРА подачи. Так разбор цепляет реальный довод, а не имя
## приёма; pro/contra сталкиваются по одной оси. LLM-реализатор подключится за тем же интерфейсом.
##
## Тезис  → взгляд своего полюса на ось (take).
## Разбор → взгляд ПРОТИВОПОЛОЖНОГО полюса на ТУ ЖЕ ось (готовый контр-довод) либо
##          процедурная придирка к тексту чужого довода.
## Кража  → разворот оси: «твой довод на самом деле работает на меня».

const TYPE_TEZIS := "T"
const TYPE_RAZBOR := "R"
const TYPE_USTANOVKA := "U"

# Имя карты модели → приём (манера). Имена из zal_v3_model.gd.
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

const SUBSTANTIVE := ["Контрпример", "До абсурда", "Ложная аналогия"]  # рефьютят содержанием (opp-взгляд)
const PROCEDURAL := ["Источник?", "Передёрг", "Не в кассу", "Корреляция"]  # придираются к тексту довода

# Тезис: заявить свой взгляд {t} на ось, манера — приём. FILL-SAFE: {t} — целая фраза на
# границе предложения; {x} (мотив оси) — только именительный нос. в безопасной позиции
# (приложение «…, например» / сравнение «как …»). Движок НИКОГДА не склоняет вставленное.
const TEZIS_PAT := {
	"Пример": ["{m}{t} — да вот хоть {x}, например.", "{m}{t}. Пример? Долго искать не надо."],
	"Авторитет": ["{m}{t} — и знающие люди со мной согласны.", "{m}{t}. Это не вкусовщина, а консенсус."],
	"Статистика": ["{m}{t} — и это, между прочим, не вкусовщина, а факт.", "{m}{t}. Цифры на моей стороне."],
	"Аналогия": ["{m}{t} — ну это как {x}, по сути.", "{m}{t} — тут всё на поверхности."],
	"Здравый смысл": ["{m}{t} — это же очевидно.", "{m}да тут и спорить глупо: {t}."],
	"Эмоция": ["{m}{t}! Аж сердце щемит.", "{m}ну пойми же — {t}!"],
	"Определение": ["{m}{t} — по сути и по определению.", "{m}давай начистоту: {t}."],
	"Традиция": ["{m}{t} — так заведено веками.", "{m}испокон веков же: {t}."],
}
# Разбор содержательный: рефьютит чужой взгляд {g} своим противоположным {o} (мотив {x}).
const RAZBOR_SUB := {
	"Контрпример": ["{m}да какой там «{g}» — {o}.", "{m}«{g}»? Как раз наоборот: {o}."],
	"До абсурда": ["{m}если «{g}», то и {x} под запрет. На деле {o}.", "{m}«{g}» — доведи до конца, и абсурд: {o}."],
	"Ложная аналогия": ["{m}«{g}» — кривое сравнение. По факту {o}.", "{m}«{g}»? Мимо. {o}."],
}
# Разбор процедурный: придирка к тексту чужого довода {g} (содержание оси не нужно).
const RAZBOR_PROC := {
	"Источник?": ["{m}«{g}»? Пруфы где? Назови хоть один.", "{m}и кто сказал, что «{g}»? Source?"],
	"Передёрг": ["{m}я не говорил «{g}» — ты передёрнул.", "{m}«{g}» — это твоя выдумка за меня, не лепи."],
	"Не в кассу": ["{m}«{g}» — вообще не по теме.", "{m}при чём тут «{g}»? Уводишь разговор."],
	"Корреляция": ["{m}«{g}»? Совпало — не значит следствие.", "{m}из «{g}» такой вывод не вытекает."],
}
# Кража: разворот оси — чужой взгляд {g} как довод за себя {o}.
const KRAJA_PAT := {
	"Разворот": ["{m}«{g}»? Так это же довод ЗА меня: {o}.", "{m}спасибо за «{g}» — отсюда ровно и следует, что {o}."],
	"Та же логика": ["{m}по твоей же логике из «{g}» выходит {o}. Беру.", "{m}«{g}»? Тем же ходом: {o}. Моё."],
}
const MARK := {
	"open": ["Объявляю: ", "Вот моя позиция: ", "Заявляю прямо: "],
	"assert": ["И вообще, ", "Более того, ", "Добавлю: ", ""],
	"refute": ["Да брось. ", "Секунду. ", "Стоп. "],
	"callback": ["Кстати, вернёмся к старому — ", "А, и про то, что ты раньше задвигал: "],
	"hold": ["Стоп-стоп. ", "Ну уж нет: ", "Это не отменяет, что "],
	"press": ["И добиваю: ", "Мало! ", "Дальше — "],
	"scramble": ["Так, момент теряю, но: ", "Хорошо-хорошо, но: "],
}

var theme: Dictionary
var stance_of := {"you": "contra", "opp": "pro"}
var _axis_by_id := {}
var _recent_motifs: Array = []
var _headline_ptr := {"you": 0, "opp": 0}
var _kraja_i := 0
var rng := RandomNumberGenerator.new()


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
	rng.seed = seed


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
## _headline_ptr/_kraja_i — текст лишь представительный, при розыгрыше реплика катается заново
## (ось/мотив/цель тогда другие). Детерминирована по личности карты, чтобы не мерцать на _refresh.
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
			var axis: Dictionary = theme.axes[prng.randi() % theme.axes.size()]
			var take := String(axis[pole])
			var motif := _motif_pure(axis, prng)
			return _cap(_fill(_pick_at(TEZIS_PAT.get(dev, TEZIS_PAT["Пример"]), prng),
				{"m": _mark_at("assert", prng), "t": take, "x": motif}))
		TYPE_RAZBOR:
			# Реактивна к цели — для превью берём типовой чужой довод (взгляд другого полюса).
			var axis: Dictionary = theme.axes[prng.randi() % theme.axes.size()]
			var gist := String(axis[_other_pole(pole)])
			var reps := {"m": _mark_at("refute", prng), "g": gist, "o": String(axis[pole]),
				"x": _motif_pure(axis, prng), "c": ""}
			if bool(card.get("steals", false)):
				return _cap(_fill(_pick_at(KRAJA_PAT.get(dev, KRAJA_PAT["Разворот"]), prng), reps))
			if SUBSTANTIVE.has(dev):
				return _cap(_fill(_pick_at(RAZBOR_SUB.get(dev, RAZBOR_SUB["Контрпример"]), prng), reps))
			return _cap(_fill(_pick_at(RAZBOR_PROC.get(dev, RAZBOR_PROC["Источник?"]), prng), reps))
	return ""


## Тезис: взгляд своего полюса на свежую ось. used_axes — id осей, уже звучавших на рамке.
## Возвращает {axis, pole, device, motif, gist, text}; gist = текст взгляда (для ссылок).
func make_statement(side: String, card: Dictionary, used_axes: Array, mark_kind: String = "assert") -> Dictionary:
	var axis := _pick_axis(used_axes)
	var pole := _pole(side)
	var take := String(axis[pole])
	var dev := device_for(card)
	var motif := _axis_motif(axis)
	var text := _cap(_fill(_pick(TEZIS_PAT.get(dev, TEZIS_PAT["Пример"])), {"m": _mark(mark_kind), "t": take, "x": motif}))
	return {"axis": axis.id, "pole": pole, "device": dev, "motif": motif, "gist": take, "text": text}


func open_line(side: String, headline: String, mark_kind: String = "open") -> String:
	return _cap(_mark(mark_kind) + headline + ".")


func redeploy_line(side: String, headline: String) -> String:
	return open_line(side, headline, "scramble")


func pass_line(side: String) -> String:
	return "…(молчит — сказать нечего)"


## Атака по чужому доводу target_stmt (его ось/взгляд). is_callback — рамка старая (закрытая).
func refute_line(attacker: String, target_claim: String, target_stmt: Dictionary, card: Dictionary, is_callback: bool) -> String:
	var mk := _mark("callback") if is_callback else _mark("refute")
	return _attack_line(attacker, target_claim, target_stmt, card, mk)


## Добив в клинче — по только что выложенному защитному доводу.
func press_line(attacker: String, target_stmt: Dictionary, card: Dictionary) -> String:
	return _attack_line(attacker, "", target_stmt, card, _mark("press"))


## Итог клинча — голос зала.
func resolve_text(landed: bool, removed: bool, claim: String, stolen: int, def_held: bool) -> String:
	var s := ""
	if landed:
		if removed:
			s = "Зал загудел: позиция «%s» рухнула — защищать нечем." % claim
		else:
			s = "Довод снят, рамка «%s» зашаталась." % claim
		if stolen > 0:
			s += " (перехвачено себе: %d)" % stolen
	else:
		s = "Рамка «%s» устояла и только окрепла — зал кивает." % claim
	return s


func verdict_text(winner_side: String, reason: String, you_label: String, opp_label: String) -> String:
	var tail := ""
	match reason:
		"knockout": tail = "нокаут — оппоненту нечем крыть"
		"decision": tail = "решение по залу"
		"draw": tail = "зал замер ровно"
	if winner_side == "":
		return "Зал расходится в раздумьях. Ничья (%s)." % tail
	var w := you_label if winner_side == "you" else opp_label
	return "Зал на стороне «%s». Победа (%s)." % [w, tail]


# --- внутреннее ---

func _pole(side: String) -> String:
	return stance_of[side]


## Общая сборка атаки: тянет ось чужого довода, по приёму выбирает содержательный/процедурный
## разбор или кражу. gist = чужой взгляд, o = наш противоположный взгляд на ту же ось.
func _attack_line(attacker: String, target_claim: String, target_stmt: Dictionary, card: Dictionary, mk: String) -> String:
	var dev := device_for(card)
	var pole := _pole(attacker)
	var axis: Dictionary
	var gist: String
	if target_stmt.has("axis") and _axis_by_id.has(target_stmt.axis):
		axis = _axis_by_id[target_stmt.axis]
		gist = String(target_stmt.get("gist", ""))
	else:
		axis = _pick_axis([])
		gist = target_claim if target_claim != "" else String(axis[_other_pole(pole)])
	var opp_take := String(axis[pole])
	var motif := _axis_motif(axis)
	var reps := {"m": mk, "g": gist, "o": opp_take, "x": motif, "c": target_claim}
	if bool(card.get("steals", false)):
		return _cap(_fill(_pick(KRAJA_PAT.get(dev, KRAJA_PAT["Разворот"])), reps))
	if SUBSTANTIVE.has(dev):
		return _cap(_fill(_pick(RAZBOR_SUB.get(dev, RAZBOR_SUB["Контрпример"])), reps))
	return _cap(_fill(_pick(RAZBOR_PROC.get(dev, RAZBOR_PROC["Источник?"])), reps))


func _other_pole(pole: String) -> String:
	return "pro" if pole == "contra" else "contra"


func _pick_axis(used_ids: Array) -> Dictionary:
	var axes: Array = theme.axes
	var fresh: Array = axes.filter(func(a): return not used_ids.has(a.id))
	var src: Array = fresh if not fresh.is_empty() else axes
	return src[rng.randi() % src.size()]


func _axis_motif(axis: Dictionary) -> String:
	var pool: Array = (axis.get("motifs", []) as Array).duplicate()
	pool.append_array(theme.shared_motifs)
	var fresh: Array = pool.filter(func(m): return not _recent_motifs.has(m))
	var src: Array = fresh if not fresh.is_empty() else pool
	var m: String = src[rng.randi() % src.size()]
	_recent_motifs.append(m)
	if _recent_motifs.size() > 4:
		_recent_motifs.pop_front()
	return m


func _pick(arr: Array) -> String:
	return String(arr[rng.randi() % arr.size()])


# --- чистые варианты выборки (на переданном rng, без мутации состояния движка) для preview_text ---

func _pick_at(arr: Array, prng: RandomNumberGenerator) -> String:
	return String(arr[prng.randi() % arr.size()])


func _mark_at(kind: String, prng: RandomNumberGenerator) -> String:
	return _pick_at(MARK.get(kind, [""]), prng)


func _motif_pure(axis: Dictionary, prng: RandomNumberGenerator) -> String:
	var pool: Array = (axis.get("motifs", []) as Array).duplicate()
	pool.append_array(theme.shared_motifs)
	return String(pool[prng.randi() % pool.size()])


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
