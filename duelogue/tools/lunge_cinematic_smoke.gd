extends Node

## Интеграционный smoke кинематографа «Выпада» (context/situational_cards_v0.1.md §3.5):
## настоящий debate_screen, подписанный на EventBus.lunge_started/resolved, ставит слоумо
## (Engine.time_scale) на открытии окна и ВОССТАНАВЛИВАЕТ его на закрытии — плюс страховки.
## Проверка развязана от жизненного цикла матча: бьём прямо по сигналам (само окно/решение
## покрывает lunge_controller_smoke). Долли (character_core) и раскладку модалки headless не
## проверить — это на глаз в tools/lunge_drill.tscn.
## Запуск:
##   Godot --headless --path . res://duelogue/tools/lunge_cinematic_smoke.tscn

const DebateScreen := preload("res://duelogue/ui/debate_screen.tscn")

var failures := 0
var _screen: Control


func _ready() -> void:
	_screen = DebateScreen.instantiate()
	add_child(_screen)
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


func _run() -> void:
	print("\n=== LUNGE CINEMATIC SMOKE ===")
	await get_tree().process_frame
	await get_tree().process_frame
	Engine.time_scale = 1.0   ## чистим за возможным мусором стартового кадра

	# --- открытие окна: слоумо + модалка ---
	EventBus.lunge_started.emit("you", "Источник подтверждён")
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, _screen.LUNGE_TIME_SCALE)
		and Engine.time_scale < 1.0,
		"lunge_started → слоумо включён (Engine.time_scale=%.2f)" % Engine.time_scale)
	_check(_screen._lunge_overlay != null and _screen._lunge_overlay.visible,
		"lunge_started → модалка показана")
	_check(_screen._lunge_active, "lunge_started → стенной таймер активен")
	_check(String(_screen._lunge_title.text).contains("ИСТОЧНИК ПОДТВЕРЖДЁН"),
		"шапка модалки несёт имя маршрута")

	# --- закрытие окна: слоумо снят, модалка убрана ---
	EventBus.lunge_resolved.emit("guard")
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"lunge_resolved → слоумо восстановлен (Engine.time_scale=%.2f)" % Engine.time_scale)
	_check(not _screen._lunge_overlay.visible, "lunge_resolved → модалка скрыта")
	_check(not _screen._lunge_active, "lunge_resolved → стенной таймер остановлен")

	# --- страховка на abort (протухший epoch в _ask_lunge) ---
	EventBus.lunge_started.emit("you", "M")
	await get_tree().process_frame
	EventBus.lunge_resolved.emit("abort")
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0) and not _screen._lunge_active,
		"lunge_resolved(abort) тоже снимает слоумо")

	# --- страховка: рестарт партии не наследует слоумо/модалку ---
	EventBus.lunge_started.emit("you", "M")
	await get_tree().process_frame
	EventBus.match_started.emit({})
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0) and not _screen._lunge_active
		and not _screen._lunge_overlay.visible,
		"_on_match_started снимает унаследованный слоумо/модалку")

	Engine.time_scale = 1.0
	print("=== LUNGE CINEMATIC: %s ===\n" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
