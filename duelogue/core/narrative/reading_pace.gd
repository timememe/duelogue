extends RefCounted

## DUELOGUE — общий темп презентации реплики. ЕДИНЫЕ ЧАСЫ для мини-сцены реакции
## (reaction_scene.gd — фазы фейдов/печати) И пейсинга контроллера (battle_controller.gd —
## автоход/финал не начинаются, пока прошлая сцена не отыграла). Один источник правды —
## оба места читают отсюда, чтобы презентация и пейсинг логики никогда не расходились.
##
## Хронология одной катсцены-реплики (scene_time):
##   доска показывает ход (BOARD_BEAT) → фейд-ин крупного плана (FADE_IN) →
##   печать текста (type_time) → пауза на дочитывание (HOLD_AFTER_TEXT) → фейд-аут (FADE_OUT).

## Настройки (крутятся в меню «Настройки») — поэтому var, не const.
static var CHARS_PER_SEC := 30.0
## Тумблер катсцен-реплик (крупный план с баблом). Выключен → сцены не играются,
## реплики остаются в стенограмме/логе, пейсинг сжимается до короткого такта OFF_BEAT.
static var CUTSCENES := true

const HOLD_AFTER_TEXT := 1.0
const MIN_TYPE_TIME := 0.2
const MIN_CHARS_PER_SEC := 10.0
const MAX_CHARS_PER_SEC := 60.0

## Фазы катсцены (использует reaction_scene; контроллер учитывает их в scene_time).
const BOARD_BEAT := 0.35   ## пауза «ход лёг на доску» ДО крупного плана
const FADE_IN := 0.15
const FADE_OUT := 0.2
const IMPACT_HOLD := 0.4   ## вспышка-спидлайны яркого исхода
## Такт хода при выключенных катсценах: доска и лог успевают прочитаться.
const OFF_BEAT := 0.5


## Время печати текста (без хвостовой паузы) — tween typewriter-эффекта в reaction_scene.
static func type_time(text: String) -> float:
	return maxf(MIN_TYPE_TIME, float(text.length()) / CHARS_PER_SEC)


## Полное время «на реплику»: печать + пауза на дочитывание (без фейдов и BOARD_BEAT).
static func read_time(text: String) -> float:
	return type_time(text) + HOLD_AFTER_TEXT


## Полная длительность катсцены-реплики — пейсинг контроллера держит ровно столько,
## чтобы следующая реплика/исход НИКОГДА не обрывали текущую сцену.
static func scene_time(text: String) -> float:
	if not CUTSCENES:
		return OFF_BEAT
	return BOARD_BEAT + FADE_IN + read_time(text) + FADE_OUT


## Длительность сцены яркого исхода (show_impact).
static func impact_time() -> float:
	if not CUTSCENES:
		return 0.2
	return IMPACT_HOLD + FADE_OUT
