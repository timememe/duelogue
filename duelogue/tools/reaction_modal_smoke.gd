extends Node

## Регрессия модальности микросцены: она должна перехватывать мышь, быть выше карточного UI
## и держать modal-active до полного завершения fade-out.

const ReactionScene := preload("res://duelogue/core/characters/reaction_scene.tscn")
const ComboNameBanner := preload("res://duelogue/ui/combo_name_banner.gd")
const DebateScreen := preload("res://duelogue/ui/debate_screen.tscn")
const ShotDirector := preload("res://duelogue/core/director/shot_director.gd")
const CameraCassettes := preload("res://duelogue/core/director/camera_cassettes.gd")

var failures := 0
var starts := 0
var finishes := 0


func _ready() -> void:
	_check_shot_director()
	_check_device_name()

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

	# Баннер названия комбо (2026-07-23): НЕ узел reaction_scene и не его модальность — отдельный
	# combo_name_banner.gd. Показывает ИМЯ комбо (не generic-слово «ЗАЩИТА!»/«ЛОВУШКА!»,
	# которое ничего не говорит о том, выиграл ли игрок); победитель читается ТОЛЬКО по цвету
	# дизер-звезды (правка #2 — без дублирующей текстовой подписи), доигрывает панч-ин/пауза/
	# панч-аут сам за 2с (правка #3) и гасится, не трогая reaction_scene вообще (character_core
	# секвенирует: await show_combo → show_utterance, и НЕ гейтит его CUTSCENES).
	var banner: Control = ComboNameBanner.new()
	add_child(banner)
	var t0 := Time.get_ticks_msec()
	await banner.show_combo("Консенсус сильнее", "you")
	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
	_check(not banner._burst.visible and not banner._label.visible and
		banner._label.text == "Консенсус сильнее" and
		banner._burst_mat.get_shader_parameter("burst_color") == banner.YOU_COLOR and
		elapsed >= 1.6 and elapsed <= 2.5,
		"баннер комбо показывает ИМЯ комбо, держит 2с и гасится сам")
	await banner.show_combo("Уклонился от источника", "opp")
	_check(banner._label.text == "Уклонился от источника" and
		banner._burst_mat.get_shader_parameter("burst_color") == banner.OPP_COLOR,
		"победа оппонента красит дизер-звезду в его цвет")
	banner.queue_free()

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
	# Тип карты/приём в живом логе (2026-07-22): meta.device теперь рендерится в саму строку
	# лога боевого экрана, не только в файловую стенограмму (battle_controller._say).
	EventBus.utterance.emit("you", "Тестовый тезис.", {"stance": "против ананаса", "device": "Корреляция"})
	_check(String(screen.log_lines[-1]).contains("против ананаса · Корреляция") and
		String(screen.log_lines[-1]).contains("Тестовый тезис."),
		"живой лог показывает приём/схему рядом с репликой, не только файловая стенограмма")
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


## Кассетный режиссёр (context/director_core_v0.1.md) — чистая логика, без сцены: детерминизм
## по seed, отсутствие немедленного повтора в мешке, безопасный пустой результат вне каталога.
## Плюс минимальная интеграция: show_utterance с реальной кассетой не роняет reaction_scene.
func _check_shot_director() -> void:
	var director_a := ShotDirector.new()
	director_a.start(CameraCassettes.data(), 777)
	var director_b := ShotDirector.new()
	director_b.start(CameraCassettes.data(), 777)
	var same_seed_matches := true
	for i in 12:
		var da := director_a.draw("you", "burst")
		var db := director_b.draw("you", "burst")
		if String(da.get("id", "")) != String(db.get("id", "")):
			same_seed_matches = false
	_check(same_seed_matches,
		"ShotDirector детерминирован: одинаковый seed даёт одинаковую серию вытягиваний")

	var director_c := ShotDirector.new()
	director_c.start(CameraCassettes.data(), 42)
	var no_immediate_repeat := true
	var last_id := ""
	for i in 40:
		var cassette := director_c.draw("opp", "declare")
		var cur_id := String(cassette.get("id", ""))
		if cur_id == "" or (i > 0 and cur_id == last_id):
			no_immediate_repeat = false
		last_id = cur_id
	_check(no_immediate_repeat,
		"мешок кассет для declare (2+ варианта в каталоге) не повторяет одну и ту же кассету дважды подряд")

	var unknown_state := director_c.draw("opp", "no_such_state")
	_check(unknown_state.is_empty(), "стейт вне каталога кассет не роняет director — просто пустой результат")

	var cassette_probe := ReactionScene.instantiate()
	add_child(cassette_probe)
	var burst_cassette := director_c.draw("you", "burst")
	_check(not burst_cassette.is_empty(), "burst покрыт каталогом кассет (draw вернул непустую)")
	cassette_probe.show_utterance("you", "Проверка кассеты", null, "burst", false, "", burst_cassette)
	_check(cassette_probe._gen == 1, "show_utterance с непустой кассетой реально запускается")
	cassette_probe.queue_free()


## Имя приёма за героем (DeviceLine/DeviceLabel, reaction_scene.gd): видимость по непустому
## аргументу, порядок узлов кодирует «за героем, но над фоновыми шейдерами», калибруемые
## переменные реально долетают до узлов, show_impact и пустое имя прячут оба узла обратно.
func _check_device_name() -> void:
	var probe = ReactionScene.instantiate()
	add_child(probe)
	probe.device_line_color = Color(0.1, 0.2, 0.9, 1.0)
	probe.device_font_size = 48
	probe.device_font_color = Color(0.9, 0.1, 0.1, 1.0)
	probe.show_utterance("you", "Проверка приёма", null, "", false, "", {}, "КОНТРПРИМЕР")
	var line: ColorRect = probe.get_node("DeviceLine")
	var label: Label = probe.get_node("DeviceLabel")
	var portrait := probe.get_node("Portrait")
	var bg_shader := probe.get_node("BgShader")
	_check(line.visible and label.visible and label.text == "КОНТРПРИМЕР",
		"имя приёма показывается крупно, когда его передали")
	_check(bg_shader.get_index() < line.get_index() and line.get_index() < label.get_index() and
		label.get_index() < portrait.get_index(),
		"порядок узлов: фоновые шейдеры → линия → текст приёма → герой поверх всех")
	var line_mat := line.material as ShaderMaterial
	_check(line_mat.get_shader_parameter("line_color") == probe.device_line_color,
		"цвет линии берётся из калибруемой переменной device_line_color")
	_check(is_zero_approx(line.offset_left) and is_zero_approx(line.offset_right) and
		line.anchor_right == 1.0,
		"линия на всю ширину экрана, без отступов по краям")
	_check(label.get_theme_color("font_color") == probe.device_font_color,
		"цвет шрифта берётся из калибруемой переменной device_font_color")
	_check(not label.has_theme_color_override("font_outline_color"),
		"аутлайн у надписи приёма убран — только сплошной цвет")
	var you_w: float = probe.size.x / 3.0 + probe.device_label_size_delta.x
	_check(is_equal_approx(label.position.x, probe.size.x - you_w) and
		is_equal_approx(label.position.x + label.size.x, probe.size.x),
		"портрет 'you' слева → подпись приёма уходит в правую треть (+калибровка), прижатую к правому краю экрана")
	_check(label.position.x >= -0.5 and label.position.x + label.size.x <= probe.size.x + 0.5,
		"бокс подписи приёма стороны 'you' не вылезает за пределы экрана по X")
	probe.device_font_size = 40
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, "Ы")
	_check(label.get_theme_font_size("font_size") == 40,
		"короткое имя приёма не сжимается ниже запрошенного калибруемого размера")
	probe.device_font_size = 64
	var long_name := "Устоявшееся значение по определению без всякого сомнения"
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, long_name)
	var fitted := label.get_theme_font_size("font_size")
	_check(fitted < 64 and fitted >= probe.DEVICE_FONT_MIN,
		"длинное многословное имя приёма сжимается до нижнего порога, не ломая вёрстку")
	_check(label.autowrap_mode == TextServer.AUTOWRAP_WORD,
		"перенос строго по словам (AUTOWRAP_WORD, не _SMART) — буквы одного слова никогда не рвутся на две строки")
	var probe_font := label.get_theme_font("font")
	var widest_word_w := 0.0
	for word in long_name.split(" ", false):
		widest_word_w = maxf(widest_word_w,
			probe_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x)
	var box_w: float = probe.size.x * (1.0 - 2.0 / 3.0) + probe.device_label_size_delta.x
	_check(widest_word_w <= box_w + 0.5,
		"на подобранном размере шрифта даже самое широкое слово укладывается в ширину бокса — переносить по буквам не требуется")
	_check(label.get_theme_constant("line_spacing") == probe.device_label_line_spacing,
		"межстрочный интервал берётся из калибруемой переменной device_label_line_spacing")
	probe.show_utterance("opp", "Проверка приёма", null, "", false, "", {}, "ИСТОЧНИК?")
	var opp_w: float = probe.size.x / 3.0 + probe.device_label_size_delta.x
	_check(is_zero_approx(label.position.x) and
		is_equal_approx(label.position.x + label.size.x, opp_w),
		"портрет 'opp' справа → подпись приёма уходит в левую треть (+калибровка), прижатую к левому краю экрана")
	_check(label.position.x >= -0.5 and label.position.x + label.size.x <= probe.size.x + 0.5,
		"бокс подписи приёма стороны 'opp' не вылезает за пределы экрана по X")
	# Калибруемая добавка к боксу (2026-08-07) — точечная подстройка поверх авто-раскладки,
	# не должна копиться от вызова к вызову (иначе бокс уезжал/рос бы с каждой новой репликой).
	probe.device_label_size_delta = Vector2(20.0, 10.0)
	probe.device_label_offset = Vector2(15.0, -5.0)
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, "ПРОВЕРКА")
	var size_after_first := label.size
	var pos_after_first := label.position
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, "ПРОВЕРКА")
	_check(label.size.is_equal_approx(size_after_first) and
		label.position.is_equal_approx(pos_after_first),
		"калибруемые device_label_size_delta/device_label_offset не копятся при повторных вызовах")
	probe.device_label_size_delta = Vector2.ZERO
	probe.device_label_offset = Vector2.ZERO
	probe.show_utterance("you", "Без приёма", null)
	_check(not line.visible and not label.visible,
		"пустое имя приёма (старый вызов show_utterance) снова прячет линию и текст")
	probe.show_impact("you", null, 0.5)
	_check(not line.visible and not label.visible,
		"show_impact прячет имя приёма, не оставляет прошлый кадр висеть")
	probe.queue_free()


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
