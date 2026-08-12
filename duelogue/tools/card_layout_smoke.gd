extends SceneTree

const CardScene := preload("res://duelogue/ui/card/card.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== CARD LAYOUT · SMOKE ===")
	await process_frame
	await process_frame
	await _check_type_badge()
	await _check_body("Короткий текст в одну строку.", "короткий текст сохраняет исходный кегль")
	await _check_body("Многострочная формулировка с длинными словами, ручными\nпереводами строк и " +
		"достаточно подробным объяснением эффекта карты, чтобы проверить реальную высоту " +
		"после переноса по ширине.", "многострочный текст помещается в поле")
	await _check_body("Очень длинное описание. ".repeat(45),
		"экстремальный текст обрезается многоточием, а не выходит за пределы")
	print("=== CARD LAYOUT: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check_type_badge() -> void:
	var card: Button = CardScene.instantiate()
	root.add_child(card)
	card.setup({"type": "U", "name": "Рамка"}, "Рамка", "Проверка жетона", true)
	await process_frame
	var icon := card.get_node("%TypeIcon") as TextureRect
	var template := card.get_node("%CardTemplate") as TextureRect
	var title := card.get_node("%Title") as Label
	var ok := icon.size.x >= 32.0 and is_equal_approx(icon.size.x, icon.size.y) \
		and icon.position.y < 0.0 and icon.z_index > template.z_index \
		and not card.clip_contents and title.position.x >= 34.0
	print("  %s · круглый жетон крупный, вынесен над рамкой и лежит верхним слоем" % \
		["OK" if ok else "FAIL"])
	if not ok:
		failures += 1
	card.queue_free()


func _check_body(source: String, label: String) -> void:
	var card: Button = CardScene.instantiate()
	root.add_child(card)
	card.setup({"type": "T", "name": "Проверка"}, "Проверка", source, true)
	await process_frame
	await process_frame
	var text_area := card.get_node("%TextArea") as Control
	var body := card.get_node("%Body") as Label
	var rendered_height := float(body.get_line_count() * body.get_line_height())
	var fits := rendered_height <= text_area.size.y - 2.0 and body.clip_text
	if source.length() < 40:
		fits = fits and body.get_theme_font_size("font_size") == 10
	if source.length() > 300:
		fits = fits and body.text.ends_with("…")
	print("  %s · %s" % ["OK" if fits else "FAIL", label])
	if not fits:
		failures += 1
	card.queue_free()
