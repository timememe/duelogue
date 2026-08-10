extends Control

## DUELOGUE — ХАБ КАТАЛОГОВ: одна кнопка в главном меню («Каталог»), внутри — вкладки
## Колоды/Темы/Комбо/Персонажи вместо отдельных кнопок меню. Каждая вкладка — самостоятельная
## сцена (deck_catalog/theme_catalog/combo_catalog/character_catalog.tscn), инстанцируется в
## %TabContent при переключении; их собственная шапка (заголовок/«В меню») убрана из tscn —
## навигацией теперь владеет только хаб.
##
## Редакторы (deck_editor/theme_editor) возвращаются СЮДА, не на голую сцену каталога — иначе
## некуда вернуться к вкладкам. Какую вкладку открыть при возврате — static requested_tab
## (транзит-хэндофф, тот же приём, что Profile.editing_deck_id/ThemeLibrary.editing_theme_id).

const TAB_LABELS := ["Колоды", "Темы", "Комбо", "Персонажи"]
const TAB_SCENES := [
	preload("res://duelogue/ui/deck_catalog.tscn"),
	preload("res://duelogue/ui/theme_catalog.tscn"),
	preload("res://duelogue/ui/combo_catalog.tscn"),
	preload("res://duelogue/ui/character_catalog.tscn"),
]

## Хэндофф от deck_editor/theme_editor: какую вкладку открыть при возврате в хаб. Гасится сразу
## после чтения — следующий вход без явного запроса падает на дефолт (0), а не на прошлый выбор.
static var requested_tab := 0

@onready var _tab_bar: TabBar = %TabBar
@onready var _content: Control = %TabContent

var _current_scene: Node = null


func _ready() -> void:
	%BackBtn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn"))
	for label in TAB_LABELS:
		_tab_bar.add_tab(label)
	_tab_bar.tab_changed.connect(_select_tab)
	var start := clampi(requested_tab, 0, TAB_SCENES.size() - 1)
	requested_tab = 0
	_tab_bar.current_tab = start
	_select_tab(start)


func _select_tab(i: int) -> void:
	if _current_scene != null:
		_current_scene.queue_free()
		_current_scene = null
	_current_scene = TAB_SCENES[i].instantiate()
	_content.add_child(_current_scene)
