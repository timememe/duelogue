extends RefCounted

## DUELOGUE — КОМБО-ГРАММАТИКА: общая риторическая онтология (контракт combo_grammar_v0.2 §1, §3).
## Нейтральный модуль данных без зависимостей (кроме card_types) — читается deck (тегирование
## при создании), narrative (реплики HIT/MISS), правилами, UI и AI из ОДНОГО источника.
## Словарь намеренно русский — «за основу берётся уже работающий словарь narrative engine»:
## схемы Тезисов («Аналогия»), приёмы Разборов («Контрпример») и зацепки («исключение»).
## Narrative держит свои старые name-мапы только как fallback для архивных данных.
##
## Ступень 1 лестницы (§13): чистые данные + matcher, БЕЗ механических эффектов.
## Механика (LINK/ARMED/CONFIRMED/BREAK) появляется на ступени 2 и читает эти же функции.

const C := preload("res://duelogue/core/cards/card_types.gd")

# --- Схемы Тезисов → масть (§1.1). Масти — данные будущих сетов, в ступени 1 инертны. ---
const SUIT_OF := {
	"Пример": "logos", "Авторитет": "ethos", "Статистика": "logos", "Аналогия": "logos",
	"Здравый смысл": "ethos", "Эмоция": "pathos", "Определение": "logos", "Традиция": "ethos",
}

# --- Приём Разбора → зацепка (§1.2). Кража — не зацепка, а присвоение: её здесь нет. ---
const HOOK_OF := {
	"Источник?": "источник", "Контрпример": "исключение", "Ложная аналогия": "сходство",
	"До абсурда": "следствие", "Передёрг": "подмена", "Корреляция": "связь",
	"Не в кассу": "уместность",
}

# --- Схема → открытые зацепки: может ли зацепка содержательно ударить по схеме (§1.2). ---
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

# --- ANSWER_OF[setup_scheme][hook] → маршрут (§1.4). Единственная новая таблица: OPEN_HOOKS
# определяет правильность атаки, ANSWER_OF — чем на неё отвечать в контексте атакованной
# схемы. Содержательный HIT без записи здесь — обычный сильный Разбор, LINK не открывает.
# Три маршрута первого теста (§5); формулировки — кандидаты бумаги A0, не финал. ---
const ANSWER_OF := {
	"Аналогия": {
		"исключение": {
			"answer_schemes": ["Авторитет"],
			"route_id": "exception_noted",
			"combo_name": "Исключение учтено",
		},
	},
	"Традиция": {
		"следствие": {
			"answer_schemes": ["Определение"],
			"route_id": "borders_restored",
			"combo_name": "Возвращаю границы",
		},
	},
	"Эмоция": {
		"уместность": {
			"answer_schemes": ["Пример"],
			"route_id": "about_people",
			"combo_name": "Это касается людей",
		},
	},
}

# --- Тегирование при создании (deck.make_card): имя колоды → схема/приём. Авторитет —
# ДАННЫЕ КАРТЫ, не повторное вычисление по имени (§1.3); эти мапы — только фабричные. ---
const CARD_SCHEME := {
	"Довод": "Здравый смысл", "Контрфакт": "Статистика", "Аргумент": "Определение",
	"Уточнение": "Аналогия", "Пример": "Пример", "Ссылка": "Авторитет",
	"Факт": "Традиция", "Логика": "Эмоция",
}
const CARD_DEVICE := {
	"Не в кассу": "Не в кассу", "Передёрг": "Передёрг", "Контрпример": "Контрпример",
	"Софизм?": "До абсурда", "Источник?": "Источник?", "Подмена": "Корреляция",
	"Мимо": "Ложная аналогия", "А докажи": "Источник?",
}


# --- Чистый matcher (§3). Работает над объектами карт; сторожа §12: combo_eligible=false
# никогда не входит в грамматику, независимо от полей схемы. ---

static func eligible(card: Dictionary) -> bool:
	return bool(card.get("combo_eligible", false))


## Зацепка атаки: только у eligible Разбора с протегированным приёмом. Кража и «И что?»
## (безхуковый safe poke) возвращают "" и в грамматику не входят.
static func hook_of(attack: Dictionary) -> String:
	if not eligible(attack) or String(attack.get("type", "")) != C.TYPE_RAZBOR:
		return ""
	return String(HOOK_OF.get(String(attack.get("device", "")), ""))


## HIT(T, A): зацепка атаки содержательно берёт схему exact Тезиса.
static func hit(thesis: Dictionary, attack: Dictionary) -> bool:
	if not eligible(thesis) or String(thesis.get("type", "")) != C.TYPE_TEZIS:
		return false
	var hook := hook_of(attack)
	if hook == "":
		return false
	return (OPEN_HOOKS.get(String(thesis.get("scheme", "")), []) as Array).has(hook)


## ROUTE(T, A): запись ANSWER_OF для пары схема×зацепка; {} если маршрута нет.
static func route(thesis: Dictionary, attack: Dictionary) -> Dictionary:
	if not hit(thesis, attack):
		return {}
	var by_hook: Dictionary = ANSWER_OF.get(String(thesis.get("scheme", "")), {})
	return by_hook.get(hook_of(attack), {})


## HAS_ROUTE(T, A): HIT с известным маршрутом ответа — будущее открытие LINK.
static func has_route(thesis: Dictionary, attack: Dictionary) -> bool:
	return not route(thesis, attack).is_empty()


## ANSWERS(T, A, T2): правильный защитный ответ закрывает маршрут пары.
static func answers(thesis: Dictionary, attack: Dictionary, answer: Dictionary) -> bool:
	if not eligible(answer) or String(answer.get("type", "")) != C.TYPE_TEZIS:
		return false
	var r := route(thesis, attack)
	if r.is_empty():
		return false
	return (r.get("answer_schemes", []) as Array).has(String(answer.get("scheme", "")))


## TRIPLE(T, A, T2): минимальная тройка setup → зацепка → ответ (§0.1).
static func triple(thesis: Dictionary, attack: Dictionary, answer: Dictionary) -> bool:
	return answers(thesis, attack, answer)
