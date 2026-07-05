extends Control

## Main game screen — wires UI to GameState core logic.

var game_state: GameState
var ai_player_preview: AIBasic ## Only used if we want to highlight suggested card
var combo_flash_tween: Tween

@onready var player_box: ColorRect = %PlayerBox
@onready var opponent_box: ColorRect = %OpponentBox
@onready var player_logic_label: Label = %PlayerLogicLabel
@onready var player_emotion_label: Label = %PlayerEmotionLabel
@onready var player_points_label: Label = %PlayerPointsLabel
@onready var opponent_logic_label: Label = %OpponentLogicLabel
@onready var opponent_emotion_label: Label = %OpponentEmotionLabel
@onready var opponent_points_label: Label = %OpponentPointsLabel
@onready var scales_label: Label = %ScalesLabel
@onready var scales_bar: ScalesBar = %ScalesBar
@onready var turn_label: Label = %TurnLabel
@onready var card_area: PanelContainer = %CardArea
@onready var card_container: HBoxContainer = %CardContainer
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_label: RichTextLabel = %LogLabel
@onready var opponent_card_label: Label = %OpponentCardLabel
@onready var player_shield_label: Label = %PlayerShieldLabel
@onready var opponent_shield_label: Label = %OpponentShieldLabel
@onready var deck_info_label: Label = %DeckInfoLabel
@onready var player_tension_bar: ProgressBar = %PlayerTensionBar
@onready var opponent_tension_bar: ProgressBar = %OpponentTensionBar
@onready var combo_slots: Array[PanelContainer] = [%ComboSlot0, %ComboSlot1, %ComboSlot2]
@onready var combo_slot_labels: Array[Label] = [%ComboSlot0Label, %ComboSlot1Label, %ComboSlot2Label]
@onready var combo_flash_overlay: ColorRect = %ComboFlashOverlay
@onready var combo_flash_label: Label = %ComboFlashLabel


func _ready() -> void:
	_apply_static_styles()
	_start_match()


func _apply_static_styles() -> void:
	card_area.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.11, 0.14, 0.96), Color(0.45, 0.48, 0.56, 0.65)))
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.075, 0.09, 0.98), Color(0.32, 0.34, 0.42, 0.8)))


func _start_match() -> void:
	var deck := CardDatabase.get_deck("Кофе")
	if deck == null:
		push_error("Колода не найдена")
		return

	game_state = GameState.new()
	game_state.ai = AIBasic.new()
	game_state.initialize(deck, game_state.ai)

	game_state.turn_resolved.connect(_on_turn_resolved)
	game_state.point_scored.connect(_on_point_scored)
	game_state.match_over.connect(_on_match_over)
	game_state.combo_triggered.connect(_on_combo_triggered)

	_add_log("=== DUELOGUE: спор начинается ===")
	_add_log("Колода: %s" % deck.deck_name)
	var starter := "Вы начинаете." if game_state.is_player_turn else "Оппонент начинает."
	_add_log(starter)

	# If opponent starts, play their opening card (single half-turn, not full play_turn)
	if not game_state.is_player_turn:
		var opening_log := game_state.play_opening_ai()
		for line in opening_log:
			_add_log(line)

	_update_ui()


func _on_card_pressed(card: CardInstance, boost: bool = false) -> void:
	if game_state.phase == Enums.GamePhase.MATCH_OVER:
		return
	if card.is_used():
		return

	var log := game_state.play_turn(card, boost)
	for line in log:
		_add_log(line)
	_update_ui()


func _update_ui() -> void:
	if game_state == null:
		return

	var p := game_state.player
	var o := game_state.opponent

	# Stats
	player_logic_label.text = "Логика: %d/%d" % [p.logic, p.max_logic]
	player_emotion_label.text = "Эмоции: %d/%d" % [p.emotion, p.max_emotion]
	player_points_label.text = "Очки: %s" % _points_dots(p.points)
	player_shield_label.text = "Щит: %d" % p.shield if p.shield > 0 else ""
	player_tension_bar.max_value = CharacterStats.MAX_TENSION
	player_tension_bar.value = p.tension

	opponent_logic_label.text = "Логика: %d/%d" % [o.logic, o.max_logic]
	opponent_emotion_label.text = "Эмоции: %d/%d" % [o.emotion, o.max_emotion]
	opponent_points_label.text = "Очки: %s" % _points_dots(o.points)
	opponent_shield_label.text = "Щит: %d" % o.shield if o.shield > 0 else ""
	opponent_tension_bar.max_value = CharacterStats.MAX_TENSION
	opponent_tension_bar.value = o.tension

	var scales_val: int = game_state.scales_mgr.scales
	scales_label.text = "%+d" % scales_val if scales_val != 0 else "0"
	scales_bar.set_scales(scales_val, ScalesManager.SCALES_MAX)
	turn_label.text = "Ход %d" % game_state.turn_number
	deck_info_label.text = "Колода: вы %d / он %d | Сброс: вы %d / он %d" % [
		p.deck.size(), o.deck.size(),
		p.discard_pile.size(), o.discard_pile.size()
	]

	# Opponent last card
	if o.last_card:
		opponent_card_label.text = o.last_card.data.card_name
	else:
		opponent_card_label.text = "..."

	# Color boxes react to state
	_update_box_color(player_box, p)
	_update_box_color(opponent_box, o)

	# Render player hand
	_update_combo_track_ui()
	_render_hand()


func _render_hand() -> void:
	# Clear old cards
	for child in card_container.get_children():
		child.queue_free()

	if game_state.phase == Enums.GamePhase.MATCH_OVER:
		return

	for card in game_state.player.hand:
		if card.is_used():
			continue
		card_container.add_child(_build_card_view(card))


func _build_card_view(card: CardInstance) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(176, 224)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = card.data.description
	var base_style := _card_panel_style(card.data.category, false)
	var hover_style := _card_panel_style(card.data.category, true)
	panel.add_theme_stylebox_override("panel", base_style)
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", hover_style))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", base_style))
	panel.gui_input.connect(_on_card_panel_input.bind(card))

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	# Header: title + optional EX badge in top-right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	layout.add_child(header)

	var title := Label.new()
	title.text = card.data.card_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	header.add_child(title)

	var ex_available := game_state != null and game_state.player.tension > 0 \
		and card.data.effect != Enums.CardEffect.BURST
	if ex_available:
		header.add_child(_build_ex_badge(card))

	# Chip: category · effect (subtle metadata, no longer in a separate stacked label)
	var chip := Label.new()
	chip.text = "%s · %s" % [_category_str(card.data.category), _effect_str(card.data.effect)]
	chip.add_theme_font_size_override("font_size", 10)
	chip.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.78))
	layout.add_child(chip)

	# Quote — the actual debate line. Takes most of the card space.
	var quote := Label.new()
	quote.custom_minimum_size = Vector2(0, 108)
	quote.text = "«%s»" % _card_statement(card)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	quote.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quote.max_lines_visible = 5
	quote.clip_text = true
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	layout.add_child(quote)

	# Footer: uses counter only — no buttons.
	var footer := HBoxContainer.new()
	layout.add_child(footer)

	var uses := Label.new()
	uses.text = "×%d" % card.uses_left
	uses.add_theme_font_size_override("font_size", 11)
	uses.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 0.85))
	footer.add_child(uses)

	return panel


func _build_ex_badge(card: CardInstance) -> Button:
	var ex_btn := Button.new()
	ex_btn.text = "EX"
	ex_btn.tooltip_text = "Сыграть с накалом: +50% к эффекту, -1 шкала"
	ex_btn.custom_minimum_size = Vector2(36, 24)
	ex_btn.add_theme_font_size_override("font_size", 11)
	ex_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.32))
	ex_btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.55))
	ex_btn.pressed.connect(_on_card_pressed.bind(card, true))
	return ex_btn


func _on_card_panel_input(event: InputEvent, card: CardInstance) -> void:
	if event is InputEventMouseButton \
		and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT:
		_on_card_pressed(card, false)


func _card_panel_style(category: Enums.CardCategory, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _card_color(category)
	if hovered:
		style.bg_color = style.bg_color.lightened(0.12)
	style.border_color = Color(1, 1, 1, 0.30 if hovered else 0.14)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _panel_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _update_box_color(box: ColorRect, stats: CharacterStats) -> void:
	var total := stats.logic + stats.emotion
	var max_total := stats.max_logic + stats.max_emotion
	var ratio := float(maxi(total, 0)) / float(maxi(max_total, 1))
	if box == player_box:
		box.color = Color(0.2, 0.4, 1.0).lerp(Color(0.1, 0.1, 0.3), 1.0 - ratio)
	else:
		box.color = Color(1.0, 0.3, 0.3).lerp(Color(0.3, 0.1, 0.1), 1.0 - ratio)


func _update_combo_track_ui() -> void:
	var entries: Array = []
	if game_state != null and game_state.combo_track != null:
		entries = game_state.combo_track.get_window()

	var empty_slots := combo_slots.size() - entries.size()
	for i in combo_slots.size():
		var slot := combo_slots[i]
		var label := combo_slot_labels[i]
		var entry_index := i - empty_slots
		if entry_index < 0:
			label.text = "..."
			_style_combo_slot(slot, Color(0.12, 0.12, 0.16, 0.9), Color(0.35, 0.35, 0.42, 1.0))
			continue

		var entry: Dictionary = entries[entry_index]
		var card: CardInstance = entry.get("card", null)
		var owner: String = entry.get("owner", ComboRecipe.OWNER_ANY)
		if card == null or card.data == null:
			label.text = "..."
			_style_combo_slot(slot, Color(0.12, 0.12, 0.16, 0.9), Color(0.35, 0.35, 0.42, 1.0))
			continue

		label.text = "%s\n%s" % [
			_category_str(card.data.category),
			_short_card_name(card.data.card_name)
		]
		var base_color := Color(0.18, 0.34, 0.82, 0.95) if owner == ComboRecipe.OWNER_SELF else Color(0.72, 0.20, 0.18, 0.95)
		var border_color := Color(0.55, 0.72, 1.0, 1.0) if owner == ComboRecipe.OWNER_SELF else Color(1.0, 0.55, 0.48, 1.0)
		_style_combo_slot(slot, base_color, border_color)


func _style_combo_slot(slot: PanelContainer, bg_color: Color, border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	slot.add_theme_stylebox_override("panel", style)


func _short_card_name(card_name: String) -> String:
	if card_name.length() <= 18:
		return card_name
	return card_name.substr(0, 17) + "..."


func _add_log(text: String) -> void:
	log_label.append_text(text + "\n")
	# Auto-scroll
	await get_tree().process_frame
	log_label.scroll_to_line(log_label.get_line_count() - 1)


func _on_turn_resolved(_turn_log: Array[String]) -> void:
	_update_ui()


func _on_point_scored(is_player: bool, points: int) -> void:
	var who := "Вы" if is_player else "Оппонент"
	_add_log("[color=yellow]%s берёте очко. Всего: %d.[/color]" % [who, points])


func _on_match_over(player_won: bool, _reason: String) -> void:
	_update_ui()
	if player_won:
		_add_log("[color=green]=== ПОБЕДА ===[/color]")
	else:
		_add_log("[color=red]=== ПОРАЖЕНИЕ ===[/color]")
	# Show restart button
	var restart_btn := Button.new()
	restart_btn.text = "Ещё спор"
	restart_btn.custom_minimum_size = Vector2(200, 50)
	restart_btn.pressed.connect(func(): _start_match())
	card_container.add_child(restart_btn)


func _on_combo_triggered(recipe: ComboRecipe) -> void:
	combo_flash_label.text = recipe.display_name
	combo_flash_overlay.visible = true
	combo_flash_overlay.modulate.a = 1.0
	if combo_flash_tween:
		combo_flash_tween.kill()
	combo_flash_tween = create_tween()
	combo_flash_tween.tween_interval(0.8)
	combo_flash_tween.tween_property(combo_flash_overlay, "modulate:a", 0.0, 0.2)
	combo_flash_tween.tween_callback(Callable(self, "_hide_combo_flash"))


func _hide_combo_flash() -> void:
	combo_flash_overlay.visible = false
	combo_flash_overlay.modulate.a = 1.0


func _points_dots(pts: int) -> String:
	var s := ""
	for i in 3:
		s += "●" if i < pts else "○"
	return s


func _category_str(cat: Enums.CardCategory) -> String:
	match cat:
		Enums.CardCategory.ATTACK: return "АТАКА"
		Enums.CardCategory.DEFENSE: return "ЗАЩИТА"
		Enums.CardCategory.EVASION: return "УКЛОН"
	return "?"


func _effect_str(effect: Enums.CardEffect) -> String:
	match effect:
		Enums.CardEffect.LOGIC: return "логика"
		Enums.CardEffect.EMOTION: return "эмоции"
		Enums.CardEffect.HEAL_LOGIC: return "хил логики"
		Enums.CardEffect.HEAL_EMOTION: return "хил эмоций"
		Enums.CardEffect.SHIELD: return "щит"
		Enums.CardEffect.CANCEL: return "отмена"
		Enums.CardEffect.MIRROR: return "зеркало"
		Enums.CardEffect.REFLECT: return "контратака"
		Enums.CardEffect.RANDOM: return "случайно"
		Enums.CardEffect.BURST: return "срыв"
	return "эффект"


func _card_statement(card: CardInstance) -> String:
	var statement := card.get_text()
	if statement == "":
		statement = card.data.description
	return statement


func _card_color(cat: Enums.CardCategory) -> Color:
	match cat:
		Enums.CardCategory.ATTACK: return Color(0.46, 0.13, 0.13, 0.96)
		Enums.CardCategory.DEFENSE: return Color(0.12, 0.34, 0.22, 0.96)
		Enums.CardCategory.EVASION: return Color(0.48, 0.40, 0.12, 0.96)
	return Color(0.20, 0.20, 0.24, 0.96)
