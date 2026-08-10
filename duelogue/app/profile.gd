extends Node

## DUELOGUE — ПРОФИЛЬ ИГРОКА (autoload "Profile"): каталог обойм + настройки презентации/боя.
## Единственный владелец сейва user://profile.json. Каталог колод (ui/deck_catalog) правит
## СПИСОК обойм (decks) и то, какая из них активна (active_deck_id); редактор колоды
## (ui/deck_editor) правит СОСТАВ конкретной записи каталога. Битва (battle_controller)
## по-прежнему читает только плоское поле `deck` — оно всегда зеркалит активную запись
## каталога, так что боевой код не обязан знать про существование каталога вообще.
## Настройки применяются к статикам ReadingPace при загрузке и при каждом set_setting.
##
## Обойма (deck): счётчики базовых типов + список id именных приёмов (по 1 копии, §10.2);
## каждый именной ЗАМЕЩАЕТ ванильную карту своей базы ВНУТРИ счётчиков (named_cards.inject) —
## размер обоймы задают только счётчики. r — ВСЕ карты атаки, steals из них Кражи
## (контракт Deck.build_side, как DECK_R/STEAL_CARDS боя).

const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

const SAVE_PATH := "user://profile.json"

## Канон-обойма (= константы боя, GDD v0.3.2): У3 Т8 Р9 (из них 2 Кражи), без именных.
const CLASSIC := {"u": 3, "t": 8, "r": 9, "steals": 2, "named": []}
const OPP_STYLES := ["smart", "balanced", "aggro", "tall", "wide"]

var deck := {}             ## активная обойма — зеркало decks[active_deck_id].deck (контракт боя)
var decks := []            ## каталог: [{id, name, deck}, ...] — минимум 1 запись всегда
var active_deck_id := ""
var editing_deck_id := ""  ## транзит-хэндофф deck_catalog → deck_editor (какую запись открыть); не сейвится
var settings := {
	"opp_style": "smart", "chars_per_sec": 30.0, "cutscenes": true,
	"outcome_profile": "combat_cohesion", "outcome_contract_version": 3,
}


func _ready() -> void:
	deck = classic()
	load_profile()
	_ensure_catalog()
	_apply_presentation()


func classic() -> Dictionary:
	return CLASSIC.duplicate(true)


func deck_total() -> int:
	return deck_total_for(deck)


func deck_total_for(d: Dictionary) -> int:
	return int(d.get("u", 0)) + int(d.get("t", 0)) + int(d.get("r", 0))


## Короткая сводка обоймы (меню/редактор/каталог): «У3 Т8 Р7+К2 · именных 2 · всего 20».
func deck_summary() -> String:
	return deck_summary_for(deck)


func deck_summary_for(d: Dictionary) -> String:
	var named_n := (d.get("named", []) as Array).size()
	return "У%d Т%d Р%d+К%d · именных %d · всего %d" % [
		int(d.get("u", 0)), int(d.get("t", 0)), int(d.get("r", 0)) - int(d.get("steals", 0)),
		int(d.get("steals", 0)), named_n, deck_total_for(d)]


# ------------------------------------------------------------- каталог колод --

func list_decks() -> Array:
	return decks.duplicate(true)


func get_deck_entry(id: String) -> Dictionary:
	var i := _index_of(id)
	return (decks[i] as Dictionary).duplicate(true) if i != -1 else {}


## Новая запись каталога: канон-обойма как старт — сразу играбельна, не пустая рамка.
func add_deck(name: String = "") -> String:
	var id := _new_id()
	decks.append({"id": id, "name": name if name != "" else _auto_name(), "deck": classic()})
	save_profile()
	return id


## Каталог не может опуститься до нуля записей — бою и меню всегда нужна активная обойма.
func delete_deck(id: String) -> void:
	if decks.size() <= 1:
		return
	var i := _index_of(id)
	if i == -1:
		return
	decks.remove_at(i)
	if active_deck_id == id:
		set_active_deck(String(decks[0].id))
	else:
		save_profile()


func rename_deck(id: String, name: String) -> void:
	var i := _index_of(id)
	if i == -1:
		return
	var nm := name.strip_edges()
	if nm != "":
		decks[i]["name"] = nm
	save_profile()


## Пишет СОСТАВ конкретной записи каталога (вызывает deck_editor.save); если это активная
## запись — синхронизирует и плоское поле `deck`, которое читает бой.
func save_deck_data(id: String, d: Dictionary) -> void:
	var i := _index_of(id)
	if i == -1:
		return
	decks[i]["deck"] = _normalize_deck(d)
	if active_deck_id == id:
		deck = (decks[i].deck as Dictionary).duplicate(true)
	save_profile()


func set_active_deck(id: String) -> void:
	var i := _index_of(id)
	if i == -1:
		return
	active_deck_id = id
	deck = (decks[i].deck as Dictionary).duplicate(true)
	save_profile()


func _auto_name() -> String:
	var used := {}
	for e in decks:
		used[String(e.name)] = true
	var n := decks.size() + 1
	while used.has("Колода %d" % n):
		n += 1
	return "Колода %d" % n


func _index_of(id: String) -> int:
	for i in decks.size():
		if String(decks[i].id) == id:
			return i
	return -1


func _new_id() -> String:
	return "d%d_%d" % [Time.get_ticks_usec(), randi() % 1000]


## Мёрж поверх классики (как раньше делал load_profile для единственной обоймы) — новые
## поля получают дефолт, старые сейвы живут; opening требует физическую рамку-резерв (u>=1).
func _normalize_deck(raw: Dictionary) -> Dictionary:
	var d := classic()
	for k in raw:
		d[k] = raw[k]
	d["u"] = maxi(1, int(d.get("u", 1)))
	if not (d.get("named") is Array):
		d["named"] = []
	return d


## Гарантирует каталог из ≥1 записи после загрузки. Старый сейв (без decks) — заворачиваем
## текущую `deck` в единственную запись «Колода 1». Битый/пустой active_deck_id — откат
## на первую запись каталога.
func _ensure_catalog() -> void:
	if decks.is_empty():
		var id := _new_id()
		decks.append({"id": id, "name": "Колода 1", "deck": deck.duplicate(true)})
		active_deck_id = id
		save_profile()
		return
	if _index_of(active_deck_id) == -1:
		active_deck_id = String(decks[0].id)
		deck = (decks[0].deck as Dictionary).duplicate(true)
		save_profile()


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_presentation()
	save_profile()


# --- сейв ---

func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"deck": deck, "settings": settings, "decks": decks, "active_deck_id": active_deck_id,
	}, "\t"))
	f.close()


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	var d: Dictionary = data
	if d.get("deck") is Dictionary:
		deck = _normalize_deck(d.deck)
	if d.get("decks") is Array:
		var built := []
		for raw in (d.decks as Array):
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) != "" \
					and (raw as Dictionary).get("deck") is Dictionary:
				var re: Dictionary = raw
				built.append({
					"id": String(re.id), "name": String(re.get("name", "Колода")),
					"deck": _normalize_deck(re.deck),
				})
		decks = built
		active_deck_id = String(d.get("active_deck_id", ""))
	if d.get("settings") is Dictionary:
		var ls: Dictionary = d.settings
		var contract_version := int(ls.get("outcome_contract_version", 0))
		var old_contract := contract_version < 2
		for k in ls:
			settings[k] = ls[k]
		# Одноразово переводим только прежний дефолт. После этой отметки пользователь может
		# вручную выбрать vector_reaction — следующий запуск уже не переопределит его выбор.
		if old_contract:
			if String(settings.get("outcome_profile", "")) == "vector_reaction":
				settings["outcome_profile"] = "vector_conduct"
			settings["outcome_contract_version"] = 2
			save_profile()
		# v3 включает новый связный боевой луп. Переводим только прежний дефолт; явно
		# выбранные диагностические/legacy-профили остаются выбором игрока.
		if contract_version < 3:
			if String(settings.get("outcome_profile", "")) == "vector_conduct":
				settings["outcome_profile"] = "combat_cohesion"
			settings["outcome_contract_version"] = 3
			save_profile()


## Настройки презентации — в статики ReadingPace (единые часы сцен и пейсинга).
func _apply_presentation() -> void:
	ReadingPace.CHARS_PER_SEC = clampf(float(settings.get("chars_per_sec", 30.0)),
		ReadingPace.MIN_CHARS_PER_SEC, ReadingPace.MAX_CHARS_PER_SEC)
	ReadingPace.CUTSCENES = bool(settings.get("cutscenes", true))
