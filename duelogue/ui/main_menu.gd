extends Control

## DUELOGUE — ГЛАВНОЕ МЕНЮ (main scene). Навигация сцен: подготовка к катке (debate_setup), сезон
## (run_map_screen), каталог (catalog_hub — одна кнопка, внутри вкладки Колоды/Темы/Комбо;
## Колоды/Темы дальше ведут в свои редакторы на конкретную запись); настройки — панель
## поверх (пишутся в autoload Profile и персистятся). Каркас — нодами в main_menu.tscn.
##
## ВИТРИНА (2026-08-18): лого — верхняя четверть слева, кнопки — левая треть под ним, два
## бойца (синий игрок спереди, красная оппонентка сзади) — правая треть, тем же дизер-
## материалом, что и в бою (character_core/stage.tscn — переиспользован, не переизобретён).
## Фон живой в два дизер-слоя: mood_bg.gdshader на весь экран (тот же шейдер, что живой фон
## крупного плана реплики) и пара вращающихся дизер-звёзд позади бойцов (dither_star.gdshader —
## та же форма/дизер-край, что звезда ComboNameBanner, вынесенная в отдельный ассет).
##
## КРОЙ «ПЕРСОНА» (2026-08-18, правка по запросу): кнопки — не скруглённые StyleBoxFlat, а
## диагонально срезанные шевроны (dither_slash.gdshader — discard по UV.x, край нарочно резкий/
## aliased, не сглажен; заливка квантована Байером, как везде в проекте). Технически каждая
## кнопка — пара нод (main_menu.tscn: *Wrap → Bg с шейдером + прозрачный Button поверх), потому
## что у StyleBox нет шейдер-хука; см. _wire_button_juice/_on_button_hover — фидбэк на
## hover/focus теперь скриптом (модуляция Bg + панч масштаба обёртки), а не сменой стилбоксов.
## Текст кнопок — SofiaSansCondensed-Black (НЕ AntonSC: тот в проекте ни разу не проверен на
## кириллице, используется только для латинского wordmark «DUELOGUE»). Входная анимация — белая
## вспышка-срез (_flash_wipe) поверх жёсткого TRANS_EXPO-влёта (без пружинного отскока), дальше
## только вращение звёзд (_process).

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

@onready var _deck_summary: Label = %DeckSummary
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _speed_label: Label = %SpeedLabel
@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _cuts_check: CheckButton = %CutsCheck
@onready var _opp_option: OptionButton = %OppOption

@onready var _logo_block: Control = %LogoBlock
@onready var _buttons_col: VBoxContainer = %Buttons
@onready var _characters: Node2D = %Characters
@onready var _star_back: ColorRect = %StarBack
@onready var _star_front: ColorRect = %StarFront
@onready var _ambient_mat: ShaderMaterial = %AmbientBg.material as ShaderMaterial
@onready var _flash_wipe: ColorRect = %FlashWipe

const STAR_BACK_SPIN_DEG := 4.0    # °/сек — дальняя звезда за бойцами, медленный ход
const STAR_FRONT_SPIN_DEG := -7.0  # °/сек — встречное вращение второго слоя (параллакс)
const AMBIENT_LINE_INTENSITY := 0.26  # мощность живого фона в покое (см. mood_bg.gdshader)


func _ready() -> void:
	%BattleBtn.pressed.connect(_go.bind("res://duelogue/ui/debate_setup.tscn"))
	%RunBtn.pressed.connect(_go.bind("res://duelogue/ui/run_map_screen.tscn"))
	%CatalogBtn.pressed.connect(_go.bind("res://duelogue/ui/catalog_hub.tscn"))
	%SettingsBtn.pressed.connect(_open_settings)
	%QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	%CloseSettingsBtn.pressed.connect(func() -> void: _settings_panel.visible = false)
	var active_deck := Profile.get_deck_entry(Profile.active_deck_id)
	_deck_summary.text = "Обойма «%s»: %s" % [String(active_deck.get("name", "?")), Profile.deck_summary()]
	_init_settings()
	_wire_button_juice()
	_play_intro()


func _process(delta: float) -> void:
	_star_back.rotation_degrees += STAR_BACK_SPIN_DEG * delta
	_star_front.rotation_degrees += STAR_FRONT_SPIN_DEG * delta


func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)


# ------------------------------------------------------------- настройки ------

func _init_settings() -> void:
	_speed_slider.min_value = ReadingPace.MIN_CHARS_PER_SEC
	_speed_slider.max_value = ReadingPace.MAX_CHARS_PER_SEC
	_speed_slider.step = 2.0
	_speed_slider.value = float(Profile.settings.get("chars_per_sec", 30.0))
	_speed_slider.value_changed.connect(_on_speed_changed)
	_on_speed_changed(_speed_slider.value)
	_cuts_check.set_pressed_no_signal(bool(Profile.settings.get("cutscenes", true)))
	_cuts_check.toggled.connect(func(v: bool) -> void: Profile.set_setting("cutscenes", v))
	var active := String(Profile.settings.get("opp_style", "smart"))
	for i in Profile.OPP_STYLES.size():
		var s := String(Profile.OPP_STYLES[i])
		_opp_option.add_item(s, i)
		if s == active:
			_opp_option.select(i)
	_opp_option.item_selected.connect(func(i: int) -> void:
		Profile.set_setting("opp_style", String(Profile.OPP_STYLES[i])))


func _on_speed_changed(v: float) -> void:
	_speed_label.text = "Скорость печати текста: %d симв/с" % int(v)
	Profile.set_setting("chars_per_sec", v)


func _open_settings() -> void:
	_settings_panel.visible = true


# --------------------------------------------------------------- витрина ------

## Кнопка теперь составная (main_menu.tscn: *Wrap/Bg+Button — диагональная плашка-шеврон
## рисуется дизер-шейдером на Bg, сам Button прозрачный, только хитбокс+текст), поэтому фидбэк
## живёт в скрипте, а не в normal/hover/pressed стилбоксах: на входе курсора — панч масштаба
## всей обёртки (Bg едет вместе с Button) + подсветка Bg модуляцией. focus_entered/exited
## дублируют то же самое для клавиатурной навигации (mouse_entered на неё не реагирует).
func _wire_button_juice() -> void:
	for b: Button in [%BattleBtn, %RunBtn, %CatalogBtn, %SettingsBtn, %QuitBtn]:
		var wrap := b.get_parent() as Control
		var bg := wrap.get_node("Bg") as ColorRect
		b.mouse_entered.connect(_on_button_hover.bind(wrap, bg, true))
		b.mouse_exited.connect(_on_button_hover.bind(wrap, bg, false))
		b.focus_entered.connect(_on_button_hover.bind(wrap, bg, true))
		b.focus_exited.connect(_on_button_hover.bind(wrap, bg, false))


func _on_button_hover(wrap: Control, bg: ColorRect, hovering: bool) -> void:
	wrap.pivot_offset = wrap.size / 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(wrap, "scale", Vector2.ONE * (1.035 if hovering else 1.0), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(bg, "modulate", Color(1.25, 1.25, 1.25, 1.0) if hovering else Color(1, 1, 1, 1), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_ambient_intensity(v: float) -> void:
	_ambient_mat.set_shader_parameter("line_intensity", v)


## Входной прогон (один раз при открытии меню): резкая белая вспышка-срез (в духе Persona)
## перекрывает первый кадр — под ней лого/бойцы/кнопки уже жёстко влетают на место (TRANS_EXPO/
## EASE_OUT — «встало и замерло», без пружинного отскока TRANS_BACK, который был раньше), звёзды
## и живой фон проявляются последними. Тот же почерк, что у ComboNameBanner.show_combo — не
## копия кода, тот же вкус резкого движения.
func _play_intro() -> void:
	var logo_x := _logo_block.position.x
	var buttons_x := _buttons_col.position.x
	var chars_x := _characters.position.x

	_flash_wipe.modulate.a = 1.0
	_logo_block.modulate.a = 0.0
	_logo_block.position.x = logo_x - 46.0
	_buttons_col.modulate.a = 0.0
	_buttons_col.position.x = buttons_x - 36.0
	_characters.modulate.a = 0.0
	_characters.position.x = chars_x + 60.0
	_star_back.modulate.a = 0.0
	_star_front.modulate.a = 0.0
	_set_ambient_intensity(0.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_flash_wipe, "modulate:a", 0.0, 0.2) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo_block, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo_block, "position:x", logo_x, 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_characters, "modulate:a", 1.0, 0.4).set_delay(0.06)
	tw.tween_property(_characters, "position:x", chars_x, 0.45).set_delay(0.06) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_buttons_col, "modulate:a", 1.0, 0.3).set_delay(0.14)
	tw.tween_property(_buttons_col, "position:x", buttons_x, 0.35).set_delay(0.14) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_star_back, "modulate:a", 1.0, 0.7).set_delay(0.25)
	tw.tween_property(_star_front, "modulate:a", 1.0, 0.7).set_delay(0.35)
	tw.tween_method(Callable(self, "_set_ambient_intensity"), 0.0, AMBIENT_LINE_INTENSITY, 0.9) \
		.set_delay(0.15)
