extends Panel

## DUELOGUE — ИКОНКА ПЕРКА/ДЕБАФА (кафедра). Круглая заглушка без арт-ассетов; вся логика
## тут — только кастомный тултип-бокс, следующий за курсором (Godot сам вызывает это по
## задержке наведения, если tooltip_text непусто — см. debate_screen.gd _status_icon()).
## Позиционирование/тайминг окна — забота движка; здесь только его визуальное содержимое.

func _make_custom_tooltip(for_text: String) -> Object:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.html("14181fee")
	sb.border_color = Color.html("e5b84b")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(9)
	box.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = for_text
	label.add_theme_color_override("font_color", Color.html("e8e8e8"))
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size = Vector2(180, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return box
