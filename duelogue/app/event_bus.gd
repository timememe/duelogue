extends Node

## DUELOGUE — ШИНА СОБЫТИЙ (autoload "EventBus").
## Контракт, на который подписываются UI и будущие ядра сцены/персонажей. Секцию партии
## эмитит battle_controller, секцию забега — run_controller (каждый — единственный владелец
## своего потока). Направление строго «логика → реакции»: подписчики только слушают и
## НЕ дёргают модель в ответ синхронно из обработчика.
##
## Будущее: character_core повесит анимацию/«пузырь реплики» на utterance/turn_changed;
## stage_core — камеру/режиссуру на clinch_started/match_*. Сейчас доказательство шва — print.

signal match_started(info: Dictionary)          ## новая партия: {theme, first, match_id}
signal turn_changed(side: String)               ## начинается ход стороны ("you"/"opp")
signal utterance(side: String, text: String, meta: Dictionary)  ## реплика стороны (meta: {tag, stance})
signal narration(text: String, meta: Dictionary)                ## голос зала / ремарка
## Накопительное психологическое состояние и непроизвольная реакция. v0.1 — только
## презентация: подписчики не должны менять через эти сигналы правила боя.
signal emotion_changed(side: String, state: Dictionary)
signal emotion_reacted(side: String, reaction: Dictionary)
signal clinch_started(attacker: String, defender: String, idx: int)  ## завязка клинча
signal clinch_resolved(result: Dictionary)      ## клинч закрыт (JSONL-подобный итог)
signal impact(side: String, kind: String)       ## яркий исход по стороне side (kind: "landed"/"removed")
signal board_changed()                          ## доска/рука/режим изменились → перерисовать
signal match_ended(winner: String, reason: String, verdict: String)

# --- слой забега «Сезон» (эмитит run_controller; слушает run_map_screen) ---

signal run_started(info: Dictionary)            ## новый забег: {seed, act, acts_total}
signal run_map_changed()                        ## карта/позиция/ресурсы изменились → перерисовать
signal room_entered(node: Dictionary)           ## вошли в узел карты (открыть панель комнаты)
signal room_resolved(result: Dictionary)        ## комната закрыта: {node_id, type, outcome, effects, outro}
signal act_advanced(act: int)                   ## переход в следующий акт (карта перегенерена)
signal run_ended(outcome: String, info: Dictionary)  ## финал забега: victory | defeated | abandoned
