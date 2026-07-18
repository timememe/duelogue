extends Control

## DUELOGUE — ГЛАВНОЕ МЕНЮ (main scene). Навигация сцен: катка (debate_screen),
## сезон (run_map_screen), редактор колоды (deck_editor); настройки — панель поверх
## (пишутся в autoload Profile и персистятся). Каркас — нодами в main_menu.tscn.

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

@onready var _deck_summary: Label = %DeckSummary
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _speed_label: Label = %SpeedLabel
@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _cuts_check: CheckButton = %CutsCheck
@onready var _opp_option: OptionButton = %OppOption


func _ready() -> void:
	%BattleBtn.pressed.connect(_go.bind("res://duelogue/ui/debate_screen.tscn"))
	%RunBtn.pressed.connect(_go.bind("res://duelogue/ui/run_map_screen.tscn"))
	%DeckBtn.pressed.connect(_go.bind("res://duelogue/ui/deck_editor.tscn"))
	%ComboBtn.pressed.connect(_go.bind("res://duelogue/ui/combo_catalog.tscn"))
	%SettingsBtn.pressed.connect(_open_settings)
	%QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	%CloseSettingsBtn.pressed.connect(func() -> void: _settings_panel.visible = false)
	_deck_summary.text = "Обойма: %s" % Profile.deck_summary()
	_init_settings()


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
