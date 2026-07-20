# ЗАЛ — A3 mechanics test v0.1

**Дата:** 2026-07-19
**Статус:** детерминированный test-only spike; боевой runtime и payoff-эффекты не изменены.
**Дизайн:** [combo_a3_topologies_v0.1.md](combo_a3_topologies_v0.1.md).
**Целевая архитектура:** [combo_register_architecture_v0.1.md](combo_register_architecture_v0.1.md).
**Runner:** [combo_grammar_smoke.gd](../duelogue/tools/combo_grammar_smoke.gd).
**Probe:** [a3_exchange_probe.gd](../duelogue/tools/a3_exchange_probe.gd).

## Вердикт

**Топология механически ложится на нынешний клинч.** Уже существующая физика даёт exact
окна `T₀–R₀–T₁` и `R₀–T₁–R₂`, корректно парирует их поздним T и разворачивает press до
opener. Для A3 не нужен новый тип хода или отдельная мини-игра.

Главный разрыв находится в данных состояния: нынешние `combo_route/combo_owner/closer`
умеют описать только GUARD защитника. Для TRAP, CONTESTED и RTR нужен предложенный
`combo_exchange` с одним claim на сторону.

Это **не** тест баланса наград. Probe считает только `payoff_count ∈ {0,1}` и не
применяет численный эффект к руке, залу или рамкам.

## Метод

Каждый fixture управляет настоящим `RulesCore` через `begin_clinch()` и
`clinch_submit()`. Probe не симулирует карточную физику: он читает полученные runtime
поля `resolved_sequence`, `result`, `target_step`, `effect`, `affected_thesis_id` и
оставшиеся `thesis_id` на рамке.

Тестовый слой добавляет только будущие semantic relation tags:

    target_frame_ref
    target_claim_ref
    argumentative_thread_id
    answers_step
    supports_claim_ref
    semantic_verdict
    basis_subclaim_ref

Это удобные поля fixture-probe, но **не рекомендуемая форма production state**. В
целевой архитектуре `target/answers/thread` выводятся из RelationFacts, а owner/closer —
из bindings декларативного recipe.

Таким образом отдельно проверяются:

1. настоящая физика клинча;
2. proposed ownership/settlement;
3. расхождение с текущим defensive-only classifier.

## Матрица результатов

| ID | Прогон | Реальный исход клинча | A3 v0.1 | Что показал тест |
|---|---|---|---|---|
| E1 | `DEFENDED`, A пасует после T₁ | D; T₁ `held` | `GUARD_CONFIRMED`, 1 payoff | новый exchange и текущий runtime согласны |
| E2 | `SPRUNG`, A играет R₂, D пасует | A; T₁ `removed`; R₂ и R₀ `landed` | `TRAP_SPRUNG`, 1 payoff | физика ловушки уже есть; нынешний runtime ошибочно пишет defender `BREAK` |
| E3 | тот же TRAP → T₃, A пасует | D; R₂ `parried`, T₁ `held` | `ALL_BREAK`, 0 payoff | обычный T₃ честно парирует ловушку; owner не переключается |
| E4-D | `CONTESTED`, A пасует | D | G-04 по `core`, 1 payoff | defender-branch подтверждается по exact subclaim |
| E4-A | `CONTESTED`, R₂ бьёт `qualifier`, D пасует | A | X-04 по `qualifier`, 1 payoff | attacker-branch работает, общий бюджет остаётся 1 |
| E5 | структурный TRT, semantic tags неизвестны | D; схема формально закрыта | `UNRESOLVED`, 0 payoff | текущий runtime ошибочно подтверждает такой ответ; нужна G2-валидация |
| E6 | technical T₀ → P-01 `R–T–R` | A; opening anchor отсутствует | `WATCH→LINK→ARMED→PRESSURE_CONFIRMED` | RTR действительно не требует схемы T₀, но требует frame/claim/thread refs |
| E7 | те же карты, но T₁/R₂ сменили thread | A физически перестоял | `NO_CLAIM`, 0 payoff | совпадение схем без общей аргументативной нити не образует RTR |
| E8 | P-01 → T₃, A пасует | D; R₂ `parried` | `ALL_BREAK`, 0 payoff | отдельная контр-комбинация для парирования не нужна |
| E9-A | X-01 → exact P-06, D пасует | A | только `PRESSURE_CONFIRMED`, 1 payoff | RTR жёстко заменяет TRAP; двойной выплаты нет |
| E9-D | тот же upgrade → T₃, A пасует | D | PRESSURE `BREAK`, X-01 `SUPPRESSED_UPGRADED`, 0 payoff | после повышения ставки старый TRAP не возвращается |
| E10 | победа A, но у R₂ подставлен `effect=no_target` | A по длине клинча | `ALL_BREAK`, 0 payoff | winner и `landed` недостаточны без exact effect/target |
| E11 | два длинных клинча: ранний P-01 + R₄; ранний MISS + поздний валидный `R₂–T₃–R₄` | A в обоих | первый: один P-01; второй: `NO_CLAIM` | R₄ не удваивает награду, а поздняя тройка не открывает скользящее окно |

Все строки прошли.

## Что уже доказано

- стартовые окна совместимы с текущей временной осью и unwind;
- GUARD, TRAP и PRESSURE можно разрешать после существующего settlement;
- одно обычное продолжение клинча обеспечивает двустороннее парирование;
- `CONTESTED` может хранить два claims, не меняя owner постфактум;
- жёсткий upgrade TRAP → RTR не требует второго payoff-канала;
- first-window-only устраняет бесконечный counter-chain;
- exact `step + thesis_id + effect` уже достаточно для честной проверки PRESSURE;
- `UNRESOLVED` и `NO_CLAIM` должны отличаться от проигранного `ALL_BREAK`.

## Что мешает прямому переносу в runtime

1. `opening_anchor` не создаётся над `combo_eligible=false`, поэтому отдельно нужны
   постоянные `target_frame_ref + target_claim_ref`.
2. Один скалярный `combo_owner` надо заменить на `defender_claim + attacker_claim`.
3. Press-ветка сейчас не запускает RTR matcher после первого R₂.
4. Semantic verdict и relation tags пока существуют только в fixture-контенте.
5. UI и AI знают только защитный LINK: PRESSURE finisher и ставка двух сторон ещё не
   отображаются и не оцениваются.

## Рекомендованный следующий тест

Не подключать сразу все 16 записей. Перенести в runtime **telemetry-only vertical
slice** без численного payoff:

- G-01 `Источник подтверждён`;
- X-01 `Ложная независимость`;
- P-01 `Эксперт по делу?`;
- одну explicit CONTESTED пару G-04/X-04.

На живом бумажном/UI-прогоне измерять:

- угадал ли игрок owner до settlement;
- понял ли он, что T₃ парирует PRESSURE без нового combo-banner;
- воспринимается ли TRAP как осознанная ставка A, а не наказание D за правильный T;
- как часто игрок добровольно повышает TRAP до RTR;
- `shown → candidate → ARMED → CONFIRMED/BREAK/SUPPRESSED` по каждой ветви.

Только этот прогон ответит на вопрос о читаемости и относительной частоте выплат. Равные
5 GUARD / 5 TRAP обеспечивают баланс каталога, но не баланс срабатываний: TRAP чаще
требует дополнительный R₂ и победу A.

## Команды

```powershell
& 'D:\DOWNLOADS\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' `
  --headless --path . res://duelogue/tools/combo_grammar_smoke.tscn

& 'D:\DOWNLOADS\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' `
  --headless --path . res://duelogue/tools/battle_loop_rules_smoke.tscn
```

Результат обоих runner'ов: `OK`.
