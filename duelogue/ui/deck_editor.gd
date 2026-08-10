extends Control

## DUELOGUE — РЕДАКТОР КОЛОДЫ (обоймы). Ручная сборка ОДНОЙ записи каталога (ui/deck_catalog):
## счётчики базовых типов + именные приёмы (по 1 копии, §10.2; каждый ЗАМЕЩАЕТ ванильную карту
## своей базы внутри счётчиков — размер обоймы задают счётчики). Какую запись открыть — решает
## Profile.editing_deck_id (транзит-хэндофф от каталога; пусто → правим активную). Пишет через
## Profile.save_deck_data(id, ...); если правим активную запись — battle_controller видит
## изменения сразу же (Profile.deck зеркалится). Каркас — нодами в deck_editor.tscn (правится
## в редакторе); ряды счётчиков и список приёмов строятся кодом из реестра.
##
## Канон и коридоры — индикаторы, не запреты: полигон должен позволять и заведомо кривые
## обоймы (симы D/A показали цену краёв — редактор их подсвечивает, но не запрещает).
##
## Правая колонка — живой грид ВСЕХ карт текущей обоймы (настоящие виджеты ui/card/card.tscn,
## та же техника «add_child → setup», что и рука в debate_screen). Именные подставлены на
## место замещённой ваниль-карты (зеркалит named_cards.inject) — превью показывает ИТОГ,
## а не счётчики отдельно от приёмов. Слева — блок «РАЗМЕР ОБОЙМЫ»: масштабирует все счётчики
## к новому итогу, сохраняя текущее СООТНОШЕНИЕ типов (largest remainder), чтобы можно было
## гонять один и тот же архетип на 20/24/30 картах без ручного пересчёта каждого слота.

const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")
const C := preload("res://duelogue/core/cards/card_types.gd")
const DeckLib := preload("res://duelogue/core/cards/deck.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const CardScene := preload("res://duelogue/ui/card/card.tscn")
const CatalogHub := preload("res://duelogue/ui/catalog_hub.gd")

const CANON_TOTAL := 20
const SLOT_MAX := 40
const SIZE_PRESETS := [20, 24, 30]
const GRID_COLUMNS := 4
## Ряды счётчиков: ключ рабочей обоймы → лейбл + сим-коридор (подсветка краёв).
const SLOT_DEFS := [
	{"key": "u", "label": "Установки", "lo": 2, "hi": 5},
	{"key": "t", "label": "Тезисы", "lo": 6, "hi": 10},
	{"key": "plain", "label": "Разборы (обычные)", "lo": 4, "hi": 10},
	{"key": "steals", "label": "Кражи", "lo": 1, "hi": 3},
]
const SLOT_KEYS := ["u", "t", "plain", "steals"]

var _deck := {}           ## рабочая копия: {u, t, plain, steals, named: []}
var _editing_id := ""     ## id записи каталога, которую правим (Profile.decks)
var _count_labels := {}   ## key → Label счётчика
var _named_checks := {}   ## id приёма → CheckBox
var _size_total_label: Label
var _nar := NarEngine.new()   ## только device_label() — чтение мехлейбла карты, без rng-состояния

@onready var _name_edit: LineEdit = %NameEdit
@onready var _slots_box: VBoxContainer = %SlotsBox
@onready var _named_box: VBoxContainer = %NamedBox
@onready var _size_box: VBoxContainer = %SizeBox
@onready var _total_label: Label = %TotalLabel
@onready var _warn_label: Label = %WarnLabel
@onready var _save_btn: Button = %SaveBtn
@onready var _card_grid: GridContainer = %CardGrid
@onready var _grid_title: Label = %GridTitle


func _ready() -> void:
	_card_grid.columns = GRID_COLUMNS
	%BackBtn.pressed.connect(_to_catalog)
	_save_btn.pressed.connect(_save)
	%PresetClassicBtn.pressed.connect(_preset.bind(false))
	%PresetNamedBtn.pressed.connect(_preset.bind(true))
	_name_edit.text_submitted.connect(func(_t: String) -> void: _rename())
	_name_edit.focus_exited.connect(_rename)
	# Хэндофф разовый: забираем и сразу гасим, иначе следующий заход в редактор без
	# явного выбора из каталога унаследует чужой id вместо активной записи.
	_editing_id = Profile.editing_deck_id if Profile.editing_deck_id != "" else Profile.active_deck_id
	Profile.editing_deck_id = ""
	var entry := Profile.get_deck_entry(_editing_id)
	if entry.is_empty():
		_editing_id = Profile.active_deck_id
		entry = Profile.get_deck_entry(_editing_id)
	_name_edit.text = String(entry.get("name", ""))
	var entry_deck: Dictionary = entry.get("deck", Profile.classic())
	_deck = _from_profile(entry_deck)
	_build_slot_rows()
	_build_size_controls()
	_build_named_list()
	_refresh()


func _rename() -> void:
	Profile.rename_deck(_editing_id, _name_edit.text)
	_name_edit.text = String(Profile.get_deck_entry(_editing_id).get("name", _name_edit.text))


# ------------------------------------------------ рабочая обойма ↔ профиль ----

## Профиль хранит r = ВСЕ атаки (контракт Deck.build_side); редактор разводит на
## «обычные разборы» и «кражи» — так счётчики читаются как слоты.
func _from_profile(d: Dictionary) -> Dictionary:
	var steals := int(d.get("steals", 2))
	return {
		"u": int(d.get("u", 3)), "t": int(d.get("t", 8)),
		"plain": maxi(0, int(d.get("r", 9)) - steals), "steals": steals,
		"named": (d.get("named", []) as Array).duplicate(),
	}


func _to_profile() -> Dictionary:
	return {
		"u": int(_deck.u), "t": int(_deck.t),
		"r": int(_deck.plain) + int(_deck.steals), "steals": int(_deck.steals),
		"named": (_deck.named as Array).duplicate(),
	}


# ------------------------------------------------------------- динамика UI ----

func _build_slot_rows() -> void:
	for def in SLOT_DEFS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = String(def.label)
		name_l.tooltip_text = "Коридор: %d–%d карт" % [int(def.lo), int(def.hi)]
		name_l.mouse_filter = Control.MOUSE_FILTER_STOP
		name_l.custom_minimum_size = Vector2(140, 0)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 13)
		row.add_child(name_l)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(28, 26)
		minus.pressed.connect(_bump.bind(String(def.key), -1))
		row.add_child(minus)
		var count_l := Label.new()
		count_l.custom_minimum_size = Vector2(34, 0)
		count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_l.add_theme_font_size_override("font_size", 16)
		row.add_child(count_l)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(28, 26)
		plus.pressed.connect(_bump.bind(String(def.key), 1))
		row.add_child(plus)
		_slots_box.add_child(row)
		_count_labels[String(def.key)] = count_l


## Блок «РАЗМЕР ОБОЙМЫ»: строка -/N/+ (шаг ±1 карта, ratio-preserving) + быстрые пресеты
## из SIZE_PRESETS — тестировать 20/24/30 в один клик, не гоняя все счётчики руками.
func _build_size_controls() -> void:
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 8)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(28, 26)
	minus.pressed.connect(_step_total.bind(-1))
	stepper.add_child(minus)
	_size_total_label = Label.new()
	_size_total_label.custom_minimum_size = Vector2(52, 0)
	_size_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_total_label.add_theme_font_size_override("font_size", 16)
	stepper.add_child(_size_total_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(28, 26)
	plus.pressed.connect(_step_total.bind(1))
	stepper.add_child(plus)
	_size_box.add_child(stepper)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	var hint := Label.new()
	hint.text = "быстро:"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5412, 0.5765, 0.6392))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	presets.add_child(hint)
	for n in SIZE_PRESETS:
		var b := Button.new()
		b.text = str(int(n))
		b.custom_minimum_size = Vector2(40, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_scale_to.bind(int(n)))
		presets.add_child(b)
	_size_box.add_child(presets)


## Аккуратный список тумблеров: правило приёма — в tooltip (наведение), не под именем,
## чтобы список не раздувался абзацами текста.
func _build_named_list() -> void:
	for id in NamedCards.ids():
		var card := NamedCards.make(String(id))
		var check := CheckBox.new()
		check.text = "%s — %s" % [String(card.name), _base_label(card)]
		check.tooltip_text = String(card.text)
		check.add_theme_font_size_override("font_size", 13)
		check.button_pressed = (_deck.named as Array).has(id)
		check.toggled.connect(_on_named_toggled.bind(String(id)))
		_named_box.add_child(check)
		_named_checks[String(id)] = check


func _base_label(card: Dictionary) -> String:
	match String(card.type):
		C.TYPE_TEZIS: return "Тезис"
		C.TYPE_USTANOVKA: return "Установка"
		C.TYPE_RAZBOR: return "Кража" if bool(card.get("steals", false)) else "Разбор"
	return "?"


# ---------------------------------------------------------------- интенты -----

func _bump(key: String, delta: int) -> void:
	_deck[key] = clampi(int(_deck[key]) + delta, 0, SLOT_MAX)
	_refresh()


func _on_named_toggled(pressed: bool, id: String) -> void:
	var named: Array = _deck.named
	if pressed and not named.has(id):
		named.append(id)
	elif not pressed:
		named.erase(id)
	_refresh()


func _step_total(delta: int) -> void:
	_scale_to(_deck_total() + delta)


## Меняет ИТОГ обоймы, сохраняя текущее соотношение u/t/plain/steals (largest remainder:
## округляем доли вниз, недостающие до target карты раздаём слотам с наибольшим остатком —
## сумма после округления обязана попасть в target точно). Состав пуст (total=0) — стартуем
## от канона, а не от деления на ноль.
func _scale_to(target: int) -> void:
	target = maxi(1, target)
	var basis: Dictionary = _deck
	var basis_total := _deck_total()
	if basis_total <= 0:
		basis = {"u": 3, "t": 8, "plain": 7, "steals": 2}
		basis_total = 20
	var result := {}
	var remainders := []   # [остаток, исходный индекс, ключ] — сортируем сами: sort_custom
	var floor_sum := 0     # не гарантирует стабильность при равных долях, индекс — тай-брейк
	for i in SLOT_KEYS.size():
		var key: String = SLOT_KEYS[i]
		var share := float(basis[key]) / float(basis_total) * float(target)
		var whole := floori(share)
		result[key] = whole
		remainders.append([share - float(whole), i, key])
		floor_sum += whole
	remainders.sort_custom(func(a, b):
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for i in (target - floor_sum):
		var key: String = remainders[i][2]
		result[key] += 1
	for key in SLOT_KEYS:
		_deck[key] = clampi(int(result[key]), 0, SLOT_MAX)
	if int(_deck.u) < 1:
		_deck.u = 1
	_refresh()


func _deck_total() -> int:
	return int(_deck.u) + int(_deck.t) + int(_deck.plain) + int(_deck.steals)


func _preset(with_named: bool) -> void:
	_deck = _from_profile(Profile.classic())
	if with_named:
		_deck.named = NamedCards.ids().duplicate()
	for id in _named_checks:
		(_named_checks[id] as CheckBox).set_pressed_no_signal((_deck.named as Array).has(id))
	_refresh()


func _save() -> void:
	Profile.save_deck_data(_editing_id, _to_profile())
	_rename()
	_warn_label.add_theme_color_override("font_color", Color(0.44, 0.81, 0.5))
	if _editing_id == Profile.active_deck_id:
		_warn_label.text = "Сохранено — эта обойма активна и пойдёт в следующую катку."
	else:
		_warn_label.text = "Сохранено в каталог. Активна другая колода — выберите эту в каталоге, если нужно играть ей."


func _to_catalog() -> void:
	CatalogHub.requested_tab = 0  # вкладка «Колоды»
	get_tree().change_scene_to_file("res://duelogue/ui/catalog_hub.tscn")


# ----------------------------------------------------------------- рендер -----

func _refresh() -> void:
	for def in SLOT_DEFS:
		var key := String(def.key)
		var l: Label = _count_labels[key]
		l.text = str(int(_deck[key]))
		var v := int(_deck[key])
		# Подсветка краёв сим-коридоров (жёлтым): играть можно, но цена известна (§11.4).
		l.add_theme_color_override("font_color",
			Color(0.91, 0.91, 0.91) if v >= int(def.lo) and v <= int(def.hi) else Color(1.0, 0.82, 0.29))
	var total := _deck_total()
	var named_n := (_deck.named as Array).size()
	_total_label.text = "Всего карт: %d  (канон %d)   ·   именных внутри: %d" % [total, CANON_TOTAL, named_n]
	_total_label.add_theme_color_override("font_color",
		Color(0.44, 0.81, 0.5) if total == CANON_TOTAL else Color(1.0, 0.82, 0.29))
	_size_total_label.text = str(total)
	# Валидация замен: именных приёмов базы не может быть больше, чем карт этой базы.
	var warn := _validate()
	_warn_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	_warn_label.text = warn
	_save_btn.disabled = warn != ""
	_build_card_grid(total)


func _validate() -> String:
	if int(_deck.u) < 1:
		return "Нужна минимум 1 Установка: opening закрепляет её как публичный резерв от нокаута."
	var need := {"u": 0, "t": 0, "plain": 0, "steals": 0}
	for id in _deck.named:
		var card := NamedCards.make(String(id))
		if card.is_empty():
			continue
		match String(card.type):
			C.TYPE_USTANOVKA: need.u += 1
			C.TYPE_TEZIS: need.t += 1
			C.TYPE_RAZBOR:
				if bool(card.get("steals", false)):
					need.steals += 1
				else:
					need.plain += 1
	var labels := {"u": "Установок", "t": "Тезисов", "plain": "Разборов", "steals": "Краж"}
	for key in need:
		if int(need[key]) > int(_deck[key]):
			return "Именных приёмов базы «%s» больше, чем карт в счётчике (%d > %d) — добавь карт или сними приём." % [
				labels[key], int(need[key]), int(_deck[key])]
	return ""


# ------------------------------------------------------------ грид карт -------

## Живой грид: каждая карта текущей обоймы — настоящий виджет ui/card/card.tscn (та же
## техника, что и рука в debate_screen._rebuild_hand — add_child в уже-живой контейнер,
## затем сразу setup(), без combo_catalog-style двухфазной отложенной сборки, потому что
## тут карты вешаются НАПРЯМУЮ на _card_grid, а не сквозь несколько уровней detached-обёрток).
func _build_card_grid(total: int) -> void:
	for c in _card_grid.get_children():
		c.queue_free()
	for card in _card_list():
		var inst: Button = CardScene.instantiate()
		_card_grid.add_child(inst)
		var face := _card_face(card)
		inst.setup(card, String(face[0]), String(face[1]), true)
		inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inst.focus_mode = Control.FOCUS_NONE
	_grid_title.text = "СОСТАВ ОБОЙМЫ — %d карт" % total


## Плоский список карт текущей обоймы: счётчики разворачиваются той же фабрикой, что и
## реальная колода (Deck.make_card), именные подставляются на место замещённой ваниль —
## превью показывает ИТОГОВЫЙ состав, а не счётчики отдельно от приёмов (см. named_cards.inject).
func _card_list() -> Array:
	var cards: Array = []
	for i in int(_deck.u):
		cards.append(DeckLib.make_card(C.TYPE_USTANOVKA, i))
	for i in int(_deck.t):
		cards.append(DeckLib.make_card(C.TYPE_TEZIS, i))
	for i in int(_deck.plain):
		cards.append(DeckLib.make_card(C.TYPE_RAZBOR, i))
	for i in int(_deck.steals):
		cards.append({"type": C.TYPE_RAZBOR, "name": "Кража", "steals": true})
	for id in (_deck.named as Array):
		var nc := NamedCards.make(String(id))
		if not nc.is_empty():
			_replace_one_vanilla(cards, nc)
	return cards


## Зеркалит named_cards.inject(): сперва точное совпадение (тип + steals-природа), иначе
## любая ваниль той же базы — размер обоймы не раздувается именными сверху счётчиков.
func _replace_one_vanilla(cards: Array, nc: Dictionary) -> void:
	for exact in [true, false]:
		for i in cards.size():
			var c: Dictionary = cards[i]
			if c.has("named") or String(c.type) != String(nc.type):
				continue
			if exact and bool(c.get("steals", false)) != bool(nc.steals):
				continue
			cards[i] = nc
			return


## Лицо карты вне боя (нет модели/hand_preview): именная — своё имя + правило-твист;
## ваниль — мехлейбл (схема/приём, как в руке debate_screen) сверху и её ролевое имя
## снизу, тот же порядок пары «титул/бабл», что и на столе.
func _card_face(card: Dictionary) -> Array:
	var is_named: bool = card.has("named")
	var title: String = String(card.get("name", "")) if is_named or String(card.type) == C.TYPE_USTANOVKA \
		else _nar.device_label(card)
	var body: String = String(card.get("text", "")) if is_named else String(card.get("name", ""))
	return [title, body]
