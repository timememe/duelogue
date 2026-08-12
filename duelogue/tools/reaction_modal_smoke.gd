extends Node

## Регрессия модальности микросцены: она должна перехватывать мышь, быть выше карточного UI
## и держать modal-active до полного завершения fade-out.

const ReactionScene := preload("res://duelogue/core/characters/reaction_scene.tscn")
const ComboNameBanner := preload("res://duelogue/ui/combo_name_banner.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
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
	var canon_matches := true
	for tuning_key: String in ComboNameBanner.TUNING_KEYS:
		canon_matches = canon_matches and banner.get(tuning_key) == \
			ComboNameBanner.CANON_TUNING[tuning_key]
	_check(canon_matches,
		"экспериментальные lab-ручки не меняют боевой дефолт ComboNameBanner")
	banner.apply_tuning({
		"back_layer_enabled": true,
		"back_layer_scale": 1.31,
		"back_layer_spikes": 9.0,
		"back_layer_rotation_offset_deg": 17.0,
	})
	banner.show_static_preview("Двойная проверка", "you")
	_check(banner._burst_back.visible and banner._burst_back.get_index() < banner._burst.get_index() and
		is_equal_approx(banner._burst_back.scale.x, 1.31) and
		is_equal_approx(float(banner._burst_back_mat.get_shader_parameter("spikes")), 9.0),
		"combo-banner поддерживает настраиваемую вторую фигуру отдельным задним слоем")
	_check(is_equal_approx(banner._burst_back.rotation_degrees,
		banner.burst_rotation_deg + 17.0),
		"фоновый слой получает независимый поворот относительно основной фигуры")
	banner.apply_tuning(ComboNameBanner.CANON_TUNING)
	var t0 := Time.get_ticks_msec()
	await banner.show_combo("Консенсус сильнее", "you")
	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
	var combo_weight_tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	var combo_name_font := banner._label.get_theme_font("font") as FontVariation
	var combo_kicker_font := banner._kicker.get_theme_font("font") as FontVariation
	_check(not banner._burst.visible and not banner._label.visible and
		banner._label.text == "КОНСЕНСУС СИЛЬНЕЕ" and
		banner._burst_mat.get_shader_parameter("burst_color") == banner.YOU_COLOR and
		elapsed >= 1.6 and elapsed <= 2.5,
		"баннер комбо показывает ИМЯ КОМБО капсом, держит 2.06с и гасится сам")
	_check(combo_name_font != null and combo_kicker_font != null and
		int(combo_name_font.variation_opentype.get(combo_weight_tag, 0)) == 900 and
		int(combo_kicker_font.variation_opentype.get(combo_weight_tag, 0)) == 900,
		"обе надписи combo-banner используют Sofia Sans Condensed Black (wght=900)")
	_check(banner._kicker.text == "КОМБО!" and
		not banner._kicker.has_theme_color_override("font_outline_color") and
		not banner._kicker.has_theme_constant_override("outline_size") and
		not banner._label.has_theme_color_override("font_outline_color") and
		not banner._label.has_theme_constant_override("outline_size"),
		"кикер «КОМБО!» и название приёма отображаются без аутлайна")
	_check(is_equal_approx(ReadingPace.banner_time(), 2.06),
		"ReadingPace учитывает задержку фонового слоя: combo-banner длится 2.06с")
	_check(is_zero_approx(banner._label.rotation_degrees) and
		is_zero_approx(banner._kicker.rotation_degrees),
		"надписи combo-banner остаются ровными, без наклона reaction-сцены")
	await banner.show_combo("Уклонился от источника", "opp")
	_check(banner._label.text == "УКЛОНИЛСЯ ОТ ИСТОЧНИКА" and
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
	probe.device_font_color = Color(0.9, 0.1, 0.1, 1.0)
	probe.show_utterance("you", "Проверка приёма", null, "", false, "", {}, "Контрпример")
	var line: ColorRect = probe.get_node("DeviceLine")
	var label: Label = probe.get_node("DeviceLabel")
	var portrait := probe.get_node("Portrait")
	var bg_shader := probe.get_node("BgShader")
	_check(line.visible and label.visible and label.text == "КОНТРПРИМЕР",
		"имя приёма показывается крупно и всегда переводится в UPPERCASE")
	_check(bg_shader.get_index() < line.get_index() and line.get_index() < label.get_index() and
		label.get_index() < portrait.get_index(),
		"порядок узлов: фоновые шейдеры → линия → текст приёма → герой поверх всех")
	var line_mat := line.material as ShaderMaterial
	var you_line_color: Color = probe.BUBBLE_YOU_COLOR
	you_line_color.a = 0.9
	_check(line_mat.get_shader_parameter("line_color") == you_line_color,
		"сторона 'you' красит акцентную линию в зелёный цвет игрока")
	_check(is_zero_approx(line.offset_left) and is_zero_approx(line.offset_right) and
		line.anchor_right == 1.0,
		"линия на всю ширину экрана, без отступов по краям")
	_check(label.get_theme_color("font_color") == probe.device_font_color,
		"цвет шрифта берётся из калибруемой переменной device_font_color")
	_check(not label.has_theme_color_override("font_outline_color"),
		"аутлайн у надписи приёма убран — только сплошной цвет")
	var black_font := label.get_theme_font("font") as FontVariation
	var weight_tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	_check(black_font != null and int(black_font.variation_opentype.get(weight_tag, 0)) == 900,
		"название приёма использует Sofia Sans Condensed Black (wght=900)")
	_check(probe.device_font_size == 128,
		"базовый размер названия приёма — 128px")
	_check(label.rotation_degrees >= probe.DEVICE_LABEL_TILT_MIN_DEG and
		label.rotation_degrees <= probe.DEVICE_LABEL_TILT_MAX_DEG,
		"случайный наклон названия лежит в диапазоне −10°…+10°")
	var you_w: float = probe.size.x / 3.0 + probe.device_label_size_delta.x
	_check(is_equal_approx(label.position.x, probe.size.x - you_w) and
		is_equal_approx(label.position.x + label.size.x, probe.size.x),
		"портрет 'you' слева → подпись приёма уходит в правую треть (+калибровка), прижатую к правому краю экрана")
	_check(label.position.x >= -0.5 and label.position.x + label.size.x <= probe.size.x + 0.5,
		"бокс подписи приёма стороны 'you' не вылезает за пределы экрана по X")
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, "Ы")
	_check(label.get_theme_font_size("font_size") == 128,
		"короткое имя приёма не сжимается ниже запрошенного калибруемого размера")
	var long_name := "Устоявшееся значение по определению без всякого сомнения"
	probe.show_utterance("you", "Проверка", null, "", false, "", {}, long_name)
	var fitted := label.get_theme_font_size("font_size")
	_check(fitted < 128 and fitted >= probe.DEVICE_FONT_MIN,
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
	var opp_line_color: Color = probe.BUBBLE_OPP_COLOR
	opp_line_color.a = 0.9
	_check(line_mat.get_shader_parameter("line_color") == opp_line_color and
		opp_line_color != you_line_color,
		"сторона 'opp' переключает акцентную линию на оранжевый цвет оппонента")
	var opp_w: float = probe.size.x / 3.0 + probe.device_label_size_delta.x
	_check(is_zero_approx(label.position.x) and
		is_equal_approx(label.position.x + label.size.x, opp_w),
		"портрет 'opp' справа → подпись приёма уходит в левую треть (+калибровка), прижатую к левому краю экрана")
	_check(label.position.x >= -0.5 and label.position.x + label.size.x <= probe.size.x + 0.5,
		"бокс подписи приёма стороны 'opp' не вылезает за пределы экрана по X")
	var seen_tilts := {}
	var all_tilts_in_range := true
	for i in 16:
		probe._layout_device_name("Проверка", "you")
		var tilt_key := snappedf(label.rotation_degrees, 0.001)
		seen_tilts[tilt_key] = true
		all_tilts_in_range = all_tilts_in_range and \
			label.rotation_degrees >= probe.DEVICE_LABEL_TILT_MIN_DEG and \
			label.rotation_degrees <= probe.DEVICE_LABEL_TILT_MAX_DEG
	_check(all_tilts_in_range and seen_tilts.size() > 1,
		"наклон пересчитывается для каждого показа и не залипает в одном значении")
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
