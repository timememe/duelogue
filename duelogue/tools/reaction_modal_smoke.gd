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
	reaction.show_utterance("you", "Тестовый срыв", null, "burst", false,
		"ЭМОЦИОНАЛЬНЫЙ СРЫВ · Вспышка")
	_check(reaction.get_node("Bubble/Eyebrow").visible and
		String(reaction.get_node("Bubble/Eyebrow").text).begins_with("ЭМОЦИОНАЛЬНЫЙ СРЫВ"),
		"эмоциональная реплика явно подписана в крупном плане")
	var statement_bubble := reaction.get_node("Bubble") as Control
	var speaker_plate := reaction.get_node("Bubble/SpeakerPlate") as ColorRect
	var speaker_label := reaction.get_node("Bubble/SpeakerPlate/SpeakerLabel") as Label
	var statement_label := reaction.get_node("Bubble/Label") as Label
	var centered := (
		is_equal_approx(statement_bubble.position.x,
			roundf((reaction.size.x - statement_bubble.size.x) * 0.5)) and
		is_equal_approx(statement_bubble.position.y,
			reaction.size.y - statement_bubble.size.y - 22.0) and speaker_label.text == "ВЫ" and
		speaker_plate.position.y < 0.0 and is_zero_approx(speaker_plate.position.y + speaker_plate.size.y) and
		is_equal_approx((statement_label.position.y + statement_label.size.y * 0.5),
			statement_bubble.size.y * 0.5)
	)
	reaction._layout_bubble("opp")
	centered = centered and is_equal_approx(statement_bubble.position.x,
		roundf((reaction.size.x - statement_bubble.size.x) * 0.5)) and speaker_label.text == "ОППОНЕНТ"
	_check(centered,
		"бабл реплики центрирован снизу и подписывает спикера без смещений влево/вправо")
	await reaction.scene_finished
	reaction.queue_free()

	# Интеграция с боевым экраном: уже открытый hover-бабл исчезает на scene_started,
	# а прямой повторный hover игнорируется до scene_finished.
	var screen = DebateScreen.instantiate()
	add_child(screen)
	await get_tree().process_frame
	var strain_bg: ColorRect = screen.get_node("EmotionHud/YouStrain/YouStrainBg")
	_check(strain_bg.size.y > strain_bg.size.x * 4.0,
		"HUD использует вертикальную шкалу напряжения")
	screen.controller.emotion.observe("you", "argument_lost", 4, {}, 0.99)
	screen._refresh()
	var strain_fill: ColorRect = screen.get_node("EmotionHud/YouStrain/YouStrainFill")
	_check(strain_fill.size.y > 0.0 and is_equal_approx(
		strain_fill.position.y + strain_fill.size.y,
		strain_bg.position.y + strain_bg.size.y),
		"вертикальная шкала заполняется снизу вверх")
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
