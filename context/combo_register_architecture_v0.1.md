# DUELOGUE — Combo Register Architecture v0.1

**Статус:** рабочая архитектурная гипотеза (2026-07-19), не контракт реализации.
**A3-дизайн:** [combo_a3_topologies_v0.1.md](combo_a3_topologies_v0.1.md).
**Механический spike:** [combo_a3_mechanics_test_v0.1.md](combo_a3_mechanics_test_v0.1.md).

## Решение в одном абзаце

Комбо хранится не как большой `combo_exchange` и не как набор полей на картах. Внутри
`RulesCore` появляется один **ComboRegister**: append-only запись фактов розыгрыша,
маленький граф связей этих розыгрышей с доской и набор активных совпадений
декларативных рецептов. Две actor-дорожки являются проекциями фактов по стороне, а
третья дорожка — relation graph. Карты описывают, **что** было сыграно; register —
**кто, когда, куда и в связи с чем**; recipe — **какая форма из этого следует**.

`combo_owner`, `closer` и `CONTESTED` не являются самостоятельными mutable-полями:
owner и closer выводятся из bindings рецепта, а CONTESTED — это два валидных runs на
одном окне с разными владельцами.

---

## 1. Файтинговая модель с третьим регистром

У обычного файтинга есть два input buffer. В DUELOGUE только последовательности карт
недостаточно: один и тот же `R–T–R` имеет разный смысл в зависимости от того, куда
целился R, чему отвечал T и что реально осталось на рамке.

Логически запись выглядит так:

```text
actor lane A:  play_a0 ─────────────── play_a2

actor lane B:          play_b1 ─────────────── play_b3

relation lane: play_a0 ─targets→ frame/claim
               play_b1 ─responds_to→ play_a0
               play_b1 ─materializes_as→ thesis_b1
               play_a2 ─targets→ thesis_b1
               board snapshot: thesis_b1 ∈ frame
               settlement ─result/effect→ exact plays/entities
```

Физически это не три копии данных. Истина одна — ordered `plays[]`; actor lanes —
дешёвые индексы/запросы по `actor`, relation lane — массив рёбер по ID.

Третья дорожка выполняет для карточного «файтинга» роль hit-confirm/context:

- связывает opener с exact рамкой и верхним тезисом;
- связывает ответ с предыдущим нажимом;
- связывает press с exact ответным тезисом;
- после unwind сообщает `held/removed/stolen/parried` и effect;
- для длинных защитных форм позволяет сопоставить exact тезисы из снимка рамки с
  породившими их розыгрышами.

---

## 2. Четыре сущности, которые нельзя смешивать

### 2.1 Card

Физический объект карты и её собственные свойства:

```text
type, name, scheme/suit, device/hook, named, combo_eligible
```

Карта не должна хранить:

```text
combo_state, combo_owner, route_progress,
target_frame_ref, answers_step, target_step, argumentative_thread_id
```

Это свойства конкретного **розыгрыша**, а не карты. Та же карта после recycle может
участвовать в другой цепочке.

Богатая семантика не должна добавляться россыпью top-level booleans. У карты может быть
один namespaced payload с декларациями:

```yaml
rhetoric:
  traits:
    scheme: Статистика
    quantifier: most
  emits:
    - {rel: supports, from: $self, to: $context.claim,
       attrs: {role: corroboration}}
    - {rel: derived_from, from: $self, to: $dataset}
```

Это **шаблоны**, а не runtime edges. При розыгрыше binder подставляет exact play,
frame, thesis и claim refs. Автор контента никогда не прописывает `play_42`, step или
frame index вручную.

### 2.2 PlayFact

Один occurrence розыгрыша:

```yaml
play:
  id: play_42
  scope_refs:               # явное членство, не скрытое свойство индекса
    - {kind: action, id: action_17}
    - {kind: frame, id: frame_5}
  ordinal: 2                # локальный step
  actor: you
  card_view:
    type: R
    hook: уместность
    combo_eligible: true
  outcome: null             # single-assignment на settlement
```

`card_view` — компактный snapshot механически значимых traits. Полный текст, mood,
axis и UI-поля сюда не копируются.

### 2.3 RelationFact

Типизированное ребро между exact ссылками:

```yaml
relation:
  id: rel_73
  scope_refs:
    - {kind: action, id: action_17}
    - {kind: frame, id: frame_5}
  type: targets
  from: {kind: play, id: play_42}
  to: {kind: thesis, id: thesis_9}
  provenance: rules          # rules | content
  attrs: {}
```

Механические связи первой версии:

```text
targets         play → frame | thesis | play
responds_to     play → play
materializes_as play → thesis
about           play | thesis → claim
affects         play → frame | thesis
```

`materializes_as` — единственный мост от сыгранного T к его стабильному `thesis_id`.
Текущее нахождение тезиса на рамке relation store не дублирует: `contains`,
`directly_above` и `owned_by` matcher читает из authoritative board snapshot. Поэтому
снятие/кража тезиса не требуют инвалидировать старое ребро и не создают вторую истину
рядом с `thesis_stack`.

Outcome можно один раз записать в `PlayFact.outcome`:

```yaml
result: landed | held | removed | stolen | parried
effect: breakdown | steal_thesis | no_target | ...
affected_ref: {kind: thesis, id: thesis_9}
```

Риторическая семантика использует тот же контейнер RelationFact, но не раздувает
ядро новыми полями. Начальный словарь может включать:

```text
supports, undercuts, conflicts_with, refines,
instantiates, maps_to, implies, derived_from, represents, commits_to
```

Core не обязан понимать каждый термин процедурным `if`. Он хранит relation и отдаёт
её constraint matcher'у. Отсутствие нужной content-relation даёт `UNRESOLVED`, а не
автоматический TRAP.

### 2.4 PatternRun

Конкретное совпадение recipe с фактами:

```yaml
run:
  id: run_12
  pattern_id: p01_expert_domain
  pattern_version: 1
  scope: {kind: action, id: action_17}
  roles: {A: opp, B: you}
  slots: {$ask: play_40, $reply: play_41, $press: play_42}
  next_atom: 3
  state: armed              # watching | link | armed | terminal
  terminal: null            # confirmed | break | superseded | expired | unresolved
```

Run хранит только bindings и cursor. Он не копирует карты, доску, semantic flags и
settlement info. Всё доказательство уже лежит в play/relation IDs.

---

## 3. Минимальная форма ComboRegister

```yaml
combo_register:
  next_play_id: 43
  next_relation_id: 74
  next_run_id: 13

  plays: {play_id: PlayFact}
  relations: {relation_id: RelationFact}

  indexes:                    # производные, можно пересобрать
    by_actor: {you: [], opp: []}
    by_scope: {"action:action_17": [], "frame:frame_5": []}
    by_relation_type: {targets: [], responds_to: []}

  runs: {run_id: PatternRun}
  completions: {}             # one-shot frame/meta patterns
```

Register может жить один на матч, а typed `ScopeRef {kind, id}` ограничивает окно:

- клинч — `action_id` одного ралли;
- короткое комбо вне клинча — action/turn window;
- защитная цепочка — постоянный `frame_id`;
- будущая meta-комбинация — отдельный scope run/scene.

Один PlayFact явно содержит `scope_refs[]` и может входить сразу в action- и
frame-scope, но физически не дублируется. `by_scope` лишь воспроизводит это членство;
оно никогда не возникает только внутри индекса. У PatternRun один primary `scope`,
потому что один run закрывается на одной boundary.

---

## 4. Recipe — constraint pattern, а не ветка кода

Actor lanes в рецепте символические. `A/B` связываются через контекст, а не означают
навсегда `you/opp`.

Slot из `path` всегда обозначает PlayFact. Любая другая entity получает отдельное
имя только через точный bind вида `bind + rel`; неявные ссылки вроде
`$reply.support` запрещены.

Компактная authoring-форма P-01:

```yaml
id: p01_expert_domain
version: 1
family: A3                 # каталог/UI, не ветка runtime
scope: action
arbitration: {channel: clinch, tier: 3, priority: 10}

path:
  - {$ask:   {lane: B, card: {type: R, hook: источник}, selector: first}}
  - {$reply: {lane: A, card: {type: T, scheme: Авторитет}, selector: next}}
  - {$press: {lane: B, card: {type: R, hook: уместность}, selector: next}}

where:
  - {rel: targets, from: $ask, to: $context.claim_or_frame}
  - {rel: responds_to, from: $reply, to: $ask}
  - {bind: $reply_thesis, rel: materializes_as, from: $reply}
  - {rel: targets, from: $press, to: $reply_thesis}
  - {rel: undercuts, from: $press, to: $reply,
     attrs: {reason: domain_mismatch}}

claim:
  owner: B
  confirm:
    - {winner: B}
    - {outcome: {$press: landed}}
    - {effect_in: {$press: [breakdown, steal_thesis]}}
```

TRT-GUARD добавляет board-atom вместо третьего player register:

```yaml
seed:
  $setup: {lane: board, selector: context.top_thesis,
           card: {type: T, scheme: Авторитет}}
path:
  - {$ask:   {lane: B, card: {type: R, hook: источник}, selector: first}}
  - {$reply: {lane: A, card: {type: T, scheme: Статистика}, selector: next}}
where:
  - {rel: targets, from: $ask, to: $setup}
  - {rel: responds_to, from: $reply, to: $ask}
  - {bind: $reply_thesis, rel: materializes_as, from: $reply}
  - {rel: supports, from: $reply, to: $context.claim,
     attrs: {role: corroboration, lineage: independent}}
claim:
  owner: A
  confirm:
    - {winner: A}
    - {outcome: {$reply: held}}
    - {board: contains, frame: $context.frame, entity: $reply_thesis}
```

TRT-TRAP — другой recipe над теми же slots. Он не «переключает owner» GUARD-run:
создаётся второй run с `owner: B` и другими semantic/confirm constraints.

Из этого автоматически следуют UI-проекции:

```text
только guard-run armed                  → DEFENDED
только trap-run armed                   → SPRUNG
guard-run + trap-run armed              → CONTESTED
структурный prefix без semantic match   → UNRESOLVED
```

Ни один из этих verdict не нужен как mutable поле регистра.

---

## 5. Settlement и один payoff без специальных TRT/RTR-правил

Каждый armed Run — один claim. Арбитраж общий:

1. сгруппировать runs по `(scope.kind, scope.id, owner_side, arbitration.channel)`;
2. при вооружении более высокого `tier` пометить более низкий run той же группы как
   `superseded`;
3. на boundary проверить `confirm` только по сохранённым bindings/facts;
4. глобальный winner не назначает owner, а лишь выполняет/не выполняет constraint;
5. среди подтверждённых runs одного payoff-channel выбрать priority winner;
6. выдать максимум один payoff на `(scope.kind, scope.id, channel)`;
7. armed, не подтвердившиеся runs получают BREAK; не дошедшие до armed — expired или
   unresolved.

Так решаются без hardcode:

- D2 → A3: tier 3 supersedes tier 2 у того же owner/channel;
- TRT-TRAP → RTR: более высокий run атакующего подавляет старый кандидат;
- GUARD(D) против PRESSURE(A): owner-группы разные, обе ставки живут до settlement;
- S4: тот же run с tier 4;
- отсутствие fallback: нижний run уже `superseded`, если верхний был armed.

`closer` не хранится отдельно: recipe обращается к `$reply` или `$press`.

---

## 6. Защитные три T без отдельного matcher'а

Защитная цепь отличается только scope и boundary:

```yaml
scope: {kind: frame}
match_mode: snapshot
close_on: board_stable
roles:
  A: {from: $context.frame.owner}
snapshot:
  lane: board
  source: $context.frame.thesis_stack
  selector:
    kind: new_top_suffix
    length: 3
    requires_added_in: $context.closing_action
  path:
    - {$t0: {entity: thesis, card: {type: T, combo_eligible: true}}}
    - {$t1: {entity: thesis, card: {type: T, combo_eligible: true}}}
    - {$t2: {entity: thesis, card: {type: T, combo_eligible: true}}}
where:
  - {order: directly_above, values: [$t0, $t1, $t2]}
  - {origin_actor: A, values: [$t0, $t1, $t2]}
one_shot: {key: [$context.frame.id, $pattern.id]}
```

На `board_stable` matcher одним проходом читает authoritative `thesis_stack` рамки и
связывает exact thesis IDs с их PlayFact через `materializes_as`. `match_mode: snapshot`
означает, что после первого или второго T не остаётся частичного F3-run: на каждой
boundary проверяется только целый новый верхний суффикс. `A` — одна из двух обычных
actor-ролей, выведенная из текущего владельца рамки; `board` остаётся третьей дорожкой,
а `frame_owner` как четвёртая lane не появляется.

`new_top_suffix` формально означает: exact три верхних тезиса после settlement, причём
хотя бы один из них имеет origin PlayFact с action-scope, равным
`$context.closing_action`, и в этом action был добавлен на данную рамку. Boundary,
которая только сняла карту и обнажила старую тройку, нового F3-run не создаёт.

Копия всей доски в register не нужна. Базовый one-shot ключ
`(frame_id, pattern_id)` повторяет контракт `completed_sets`: тот же рецепт не платит
снова даже на другой тройке после снятия/возврата карт или захвата рамки. Если когда-то
понадобится повтор за новую сигнатуру, это будет явная `repeat_policy`, а не поведение
по умолчанию.

---

## 7. Как это входит в нынешнюю архитектуру

### Что уже есть

- `clinch.sequence` — почти готовый ordered play-log;
- `thesis_id` — стабильная identity T, переживающая снятие и кражу;
- `line.thesis_stack` — authoritative board order;
- `type/scheme/hook/combo_eligible` — card traits;
- `resolved_sequence` — outcomes, exact targets и effects;
- `EventBus.clinch_resolved` и JSONL — готовая выходная телеметрия.

### Чего не хватает

Минимальные новые identities:

```text
frame_id    постоянен при переносе/захвате рамки
action_id   один полный игровой action; у клинча это scope id
play_id     occurrence карты внутри матча
```

Пока не нужны:

```text
card_instance_id          # нужен только для «сыграй ту же физическую карту снова»
argumentative_thread_id   # внутри клинча связь выводится из graph/scope
claim_instance_id         # механическая опора — frame_id; claim_id остаётся content ref
```

### Точки подключения

```text
begin_clinch
  → action_id, play R₀, targets frame/top thesis, optional about claim

defensive clinch_submit
  → play T₁, responds_to R₀, materializes_as T₁→thesis_id

press clinch_submit
  → play R₂, targets previous T/play

post-resolve, до refill
  → single-assign outcomes, close scope, settle runs, emit combo_events[]

после любого полного action
  → board_stable(action_id, frame IDs), проверить frame-scoped patterns
```

`ComboRegister` должен принадлежать чистому `RulesCore`. EventBus, BattleController и
MatchLog получают только итоговые `combo_events[]`: им слишком поздно быть источником
истины для AI и UI.

Текущий `claim_id` назначается app-слоем уже после `begin_clinch`. Поэтому физический
target обязан существовать через `frame_id`; content claim можно добавить relation'ом
позже, до semantic matching.

Есть второй текущий шов: содержательная `statement` создаётся BattleController уже
после `clinch_submit`. Для G2 это надо сдвинуть в одну из двух разрешённых форм:

1. theme/content binder обогащает card `rhetoric` payload до передачи play intent в
   RulesCore; либо
2. controller добавляет content RelationFacts сразу после физического play, но до
   следующего matcher milestone и settlement.

Первый вариант лучше для AI-предпросмотра; второй дешевле как миграционный этап. В
обоих случаях RulesCore исполняет общий relation contract, а не знает конкретные
риторические route names.

### Переходная совместимость

Не хранить два параллельных combo-state. На время миграции:

```text
legacy combo_route/combo_owner/closer
  = ComboRegister.legacy_view(active_scope)
```

После перевода UI/AI старые поля удаляются.

---

## 8. Ограничители сложности

- recipe — ациклический pattern максимум из четырёх смысловых atoms;
- только `first/next/exact/current`, без `*`, рекурсии и backtracking;
- после первого atom обязательна exact связь по scope/target/frame;
- один live run на `(pattern_id, scope.kind, scope.id, anchor_binding, role_binding)`;
- общий префикс recipes компилируется в trie/discrimination network;
- matcher индексируется по следующему `type/scheme/hook/relation`, а не сканирует всё;
- `max_events` и close boundary обязательны для каждого scope;
- максимум 16 live runs на scope; превышение — ошибка recipe-каталога;
- tier/priority graph валидируется как ациклический;
- отсутствие semantic relation не считается отрицательным фактом;
- frame-chain проверяется только на `board_stable`, не после каждой внутренней мутации.

На первом вертикальном срезе каталог мал, поэтому matcher может быть простым. Контракт
данных уже позволяет позднее скомпилировать его без изменения recipes.

---

## 9. Миграция без большого переписывания

### Шаг R0 — identity only

**Статус: ВЫПОЛНЕН 2026-07-20.** В `RulesCore`: три serial-счётчика; `frame_id` живёт
на объекте рамки (минт при создании + ленивый сторож `_ensure_frame_id` по образцу
`_ensure_thesis_stack` — тестовые/ран-слойные рамки догоняются при первом касании) и
переживает захват; `action_id` минтится на четырёх точках входа (`play_action`,
`play_named`, `begin_clinch` — одно на всё ралли, `play_redeploy`); записи
`clinch.sequence` получают `play_id/actor/role/step` сразу при play (settlement лишь
дописывает result/effect). Телеметрия: `action_id/play_id` в каждом info,
`target_frame_id` у single-razbor и клинча, `captured_frame_id` у захвата, `frame_id`
в `opening_anchor`. Сторожа — `_check_r0_identity` в combo_grammar_smoke; все 8
smoke-сцен зелёные, combo behavior не изменён.

- добавить `frame_id/action_id/play_id`;
- записывать actor/ordinal в sequence сразу при play;
- ничего не менять в combo behavior.

### Шаг R1 — relation trace

**Статус: ВЫПОЛНЕН 2026-07-20.** В `RulesCore`: фабрика `_relation_fact` (форма §2.3:
id/type/from/to/scope_refs/provenance="rules"); эмиссия в момент розыгрыша — opener
`targets`→frame + exact верхний тезис (независимо от eligibility: ребро — физический
факт), hold `responds_to`→предыдущий нажим + `materializes_as`→thesis_id, press
`targets`→exact материализованный T; на settlement (после unwind и сократика)
single-assign `outcome{result, effect, affected}` на каждую запись sequence;
`info["relations"]` уходит в телеметрию. Гейт пройден: мини-вывод в smoke
(`_derive_combo_from_trace`) воспроизводит CONFIRMED/BREAK/LINK/NONE, owner и closer
только из трейса+outcome+якоря, не читая mutable combo-полей; все 8 smoke-сцен зелёные.

**Шов §7 зафиксирован: вариант 2** — controller добавляет content-RelationFacts после
физического play, до matcher milestone/settlement; ядро исполняет общий relation
contract и не знает риторических route names. Вариант 1 (binder до play intent)
остаётся целевым для AI-предпросмотра позже.

- поверх нынешнего sequence эмитить `targets/responds_to/materializes_as`;
- на settlement single-assign outcome;
- проверить, что trace полностью воспроизводит текущие combo smoke assertions.

### Шаг R2 — один recipe вместо старого matcher

**Статус: ВЫПОЛНЕН 2026-07-20.** Новый модуль `core/rules/combo_register.gd`: рецепт
`P_G01_GUARD` — GDScript-словарь в форме §4 (path/where/claim.confirm), интерпретатор
покрывает ровно используемые constraint-типы (anchor_route, responds_to по свежим
рёбрам R1, bind materializes_as, grammar_answers; confirm: winner/outcome/
board_contains). `RulesCore` владеет одним регистром на матч (append-only runs);
инлайновый matcher удалён — LINK/ARMED/settlement решает register, а клинч и info
получают прежние ключи `combo_*`/`closer_*` только как проекцию `legacy_view()`
(маппинг терминалов: expired→link, confirmed/break→armed). Вооружает только ответ
с ребром `responds_to` на exact опенер — факт-эквивалент старого «t_added == 1».
Гейт пройден: сценарии §4 и сторожа смоука ассертят прежние значения на всех
milestone'ах побитно; AI/UI/контроллер не менялись; все 8 smoke-сцен зелёные.
Новая телеметрия: `info["combo_run"]` — снапшот терминализированного run'а.

- перенести G-01 GUARD в Pattern;
- `legacy_view()` обязан побитно совпасть с нынешними telemetry fields;
- AI/UI пока продолжают читать legacy view.

### Шаг R3 — две стороны

**Статус: ВЫПОЛНЕН 2026-07-20.** Каталог регистра: `P_X01_TRAP` («Ложная
независимость», seed=$setup board-atom + двухзвенный path, owner A) и
`P_P01_PRESSURE` («Эксперт по делу?», трёхзвенный path без чтения схемы T₀, owner A).
Окна жёсткие по §2 топологий: $reply — ровно step 1, $press — ровно step 2. Оба
рецепта вооружаются только при content-RelationFact по своему content-атому
(X-01: supports с {claimed_lineage: independent, lineage: dependent};
P-01: undercuts с {reason: domain_mismatch}); новый публичный API
`RulesCore.add_content_relation()` — шов §7 вариант 2 (controller эмитит после
физического play, provenance="content", факт ложится в общий trace). Структурно
полный кандидат без семантики терминализируется UNRESOLVED (неизвестность не
наказывается), недостроенный — expired. Settlement стал scope-wide
(`settle_action`), наружу уходят `info["combo_events"]` — по событию на run
(pattern/topology/combo_name/owner/terminal/slots, payoff всегда "") — и
дублируются в JSONL клинча контроллера. Stake/owner readability подтверждена
смоуком: SPRUNG-ралли несёт две читаемые ставки двух владельцев (X-01 confirmed
атакующему, G-01 break защитнику). G-01 остаётся структурным (20 маршрутов —
guard-only резерв, §11 топологий); verdict-гейтинг GUARD и арбитраж
(supersede/CONTESTED) — R4. Все 8 smoke-сцен зелёные, легаси-поля не изменились.

- добавить X-01 и P-01;
- выводить `combo_events[]` без численного payoff;
- проверить stake/owner readability.

### Шаг R4 — arbitration и frame scope

**Статус: ВЫПОЛНЕН 2026-07-20.** Каталог получил explicit contested-пару
G-04/X-04 над одной тройкой `Аналогия → Ложная аналогия → Определение`: две authored
content-relations связывают ответ с разными exact `subclaim` (`shared_core` и
`scope_qualifier`), поэтому CONTESTED остаётся производной двух `armed_once` runs
разных владельцев, а не mutable verdict. X-04 подтверждается только если первый press
дополнительно имеет content-ребро `targets` на exact trap-basis.

Для уже мигрированной пары G-01/X-01 добавлен semantic G-01 `source_backed`. Старый
structural G-01 на этой exact тройке становится только shadow legacy-проекции:
`lineage=independent` подтверждает semantic GUARD, dependent — вооружает X-01, а
неизвестность оставляет обе ветви UNRESOLVED. Поэтому победа защитника больше не может
превратить зависимый источник в правильный GUARD. Неперенесённые маршруты `ANSWER_OF`
по-прежнему используют structural reserve без изменения поведения.

У каждого pattern появился общий `arbitration {channel,tier,priority}`. Более высокий
tier того же owner/channel single-assign терминализирует нижний run как `superseded`;
нижний не возвращается после BREAK верхнего. Реальный гейт — P-06 «Двойной аудит»
жёстко повышает X-01. После settlement priority оставляет максимум один `confirmed`
run на payoff-channel; generic G-01 уступает семантически точному G-04, а
`legacy_view()` следует победившему run, не меняя старый UI/AI-контракт.

Frame-scope реализован одним F3-10 «Вверх и обратно». Карты exact authored-заготовки
несут namespaced `rhetoric.frame_recipe_id`; одного случайного совпадения схем
недостаточно. Register хранит только origin `thesis_id → action/play/actor/frame`, а
authoritative порядок получает снимком на `board_stable` после любого полного action.
Matcher читает новый top-suffix `Пример → Определение → Пример`, требует origin от
текущего владельца на этой рамке и хотя бы один T из closing action; снятие/захват не
вскрывают старую тройку как новую. Completion `(frame_id, pattern_id)` one-shot переживает
снятие, повторную укладку и перенос рамки. Frame-events идут тем же `combo_events[]` в
move/named/redeploy/clinch telemetry.

Гейт `_check_r4_arbitration_frame_scope`: оба исхода CONTESTED, distinct basis,
priority-suppression legacy G-01, P-06 BREAK без X-01 fallback, authored guard F3,
stable-boundary и one-shot. `combo_grammar_smoke` и `battle_loop_rules_smoke` зелёные.
Численный payoff намеренно остаётся пустым: его подключение — следующий этап после R4.

- добавить contested G-04/X-04, tier-supersede и один защитный 3T;
- только затем подключать payoff и расширять каталог.

---

## 10. Рабочий вывод

Правильная базовая абстракция — не `combo_exchange`, а:

```text
Play facts + Relation facts + Declarative patterns + Derived runs
```

`Exchange` остаётся удобной UI-проекцией:

```text
все armed runs одного action scope, сгруппированные по owner/channel
```

Но он не является хранилищем и не диктует topology. Поэтому новые D2/A3/S4/F3
добавляют recipes и relation vocabulary, а не новые поля в `clinch`.
