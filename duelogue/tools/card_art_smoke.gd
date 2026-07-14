extends SceneTree

const Art := preload("res://duelogue/core/cards/card_art.gd")
const C := preload("res://duelogue/core/cards/card_types.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Named := preload("res://duelogue/core/cards/named_cards.gd")
const Narrative := preload("res://duelogue/core/narrative/narrative_engine.gd")

var failures := 0


func _init() -> void:
	print("\n=== CARD ART · SMOKE ===")
	var narrative := Narrative.new()
	for i in Deck.TEZIS_NAMES.size():
		var card := Deck.make_card(C.TYPE_TEZIS, i)
		_check_card(card, narrative.device_label(card))
	for i in Deck.RAZBOR_NAMES.size():
		var card := Deck.make_card(C.TYPE_RAZBOR, i)
		_check_card(card, narrative.device_label(card))
	for title in ["Разворот", "Та же логика"]:
		_check_card({"type": C.TYPE_RAZBOR, "name": "Кража", "steals": true}, title)
	for i in Deck.USTANOVKA_NAMES.size():
		var card := Deck.make_card(C.TYPE_USTANOVKA, i)
		_check_card(card, String(card.name))
	for id in Named.ids():
		var card := Named.make(String(id))
		_check_card(card, String(card.name))
	print("=== CARD ART: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check_card(card: Dictionary, title: String) -> void:
	_check_texture(Art.type_icon_for(card), "%s · иконка типа" % title)
	_check_texture(Art.art_for(card, title), "%s · арт приёма" % title)


func _check_texture(texture: Texture2D, label: String) -> void:
	var ok := texture is AtlasTexture and (texture as AtlasTexture).atlas != null
	if ok:
		var atlas_texture := texture as AtlasTexture
		var bounds := Rect2(Vector2.ZERO, atlas_texture.atlas.get_size())
		ok = bounds.encloses(atlas_texture.region)
	print("  %s · %s" % ["OK" if ok else "FAIL", label])
	if not ok:
		failures += 1
