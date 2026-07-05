extends Node

## Three-layer data loader:
##   Layer 1 — data/cards/universal_cards.json (mechanical definitions, card_id -> CardData)
##   Layer 2 — data/themes/<theme_id>/theme.json (name/text overrides per card_id)
##   Layer 3 — data/decks/<deck>.json (list of card_id + theme reference)
##
## At load time each deck is resolved: card_ids -> universal CardData -> apply theme overrides
## -> final per-deck CardData instances stored in DeckData.

const UNIVERSAL_CARDS_PATH := "res://data/cards/universal_cards.json"
const THEME_PATHS := {
	"coffee": "res://data/themes/coffee/theme.json",
	"evangelion": "res://data/themes/evangelion/theme.json",
	"drive": "res://data/themes/drive/theme.json",
}
const DECK_PATHS: Array[String] = [
	"res://data/decks/default_deck.json",
	"res://data/decks/evangelion_deck.json",
	"res://data/decks/drive_deck.json",
]

var _universal_cards: Dictionary = {} ## card_id -> CardData
var _themes: Dictionary = {} ## theme_id -> Dictionary (raw theme dict)
var _decks: Dictionary = {} ## display_name OR deck_id -> DeckData


func _ready() -> void:
	_load_universal_cards()
	_load_themes()
	_load_decks()


# --- Layer 1: universal cards ---

func _load_universal_cards() -> void:
	var data = _parse_json(UNIVERSAL_CARDS_PATH)
	if not data is Array:
		push_error("universal_cards.json: ожидался массив верхнего уровня")
		return
	for entry in data:
		if entry is Dictionary:
			var card := CardData.from_dict(entry)
			_universal_cards[card.card_id] = card
	print("Загружено универсальных карт: %d" % _universal_cards.size())


# --- Layer 2: themes ---

func _load_themes() -> void:
	for theme_id in THEME_PATHS:
		var path: String = THEME_PATHS[theme_id]
		var data = _parse_json(path)
		if data is Dictionary:
			_themes[theme_id] = data
	print("Загружено тем: %d" % _themes.size())


# --- Layer 3: decks ---

func _load_decks() -> void:
	var loaded_count := 0
	for path in DECK_PATHS:
		var data = _parse_json(path)
		if not data is Dictionary:
			continue
		var deck := _build_deck(data)
		if deck == null:
			continue
		loaded_count += 1
		var deck_id: String = data.get("id", "")
		var display_name: String = data.get("display_name", deck_id)
		_decks[display_name] = deck
		if deck_id != "" and deck_id != display_name:
			_decks[deck_id] = deck
	print("Загружено колод: %d" % loaded_count)


func _build_deck(deck_dict: Dictionary) -> DeckData:
	var deck := DeckData.new()
	deck.deck_name = deck_dict.get("display_name", "Unnamed")
	var theme_id: String = deck_dict.get("theme_id", "")
	var theme: Dictionary = _themes.get(theme_id, {})
	var cards: Dictionary = deck_dict.get("cards", {})

	_fill_list(cards.get("player_attack_cards", []), theme, deck.player_attack_cards)
	_fill_list(cards.get("enemy_attack_cards", []), theme, deck.enemy_attack_cards)
	_fill_list(cards.get("defense_cards", []), theme, deck.defense_cards)
	_fill_list(cards.get("evasion_cards", []), theme, deck.evasion_cards)
	_fill_list(cards.get("rare_attack_cards", []), theme, deck.rare_attack_cards)

	var repeat_id = cards.get("repeat_card", "")
	if repeat_id != "":
		deck.repeat_card = _resolve_card(repeat_id, theme)
	deck.burst_card = _resolve_card("special_burst", theme)
	deck.rage_card = _resolve_card("special_rage", theme)

	print("Собрана колода '%s' [theme=%s]: %d атак игрока + %d атак оппонента, %d защит, %d уклонений" % [
		deck.deck_name, theme_id,
		deck.player_attack_cards.size(),
		deck.enemy_attack_cards.size(),
		deck.defense_cards.size(),
		deck.evasion_cards.size()
	])
	return deck


func _fill_list(card_ids: Array, theme: Dictionary, target: Array[CardData]) -> void:
	for card_id in card_ids:
		var card := _resolve_card(card_id, theme)
		if card:
			target.append(card)


func _resolve_card(card_id: String, theme: Dictionary) -> CardData:
	if not _universal_cards.has(card_id):
		push_error("Неизвестный card_id: %s" % card_id)
		return null
	var base: CardData = _universal_cards[card_id]
	var theme_overrides = theme.get("card_overrides", {})
	if not theme_overrides is Dictionary or not theme_overrides.has(card_id):
		# No overrides — return a duplicate so different decks don't share mutable state
		return base.duplicate()
	var overrides: Dictionary = theme_overrides[card_id]
	var resolved: CardData = base.duplicate()
	if overrides.has("name"):
		resolved.card_name = overrides["name"]
	if overrides.has("desc"):
		resolved.description = overrides["desc"]
	if overrides.has("text"):
		resolved.text = overrides["text"]
	if overrides.has("textVariants"):
		var variants = overrides["textVariants"]
		if variants is Array:
			var psa := PackedStringArray()
			for v in variants:
				psa.append(str(v))
			resolved.text_variants = psa
	return resolved


# --- Public API (unchanged for callers) ---

func get_deck(deck_name: String) -> DeckData:
	return _decks.get(deck_name)


func create_card_instance(card_id: String) -> CardInstance:
	var card_data := _resolve_card(card_id, {})
	if card_data == null:
		return null
	return CardInstance.new(card_data)


func get_deck_names() -> PackedStringArray:
	var names := PackedStringArray()
	var seen: Dictionary = {}
	for key in _decks:
		var deck: DeckData = _decks[key]
		if not seen.has(deck):
			seen[deck] = true
			names.append(deck.deck_name)
	return names


func create_full_deck(deck_data: DeckData, is_player: bool) -> Array[CardInstance]:
	var cards: Array[CardInstance] = []
	var attack_pool: Array[CardData] = deck_data.player_attack_cards if is_player else deck_data.enemy_attack_cards

	for card_data in attack_pool:
		cards.append(CardInstance.new(card_data))

	for card_data in deck_data.defense_cards:
		cards.append(CardInstance.new(card_data))

	for card_data in deck_data.evasion_cards:
		cards.append(CardInstance.new(card_data))

	for card_data in deck_data.rare_attack_cards:
		cards.append(CardInstance.new(card_data))

	return cards


func create_starting_hand(deck_data: DeckData, stats: CharacterStats, is_player: bool) -> Array[CardInstance]:
	## Starting hand: 2 attacks + 1 defense + 1 evasion
	var hand: Array[CardInstance] = []
	var used_names: Dictionary = {}
	var attack_pool: Array[CardData] = deck_data.player_attack_cards if is_player else deck_data.enemy_attack_cards

	# 2 attacks weighted by logic/emotion
	var total := maxi(1, stats.logic + stats.emotion)
	var logic_weight := float(stats.logic) / total

	for i in 2:
		var use_logic := randf() < logic_weight
		var pool: Array[CardData] = []
		for c in attack_pool:
			var is_logic := c.effect == Enums.CardEffect.LOGIC
			if use_logic and is_logic:
				pool.append(c)
			elif not use_logic and not is_logic:
				pool.append(c)
		if pool.is_empty():
			pool = attack_pool

		var available: Array[CardData] = []
		for c in pool:
			if not used_names.has(c.card_name):
				available.append(c)
		if available.is_empty():
			available = pool

		if not available.is_empty():
			var chosen: CardData = available[randi() % available.size()]
			hand.append(CardInstance.new(chosen))
			used_names[chosen.card_name] = true

	# 1 defense (non-shield)
	var def_pool: Array[CardData] = []
	for c in deck_data.defense_cards:
		if c.effect != Enums.CardEffect.SHIELD:
			def_pool.append(c)
	if def_pool.is_empty():
		def_pool = deck_data.defense_cards

	if not def_pool.is_empty():
		var available: Array[CardData] = []
		for c in def_pool:
			if not used_names.has(c.card_name):
				available.append(c)
		if available.is_empty():
			available = def_pool
		var chosen: CardData = available[randi() % available.size()]
		hand.append(CardInstance.new(chosen))
		used_names[chosen.card_name] = true

	# 1 evasion
	if not deck_data.evasion_cards.is_empty():
		var available: Array[CardData] = []
		for c in deck_data.evasion_cards:
			if not used_names.has(c.card_name):
				available.append(c)
		if available.is_empty():
			available = deck_data.evasion_cards
		var chosen: CardData = available[randi() % available.size()]
		hand.append(CardInstance.new(chosen))
		used_names[chosen.card_name] = true

	return hand


# --- Helpers ---

func _parse_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Не удалось открыть файл: %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("Ошибка JSON в %s: %s" % [path, json.get_error_message()])
		return null
	return json.data
