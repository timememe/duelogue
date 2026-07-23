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

## Баннер названия комбо (2026-07-23, ui/combo_name_banner.gd): панч-ин с перелётом → пауза →
## панч-аут, РОВНО 2 секунды суммарно (правка 2026-07-23 #3 — было 1с, мало для крупной
## надписи), ДО обычной сцены-реплики с портретом (show_utterance). Свои, отдельные от
## IMPACT_HOLD часы — баннер читается как отдельный, нейтральный жест самой игры.
const BANNER_PUNCH_IN := 0.2
const BANNER_HOLD := 1.5
const BANNER_PUNCH_OUT := 0.3


## Длительность одного баннера (панч-ин + пауза + панч-аут) — ровно 2.0, ВСЕГДА, независимо
## от CUTSCENES: баннер — не катсцена-реплика, а нейтральный эффект самой игры (см.
## combo_name_banner.gd/character_core._on_combo_verdict), играет и с выключенными катсценами.
static func banner_time() -> float:
	return BANNER_PUNCH_IN + BANNER_HOLD + BANNER_PUNCH_OUT


## Полная длительность вердикта комбо: баннер + сцена-реплика владельца (портрет+бабл).
## Пейсинг контроллера держит ровно столько же — держим единые часы, как и у обычной реплики.
static func combo_verdict_time(text: String) -> float:
	return banner_time() + scene_time(text)


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
