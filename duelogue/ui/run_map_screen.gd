extends Control

## DUELOGUE — ЭКРАН КАРТЫ ЗАБЕГА (чистый view слоя «Сезон», zal_run_v0.1 §6). Каркас UI
## авторится НОДАМИ в run_map_screen.tscn (шапка/скролл/панель комнаты/легенда — двигаются
## в редакторе); скрипт ссылается на них (%Name), рендерит состояние run_controller по
## сигналам EventBus и шлёт интенты. Динамика — узлы-кнопки и рёбра — строится кодом в
## %MapCanvas (рёбра рисуются в его draw-сигнале, кнопки — дети канваса).
## Самодостаточна: F6 на этой сцене стартует забег со случайным сидом.

const RunController := preload("res://duelogue/app/run_controller.gd")
const RoomTypes := preload("res://duelogue/core/run/room_types.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")

## Цвета типов комнат (узлы карты). Каркас/панель красятся в tscn.
const COL_ROOM := {
	RoomTypes.ROOM_EFIR: Color("6fcf7f"),
	RoomTypes.ROOM_ELITE: Color("d9594c"),
	RoomTypes.ROOM_SHOP: Color("ffd24a"),
	RoomTypes.ROOM_PREP: Color("6fb7cf"),
	RoomTypes.ROOM_EVENT: Color("c48fd9"),
	RoomTypes.ROOM_BOSS: Color("ff7a45"),
}
const COL_EDGE := Color(0.35, 0.38, 0.45, 0.8)
const COL_EDGE_WALKED := Color(0.44, 0.81, 0.5, 0.95)   ## пройденный маршрут
const COL_EDGE_OPEN := Color(0.95, 0.88, 0.55, 0.95)    ## доступные сейчас шаги
const COL_GOLD := Color("ffd24a")

# --- геометрия карты (слой = колонка, lane = ряд) ---
const NODE_W := 118.0
const NODE_H := 42.0
const LAYER_GAP := 172.0
const LANE_PITCH := 94.0
const MARGIN_X := 56.0

var controller: Node
var _btns := {}  ## node_id → Button (пересобираются на акт/забег)

@onready var _canvas: Control = %MapCanvas
@onready var _act_label: Label = %ActLabel
@onready var _res_label: Label = %ResLabel
@onready var _dimmer: ColorRect = %Dimmer
@onready var _panel: PanelContainer = %RoomPanel
@onready var _room_title: Label = %RoomTitle
@onready var _room_body: RichTextLabel = %RoomBody
@onready var _room_choices: VBoxContainer = %RoomChoices
@onready var _restart_btn: Button = %RestartBtn


func _ready() -> void:
	controller = RunController.new()
	add_child(controller)
	_restart_btn.pressed.connect(_on_restart)
	%MenuBtn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn"))
	_canvas.draw.connect(_draw_edges)
	_canvas.resized.connect(_layout_nodes)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_map_changed.connect(_refresh)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.room_resolved.connect(_on_room_resolved)
	EventBus.act_advanced.connect(_on_act_advanced)
	EventBus.run_ended.connect(_on_run_ended)
	controller.start_run()


# ----------------------------------------------------- карта (узлы и рёбра) ---

func _on_run_started(_info: Dictionary) -> void:
	_hide_panel()
	_rebuild_map()


func _on_act_advanced(_act: int) -> void:
	# Панель итога босса остаётся поверх — карта нового акта уже собрана позади неё.
	_rebuild_map()


func _rebuild_map() -> void:
	for id in _btns:
		(_btns[id] as Button).queue_free()
	_btns = {}
	var map: Dictionary = controller.state.map
	if map.is_empty():
		return
	var max_lanes := 1
	for s in map.sizes:
		max_lanes = maxi(max_lanes, int(s))
	_canvas.custom_minimum_size = Vector2(
		MARGIN_X * 2.0 + float(int(map.layers) - 1) * LAYER_GAP + NODE_W,
		float(max_lanes) * LANE_PITCH + 60.0)
	for id in map.nodes:
		var nd: Dictionary = map.nodes[id]
		var b := Button.new()
		b.text = "%s %s" % [RoomTypes.GLYPHS[nd.type], RoomTypes.SHORT[nd.type]]
		b.tooltip_text = _node_tooltip(nd)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", COL_ROOM[nd.type])
		b.add_theme_color_override("font_disabled_color", COL_ROOM[nd.type])
		b.pressed.connect(controller.enter_node.bind(int(nd.id)))
		_canvas.add_child(b)
		_btns[int(nd.id)] = b
	_layout_nodes()
	_refresh()


## Афиша узла в тултипе (§6 «каждый узел читается как афиша»).
func _node_tooltip(nd: Dictionary) -> String:
	if RoomTypes.is_battle(String(nd.type)):
		var eng: Dictionary = nd.engagement
		var side := "ЗА" if String(eng.side) == "pro" else "ПРОТИВ"
		var twist := ""
		if String(eng.get("twist", "")) != "":
			twist = " · твист: %s" % eng.twist
		return "%s: топить %s «%s» против %s (%s) · гонорар %d%s" % [
			RoomTypes.LABELS[nd.type], side, eng.topic, eng.opp_name, eng.opp_style, int(eng.fee), twist]
	if String(nd.type) == RoomTypes.ROOM_EVENT:
		return "%s: %s" % [RoomTypes.LABELS[nd.type], String(RunEvents.get_event(String(nd.event_id)).get("title", ""))]
	return String(RoomTypes.LABELS[nd.type])


func _layout_nodes() -> void:
	var map: Dictionary = controller.state.map if controller != null else {}
	if map.is_empty():
		return
	var cy := maxf(_canvas.size.y, _canvas.custom_minimum_size.y) / 2.0
	for id in _btns:
		var nd: Dictionary = map.nodes[id]
		var b: Button = _btns[id]
		b.size = Vector2(NODE_W, NODE_H)
		b.position = Vector2(
			MARGIN_X + float(int(nd.layer)) * LAYER_GAP,
			cy + (float(int(nd.lane)) - (float(int(nd.lanes)) - 1.0) / 2.0) * LANE_PITCH - NODE_H / 2.0)
	_canvas.queue_redraw()


func _refresh() -> void:
	if controller == null or controller.state.map.is_empty():
		return
	var st: RefCounted = controller.state
	for id in _btns:
		var b: Button = _btns[id]
		match String(st.node_status(id)):
			"open":
				b.disabled = false
				b.modulate = Color.WHITE
			"current":
				b.disabled = true
				b.modulate = COL_GOLD
			"cleared":
				b.disabled = true
				b.modulate = Color(1, 1, 1, 0.55)
			_:
				b.disabled = true
				b.modulate = Color(1, 1, 1, 0.3)
	_act_label.text = "Акт %d/%d · сид %d" % [st.act, st.acts_total, st.run_seed]
	_res_label.text = "Репутация %d · Гонорары %d" % [st.reputation, st.fees]
	_canvas.queue_redraw()


func _draw_edges() -> void:
	if controller == null or controller.state.map.is_empty():
		return
	var st: RefCounted = controller.state
	var map: Dictionary = st.map
	var walked := {}
	for e in st.walked_edges():
		walked["%d_%d" % [int(e[0]), int(e[1])]] = true
	var open := {}
	for id in st.reachable_ids():
		open[int(id)] = true
	for id in map.nodes:
		if not _btns.has(int(id)):
			continue
		var from: Button = _btns[int(id)]
		var p0: Vector2 = from.position + Vector2(NODE_W, NODE_H / 2.0)
		for t in map.nodes[id].next:
			if not _btns.has(int(t)):
				continue
			var to: Button = _btns[int(t)]
			var p1: Vector2 = to.position + Vector2(0.0, NODE_H / 2.0)
			var col := COL_EDGE
			var w := 1.5
			if walked.has("%d_%d" % [int(id), int(t)]):
				col = COL_EDGE_WALKED
				w = 3.0
			elif int(id) == int(st.current_id) and open.has(int(t)):
				col = COL_EDGE_OPEN
				w = 2.5
			_canvas.draw_line(p0, p1, col, w, true)


# ------------------------------------------------------- панель комнаты -------

func _on_room_entered(node: Dictionary) -> void:
	_show_panel()
	_clear_choices()
	var type := String(node.type)
	_room_title.text = "%s  %s" % [RoomTypes.GLYPHS[type], RoomTypes.LABELS[type]]
	if RoomTypes.is_battle(type):
		var eng: Dictionary = node.engagement
		var side := "ЗА" if String(eng.side) == "pro" else "ПРОТИВ"
		var rows := [
			"[b]ТЕМА:[/b] «%s»" % eng.topic,
			"[b]КОНТРАКТ:[/b] топить %s" % side,
			"[b]ОППОНЕНТ:[/b] %s · стиль %s" % [eng.opp_name, eng.opp_style],
			"[b]ГОНОРАР:[/b] %d" % int(eng.fee),
		]
		if String(eng.get("twist", "")) != "":
			rows.append("[b]СПЕЦ-ПРАВИЛО:[/b] %s (бестиарий §5 — подключится с боссами)" % eng.twist)
		rows.append("")
		rows.append("[color=#8a93a3]Боёвка подключится по лестнице §9 — конфиг боя (battle_config) уже готов. Пока исход выбирается заглушкой:[/color]")
		_room_body.text = "\n".join(rows)
		_add_choice("Победа (заглушка боя)", func() -> void: controller.resolve_room("win"))
		_add_choice("Поражение (заглушка боя)", func() -> void: controller.resolve_room("lose"))
	elif type == RoomTypes.ROOM_EVENT:
		var ev := RunEvents.get_event(String(node.event_id))
		_room_title.text = "?  %s" % String(ev.get("title", "Событие"))
		_room_body.text = "\n\n".join(ev.get("lines", []))
		var choices: Array = ev.get("choices", [])
		for i in choices.size():
			_add_choice(String(choices[i].label), controller.event_choice.bind(i))
	elif type == RoomTypes.ROOM_SHOP:
		_room_body.text = "Кулуары гудят, но прилавок пока пуст: торговец приёмами (замены в обойме, §1) появится на шаге 4 лестницы §9.\n\n[color=#8a93a3]Пока здесь только кофе и слухи.[/color]"
		_add_choice("Уйти", func() -> void: controller.resolve_room("done"))
	else:  # prep
		_room_body.text = "Комната подготовки: заготовка стартовой рамки, порядок колоды и разведка (§3) лягут сюда на шаге 4 лестницы §9.\n\n[color=#8a93a3]Пока — репетиция перед зеркалом.[/color]"
		_add_choice("Продолжить путь", func() -> void: controller.resolve_room("done"))


func _on_room_resolved(result: Dictionary) -> void:
	_clear_choices()
	var rows: Array = []
	var outcome := String(result.outcome)
	if outcome == "win":
		rows.append("[b]Эфир отработан — победа.[/b]")
	elif outcome == "lose":
		rows.append("[b]Эфир провален.[/b] Карьера продолжается, но счёт запомнит (§10.4).")
	var outro := String(result.get("outro", ""))
	if outro != "":
		rows.append(outro)
	rows.append("[color=#8a93a3]%s[/color]" % _fx_text(result.get("effects", {})))
	_room_body.text = "\n\n".join(rows)
	_add_choice("Продолжить", _hide_panel)


func _on_run_ended(outcome: String, info: Dictionary) -> void:
	_show_panel()
	_clear_choices()
	var titles := {"victory": "СЕЗОН ЗАКРЫТ", "cancelled": "ВЫ ОТМЕНЕНЫ", "abandoned": "СЕЗОН БРОШЕН"}
	var bodies := {
		"victory": "Все %d акта отработаны. Контракты закрыты, имя звучит из каждого эфира." % int(controller.state.acts_total),
		"cancelled": "Репутация выгорела до нуля — букинг молчит, эфиры отменены (§4).",
		"abandoned": "Вы сошли с тура на середине сезона.",
	}
	_room_title.text = String(titles.get(outcome, outcome))
	_room_body.text = "%s\n\n[color=#8a93a3]Комнат пройдено: %d · Репутация: %d · Гонорары: %d[/color]" % [
		String(bodies.get(outcome, "")), int(info.get("rooms", 0)),
		int(info.get("reputation", 0)), int(info.get("fees", 0))]
	_add_choice("Новый сезон", _on_restart)


func _on_restart() -> void:
	controller.start_run()


func _fx_text(fx: Dictionary) -> String:
	var parts: Array = []
	if int(fx.get("rep", 0)) != 0:
		parts.append("Репутация %+d" % int(fx.rep))
	if int(fx.get("fee", 0)) != 0:
		parts.append("Гонорар %+d" % int(fx.fee))
	return "Без последствий." if parts.is_empty() else " · ".join(parts)


func _add_choice(label: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(fn)
	_room_choices.add_child(b)


func _clear_choices() -> void:
	for c in _room_choices.get_children():
		c.queue_free()


func _show_panel() -> void:
	_dimmer.visible = true
	_panel.visible = true


func _hide_panel() -> void:
	_dimmer.visible = false
	_panel.visible = false
