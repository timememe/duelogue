# Архитектурная пересборка — чеклист v0.1

**Назначение:** живой trackable-документ для пересборки кода под `context/game_design.md` v0.1.
Любая сессия (включая будущий «холодный» агент) должна с него поднять контекст:
что сделано, что в работе, что следующее.

**Связанные документы:**
- `context/game_design.md` — что строим и почему
- `context/rhetoric/_summary_universal_methods.md` — карточный набор
- `context/fighting/*.md` — источники механик (комбо, метр, rage)

**Текущая позиция:** Фаза 4 — код Burst/Rage добавлен; нужен ручной smoke-test Фазы 4.

---

## Состояние на данный момент

| Фаза | Статус |
|---|---|
| Фаза 1 — Скелет данных | ✅ завершена |
| Фаза 2 — Разделение данных на 3 слоя | ✅ завершена |
| Фаза 3 — Combo mechanic + UI | ✅ завершена |
| Фаза 4 — Накал / Burst / Rage / Damage scaling | 🟡 код готов, нужен ручной smoke-test |
| Фаза 5 — Плейтест → v0.2 дизайн-док | ⏳ pending |

**Следующее действие:** вручную smoke-test'ить damage scaling / tension / EX / Burst / Rage.

---

## Текущая кодовая база (для холодного агента)

```
project root: D:\GODOT_PROJECTS\DUELOGUE\duelogue-v-1\

autoloads/
  card_database.gd        — загружает JSON-колоды, создаёт стартовые руки
  game_manager.gd         — глобальное состояние, сигналы

core/
  enums.gd                — CardCategory, CardEffect, GamePhase, Advantage, EventType
  rules_engine.gd         — get_advantage, calculate_damage/heal, эвристики статов
  scales_manager.gd       — весы ±5, очки до 3
  game_state.gd           — оркестратор партии (play_turn)
  turn_resolver.gd        — резолв атак/защит/уклонений
  event_checker.gd        — эвенты (медитация, шквал, mind games, и т.д.)
  combo_track.gd          — общая дорожка последних карт
  combo_resolver.gd       — матчинг combo recipes по дорожке
  ai/
    ai_strategy.gd        — абстрактный класс
    ai_basic.gd           — counter-pick + weighted random

resources/
  card_data.gd            — CardData Resource (id, category, effect, base_damage, …)
  card_instance.gd        — runtime-обёртка над CardData (uses_left, from_discard)
  character_stats.gd      — logic/emotion/shield/hand/deck/discard, last_card_effects
  combo_recipe.gd         — Resource-описание рецепта комбо
  deck_data.gd            — DeckData (player_attack_cards, defense_cards, …)

data/cards/
  universal_cards.json    — универсальная механика карт

data/decks/
  default_deck.json       — «Кофе»
  evangelion_deck.json    — «Евангелион»
  drive_deck.json         — «Драйв»

data/themes/
  coffee/evangelion/drive — имена, тексты и описания карт

data/combos/
  v0_combos.json          — 8 стартовых combo recipes

scenes/screens/
  game_screen.tscn / .gd  — главный экран

test/
  test_match.tscn / .gd   — AI vs AI прогон в консоль
```

**Smoke-тест** после каждой фазы: запустить `test/test_match.tscn` в Godot, убедиться,
что матч проходит без ошибок и логи выглядят как раньше.

---

## ФАЗА 1 — Скелет данных

**Цель:** добавить поля и классы, ничего не активировать. Партия должна играться как раньше.

### 1.1 `resources/card_data.gd`
- [x] Сделать `card_id: String` **первичным экспортным полем** (сейчас выводится из `card_name`)
- [x] Добавить `@export var combo_tags: PackedStringArray = []`
- [x] В `from_dict()` парсить `card_id` явно: `card.card_id = data.get("id", card_name.to_snake_case())`
- [x] В `from_dict()` парсить `combo_tags`:
      ```
      var tags = data.get("combo_tags", [])
      if tags is Array:
          var psa := PackedStringArray()
          for t in tags: psa.append(str(t))
          card.combo_tags = psa
      ```
- [x] Старое поле `id` заменено на `card_id` (никто не ссылался — проверено `grep`)
- [x] Smoke-test: запустить `test_match` — карты должны грузиться

### 1.2 `resources/character_stats.gd`
- [x] Добавить `var tension: int = 0`
- [x] Добавить `var rage_used: bool = false`
- [x] Добавить `var burst_used: bool = false`
- [x] Добавить `var effect_use_count: Dictionary = {}` (effect_int → count)
- [x] В `reset()` сбрасывать новые поля
- [x] Константы для max tension: `const MAX_TENSION := 3`
- [x] Smoke-test: ничего не должно сломаться

### 1.3 `resources/combo_recipe.gd` (новый файл)
- [x] Создать `class_name ComboRecipe extends Resource`
- [x] Поля: `recipe_id`, `display_name`, `recipe_type`, `pattern`, `bonus_damage`, `bonus_heal`, `bonus_effect_id`, `description`
- [x] Константы типов (`TYPE_SOLO/REACTIVE/BAIT/ECHO`) и владельцев (`OWNER_SELF/OPPONENT/ANY`) + `WILDCARD = -1`
- [x] `static func from_dict()` для загрузки из JSON
- [x] Метод `slot_matches(slot, entry)` для матчинга (вынесен сюда, чтобы Resolver был тоньше)
- [x] Smoke-test: класс должен компилироваться

### 1.4 `core/combo_track.gd` (новый файл)
- [x] `class_name ComboTrack extends RefCounted`
- [x] Поля: `entries`, `max_size` (default 3)
- [x] Методы: `add_entry`, `get_window`, `size`, `clear`
- [x] Smoke-test: класс компилируется

### 1.5 `core/combo_resolver.gd` (новый файл)
- [x] `class_name ComboResolver extends RefCounted`
- [x] Поля: `recipes: Array[ComboRecipe]`
- [x] Методы: `add_recipe`, `clear_recipes`, `load_recipes_from_file`, `check`
- [x] **Логика матчинга реализована полностью** (см. заметку об отклонении ниже)
- [x] Smoke-test: класс компилируется

### 1.6 Интеграция в `core/game_state.gd`
- [x] Поля `combo_track`, `combo_resolver` + сигнал `combo_triggered`
- [x] В `initialize()` создаются новые объекты
- [x] В `play_turn()` после `_consume_card` добавляется entry в track для игрока
- [x] После хода AI добавляется entry с `OWNER_OPPONENT`
- [x] В Фазе 1 `resolver.check()` НЕ вызывался (в Фазе 3 подключён ниже)
- [x] Smoke-test: `test_match` должен выдавать те же логи, что и раньше

### 1.7 Финальная проверка Фазы 1
- [x] Все изменённые файлы компилируются (проверено через прогон в Godot — только warnings, моих исправлено 2)
- [x] Прогон в Godot: основная игра (`game_screen.tscn`) прошла до победы — UI + резолв + очки + эвенты работают
- [x] ✅ ФАЗА 1 ЗАВЕРШЕНА

**Дополнительные правки после прогона:**
- `combo_track.gd:13` — переименовал параметр `size` → `initial_size` (конфликт с методом `size()`)
- `game_state.gd:25` — добавил `@warning_ignore("unused_signal")` к `combo_triggered` (он будет emit'иться в Фазе 3)

---

## ФАЗА 2 — Разделение данных на 3 слоя

**Цель:** разделить смешанные сейчас «карта + тема» в JSON на три независимых слоя.
Внешнее поведение игры не меняется — те же 3 «колоды» работают идентично.

### 2.1 Спроектировать схему универсальной карты
- [x] Документировать в `data/cards/_schema.md`:
      ```
      {
        "id": "ad_hominem",
        "category": "Атака",
        "effect": "emotion",
        "damage": 2,
        "heal": 0,
        "shield": 0,
        "modifier": 1.0,
        "max_uses": 2,
        "combo_tags": ["pressure", "interrupt"]
      }
      ```
- [x] **Никаких имён/текстов/арта** — только механика (имя/desc оставлены как fallback)

### 2.2 Создать `data/cards/universal_cards.json`
- [x] Извлечь уникальные карты из 3 текущих deck-JSON (по содержанию, не по имени)
- [x] Присвоить каждой карте стабильный `card_id` (snake_case на основе механики или ad-hoc)
- [x] Заполнить `combo_tags` (предварительные, скорректируются в Фазе 3 при дизайне рецептов)
- [x] Итого 22 универсальных карты в Фазе 2; после Фазы 4 добавлены `special_burst` и `special_rage` (24 всего)

### 2.3 Спроектировать схему темы
- [x] Документировать в `data/themes/_schema.md`:
      ```
      {
        "theme_id": "coffee",
        "display_name": "Кофе",
        "card_overrides": {
          "ad_hominem": {
            "name": "Лично против тебя",
            "description": "Прямой удар по личности",
            "text_variants": ["...", "...", "..."]
          },
          ...
        }
      }
      ```

### 2.4 Создать темы
- [x] `data/themes/coffee/theme.json` — извлечь из `default_deck.json`
- [x] `data/themes/evangelion/theme.json` — извлечь из `evangelion_deck.json`
- [x] `data/themes/drive/theme.json` — извлечь из `drive_deck.json`

### 2.5 Спроектировать схему колоды (v2)
- [x] Документировать в `data/decks/_schema.md`:
      ```
      {
        "deck_id": "default_kofe",
        "display_name": "Кофе",
        "theme_id": "coffee",
        "cards": {
          "player_attack_cards": ["ad_hominem", "reductio", ...],
          "enemy_attack_cards": [...],
          "defense_cards": [...],
          "evasion_cards": [...],
          "rare_attack_cards": [...],
          "repeat_card": "..."
        }
      }
      ```

### 2.6 Переписать существующие колоды
- [x] `data/decks/default_deck.json` → новый формат (display_name "Кофе")
- [x] `data/decks/evangelion_deck.json` → новый формат
- [x] `data/decks/drive_deck.json` → новый формат

### 2.7 Обновить `resources/deck_data.gd` и `resources/card_data.gd`
- [x] `CardData.from_dict()` без изменений (читает уже-обогащённый словарь, как раньше)
- [x] `DeckData.from_dict()` удалён — мёртвый код, билд теперь идёт через CardDatabase

### 2.8 Обновить `autoloads/card_database.gd`
- [x] `_ready()` грузит все 3 слоя: universal_cards → themes → decks
- [x] `_build_deck()`: для каждой колоды резолвит card_ids → universal CardData → применяет theme overrides → собирает DeckData
- [x] `get_deck()` индексирует и по display_name, и по deck_id

### 2.9 Финальная проверка Фазы 2
- [x] Игра запускается на текущей теме (Кофе) — карты с правильными именами
- [x] (опционально) поменять `get_deck("Кофе")` в `game_screen.gd` на «Евангелион» / «Драйв» — не блокирует фазу
- [x] Логи `Loaded N universal cards / themes / decks` в консоли
- [x] ✅ ФАЗА 2 ЗАВЕРШЕНА

---

## ФАЗА 3 — Combo mechanic + UI

**Цель:** включить комбо. Игра начинает ощущаться по-новому.

### 3.1 Описать стартовые рецепты
- [x] Создать `data/combos/v0_combos.json` (массив ComboRecipe-словарей)
- [x] 8 рецептов из `game_design.md` §7:
  - Сократов капкан (reactive)
  - Эмоциональный шквал (solo)
  - Холодный разум (echo)
  - Зеркальный финиш (reactive)
  - Стальная стена (solo)
  - Серенада (solo)
  - Догматический бур (solo)
  - Подмена тезиса (bait)

### 3.2 Реализовать матчинг в `combo_resolver.gd`
- [x] Сейчас в Фазе 1 был placeholder. Заполнить:
- [x] Для каждого рецепта пройти `pattern` и сравнить со слотами `track.get_window()`
- [x] Особый случай для bait-рецептов: pattern может быть длиннее окна — тогда матчим то, что есть, ждём дополнения
- [x] Возвращать первый совпавший рецепт (приоритет — порядок в JSON)

### 3.3 Использовать в `game_state.gd`
- [x] После обновления combo_track в `play_turn()`:
      ```
      var combo := combo_resolver.check(combo_track)
      if combo:
          _apply_combo_bonus(combo)
          combo_triggered.emit(combo)
      ```
- [x] Добавить сигнал `signal combo_triggered(recipe: ComboRecipe)`
- [x] Метод `_apply_combo_bonus(recipe)` — применяет `bonus_damage`/`bonus_heal`/`bonus_effect_id`

### 3.4 UI: дорожка в `scenes/screens/game_screen.tscn`
- [x] Добавить `HBoxContainer ComboTrack` с 3 пустыми слотами (Panel-узлы)
- [x] В `game_screen.gd` подключиться к сигналам combo_track / turn_resolved
- [x] При каждом ходе обновлять слоты: имя карты + цвет (owner)

### 3.5 UI: вспышка комбо
- [x] При `combo_triggered` показать:
  - Затемнение фона на 1 сек
  - Большой текст с именем приёма по центру
  - Опционально: рамка вокруг 3 слотов дорожки
  - Опционально: sting (AudioStreamPlayer)
- [x] AnimationPlayer или Tween — что проще

### 3.6 Финальная проверка Фазы 3
- [x] Запустить партию игрок vs AI, попробовать собрать каждый из 8 рецептов
- [x] Хотя бы 2-3 рецепта должны срабатывать в обычной партии
- [x] Вспышка отображается корректно
- [x] ✅ ФАЗА 3 ЗАВЕРШЕНА

---

## ФАЗА 4 — Накал / Burst / Rage / Damage scaling

### 4.1 Damage scaling
- [x] В `turn_resolver._resolve_attack()` до применения урона:
      ```
      var effect_count = source.effect_use_count.get(card.data.effect, 0)
      var scale_mult = max(0.3, 1.0 - 0.1 * effect_count)
      damage = int(floor(damage * scale_mult))
      source.effect_use_count[card.data.effect] = effect_count + 1
      ```
- [x] Сброс счётчиков после 3 ходов без повтора эффекта (логика в game_state)

### 4.2 Tension накопление
- [x] В `turn_resolver` после успешного `_resolve_attack` с урон > 0:
      `source.tension = mini(source.tension + 1, CharacterStats.MAX_TENSION)`
- [x] При получении урона:
      `target.tension = mini(target.tension + 1, CharacterStats.MAX_TENSION)`

### 4.3 Tension UI
- [x] В `game_screen.tscn` добавить шкалу `ProgressBar PlayerTensionBar` и `OpponentTensionBar`
- [x] Обновлять в `_update_ui()`

### 4.4 Tension расход (EX modifier)
- [x] Кнопка / тап на карте в руке: «играть с бонусом» (если tension > 0)
- [x] Trade-off: -1 tension → +50% к damage/heal/shield этой карты
- [x] Логика в `play_turn` — принять параметр `boost: bool`

### 4.5 Burst-карта
- [x] Концепция: 1 универсальная Burst-карта в стартовой руке каждого игрока
- [x] Эффект: отменяет последние 2 хода оппонента (out of combo_track + reverses scales/stats)
- [x] Реализация: новый CardEffect.BURST или особый card_id, обрабатываемый отдельно

### 4.6 Rage-карта
- [x] Условие активации: `player.logic + player.emotion <= 3` и `not player.rage_used`
- [x] При выполнении условия — добавить Rage-карту в руку (1 раз за партию)
- [x] Большой урон одного типа, `max_uses: 1`
- [x] После использования — `rage_used = true`

### 4.7 Финальная проверка Фазы 4
- [ ] Damage scaling действительно ограничивает спам одного эффекта
- [ ] Tension шкала видна и заполняется логично
- [ ] Burst отменяет
- [ ] Rage появляется в нужный момент
- [ ] ✅ ФАЗА 4 ЗАВЕРШЕНА

---

## ФАЗА 5 — Плейтест → v0.2

### 5.1 Автоматический плейтест
- [ ] Расширить `test/test_match.gd`: 100 матчей AI vs AI, статистика
  - средняя длина партии
  - частота срабатываний каждого комбо
  - распределение исходов (player_won %)
  - частота rage / burst / комбо

### 5.2 Ручной плейтест
- [ ] Самим сыграть 10+ партий
- [ ] Записать наблюдения в `context/playtest_notes.md`:
  - что работает
  - что фрустрирует
  - где провисает темп
  - какие комбо ощущаются круто / тускло

### 5.3 Обновление дизайн-дока
- [ ] Создать `context/game_design_v02.md` (или обновить существующий с маркером версии)
- [ ] Закрыть пункты «парковки» по результатам плейтеста
- [ ] Принять решения по: длине дорожки (3 → 5?), 4-му типу карт, скрытой карте, размеру руки, новым рецептам

---

## Гайдлайны для будущего «холодного» агента

Если ты сессия, попавшая на этот чеклист с нуля:

1. **Прочти `context/game_design.md`** до конца — без него действия не имеют смысла.
2. **Прочти этот файл сверху** — найди первый невыполненный `- [ ]` пункт.
3. **Не прыгай через фазы.** Порядок A → B → C → D → E важен.
4. **После каждого шага запускай smoke-test:** `test/test_match.tscn`.
5. **После каждой фазы обнови этот чеклист:** замени `- [ ]` на `- [x]` для сделанных, добавь «✅ ФАЗА X ЗАВЕРШЕНА» в раздел «Состояние».
6. **Если что-то идёт не по плану** — добавь раздел `## Заметки и отклонения` внизу и фиксируй там. Не правь молча.
7. **При сомнениях по дизайн-решениям** — спроси пользователя, не додумывай за него. Парковка в `game_design.md` §10 — это вопросы, которые **нельзя** решать в одиночку.
8. **Текущие конвенции кода** (из существующих файлов):
   - Static typing везде (`var x: int`, `func y() -> void`)
   - `class_name X extends Y` для классов
   - Сигналы через `signal`
   - Имена в snake_case
   - Русские названия карт сохраняются, английские — для card_id/тегов

---

## Заметки и отклонения

### Фаза 1

**Отклонение 1.5 — резолвер реализован полностью, а не как placeholder.**
Изначально в плане `combo_resolver.gd` должен был возвращать всегда `null`, а реальная
логика матчинга — в Фазе 3. На практике алгоритм компактный (~15 строк, `_matches()`),
поэтому реализован сразу. Поведение для пользователя идентично placeholder'у, потому
что `recipes` пуст. В Фазе 3 нужно будет только добавить рецепты и вызвать `check()` из
`game_state`.

**Архитектурный нюанс 1.3 — `slot_matches` вынесен в `ComboRecipe`, а не в `ComboResolver`.**
Логика «совпадает ли слот паттерна с entry трека» — внутреннее знание рецепта, а не
резолвера. Резолвер теперь тоньше, рецепт самодостаточен.

**Поле `card_id` теперь экспортируется явно.** Старое `id` удалено (был выводимым из
`card_name`). По grep'у никто не ссылался — безопасно. JSON-парсер падает обратно на
snake_case если `id` отсутствует в данных (старые колоды продолжают работать).

### Фаза 2

**Smoke-test в Godot перенесён на ручную проверку.** Автоматически проверены JSON и
ссылки deck/theme → universal card: 22 universal cards, 3 themes, 3 decks, неизвестных
`card_id` нет. После ручного подтверждения комбо Фаза 2 отмечена закрытой.

### Фаза 3

**`v0_combos.json` использует строковые значения для owner/category/effect.**
`ComboRecipe.from_dict()` теперь парсит `attack/defense/evasion`, `logic/emotion/...`,
а также поддерживает дополнительные ограничения слота: `card_id`, `tag`,
`same_card_as`, `min_damage`, `max_damage`.

**`Эмоциональный шквал` адаптирован под общее окно из 3 карт.** В исходном тексте
`[ТЫ:EMOTION_ATK]×3` плохо ложится на текущую общую дорожку `[ТЫ][ОН][ТЫ]`, поэтому
v0.1-рецепт матчится как две эмоциональные атаки игрока через любой ответ оппонента.

**`bonus_effect_id` пока лёгкие прототипные хуки.** Реализованы `discard_one`,
`break_shield`, `mirror_finish`, `fortify_shield`, `dogmatic_debuff`. Долгие состояния
вроде «щит не разрушается до конца партии» и «следующая ATK -50%» не вводились, чтобы
не перескакивать в Фазу 4.

### Фаза 4

**4.1–4.4 сделаны отдельным безопасным срезом.** Damage scaling живёт в
`turn_resolver._resolve_attack()`, decay счётчиков — в `game_state.gd` после каждого
сыгранного хода стороны. Tension начисляется источнику и цели, когда после щита прошёл
реальный урон.

**EX modifier сделан отдельной кнопкой под картой.** Обычный клик играет карту как
раньше, кнопка `EX +50%` доступна при `player.tension > 0` и вызывает
`play_turn(card, true)`. Burst/Rage оставлены следующим блоком, потому что для Burst
нужен отдельный журнал эффектов/откат истории.

**Burst реализован через дельты действий, а не полный snapshot-rollback.** `GameState`
ведёт `action_history` для обычных карт и при `special_burst` отменяет до 2 последних
действий оппонента: откатывает logic/emotion/max stats/points/shield/tension/scales,
убирает соответствующие entries из combo track и пересобирает `last_card`.
Руки/диски не откатываются намеренно, чтобы не ломать порядок добора и расход карт.

**Rage — обычная special attack-карта.** `special_rage` добавляется в руку, когда
`logic + emotion <= 3`, если Rage ещё не использовался и карта ещё не выдана. Механически
это одноразовая emotion-атака на 5 урона; после расхода выставляется `rage_used = true`.

**UX pass после Фазы 4.** Карта в руке теперь показывает не только механику, но и
тематическое высказывание (`CardInstance.get_text()`), чтобы при тесте было видно,
какую фразу произносит риторический приём. Для `special_burst` и `special_rage`
добавлены theme overrides во все 3 темы. Боевые логи переведены на русский, а рука и
combo track визуально разнесены на отдельные тестовые панели.
