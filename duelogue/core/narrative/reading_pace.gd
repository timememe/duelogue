extends RefCounted

## DUELOGUE — общий темп чтения реплики. Единая формула для мини-сцены реакции
## (reaction_scene.gd — печатает текст этим темпом) И пейсинга контроллера
## (battle_controller.gd — не даёт автоходу ИИ/клинча оборвать предыдущую реплику раньше,
## чем её реально можно прочитать). Один источник правды — оба места читают отсюда, чтобы
## презентация и пейсинг логики никогда не расходились.

## Настройка (крутится слайдером в меню «Настройки») — поэтому var, не const.
static var CHARS_PER_SEC := 30.0
const HOLD_AFTER_TEXT := 1.0
const MIN_TYPE_TIME := 0.2
const MIN_CHARS_PER_SEC := 10.0
const MAX_CHARS_PER_SEC := 60.0


## Время печати текста (без хвостовой паузы) — tween typewriter-эффекта в reaction_scene.
static func type_time(text: String) -> float:
	return maxf(MIN_TYPE_TIME, float(text.length()) / CHARS_PER_SEC)


## Полное время «на реплику»: печать + пауза на дочитывание. Пейсинг контроллера берёт это
## как МИНИМУМ перед следующим автоматическим действием (см. battle_controller._wait_pace).
static func read_time(text: String) -> float:
	return type_time(text) + HOLD_AFTER_TEXT
