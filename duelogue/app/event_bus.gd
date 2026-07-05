extends Node

## DUELOGUE — ШИНА СОБЫТИЙ ПАРТИИ (autoload "EventBus").
## Контракт, на который подписываются UI и будущие ядра сцены/персонажей. Эмитит
## battle_controller (единственный владелец потока). Направление строго «логика → реакции»:
## подписчики только слушают и НЕ дёргают модель в ответ синхронно из обработчика.
##
## Будущее: character_core повесит анимацию/«пузырь реплики» на utterance/turn_changed;
## stage_core — камеру/режиссуру на clinch_started/match_*. Сейчас доказательство шва — print.

signal match_started(info: Dictionary)          ## новая партия: {theme, first, match_id}
signal turn_changed(side: String)               ## начинается ход стороны ("you"/"opp")
signal utterance(side: String, text: String, meta: Dictionary)  ## реплика стороны (meta: {tag, stance})
signal narration(text: String, meta: Dictionary)                ## голос зала / ремарка
signal clinch_started(attacker: String, defender: String, idx: int)  ## завязка клинча
signal clinch_resolved(result: Dictionary)      ## клинч закрыт (JSONL-подобный итог)
signal impact(side: String, kind: String)       ## яркий исход по стороне side (kind: "landed"/"removed")
signal board_changed()                          ## доска/рука/режим изменились → перерисовать
signal match_ended(winner: String, reason: String, verdict: String)
