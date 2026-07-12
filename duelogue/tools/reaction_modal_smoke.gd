extends Node

## Регрессия модальности микросцены: она должна перехватывать мышь, быть выше карточного UI
## и держать modal-active до полного завершения fade-out.

const ReactionScene := preload("res://duelogue/core/characters/reaction_scene.tscn")
const DebateScreen := preload("res://duelogue/ui/debate_screen.tscn")

var failures := 0
var starts := 0
var finishes := 0


func _ready() -> void:
	var reaction = ReactionScene.instantiate()
	add_child(reaction)
	reaction.scene_started.connect(func(): starts += 1)
	reaction.scene_finished.connect(func(): finishes += 1)
	reaction.show_impact("you", null, 0.65)
	_check(reaction.visible and reaction.is_modal_active(),
		"модальность включается в первый кадр микросцены")
	_check(reaction.mouse_filter == Control.MOUSE_FILTER_STOP,
		"полноэкранный слой перехватывает hover и клики")
	_check(reaction.z_index > 45,
		"микросцена рисуется выше карточного бабла и рамок")
	await reaction.scene_finished
	_check(not reaction.visible and not reaction.is_modal_active(),
		"модальность снимается только после fade-out")
	_check(starts == 1 and finishes == 1,
		"сигналы начала и конца сбалансированы")
	reaction.queue_free()

	# Интеграция с боевым экраном: уже открытый hover-бабл исчезает на scene_started,
	# а прямой повторный hover игнорируется до scene_finished.
	var screen = DebateScreen.instantiate()
	add_child(screen)
	await get_tree().process_frame
	var hover_owner := Control.new()
	screen.add_child(hover_owner)
	var card := {"type": "U", "steals": false}
	screen._show_card_bubble(hover_owner, "Рамка", "Описание", card)
	_check(screen._card_bubble.visible, "до микросцены hover-бабл работает")
	screen._reaction.show_impact("you", null, 0.65)
	_check(not screen._card_bubble.visible and screen._cutscene_active,
		"старт микросцены немедленно очищает открытый hover")
	screen._show_card_bubble(hover_owner, "Рамка", "Не должно появиться", card)
	_check(not screen._card_bubble.visible,
		"во время микросцены новый hover-бабл не создаётся")
	await screen._reaction.scene_finished
	_check(not screen._cutscene_active, "после микросцены hover снова разблокирован")
	screen.queue_free()
	print("=== REACTION MODAL: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
