# Universal Cards Schema

`data/cards/universal_cards.json` — пул механически-уникальных карт. Тематически нейтральные
имена и описания (фолбэк, если тема ничего не оверрайдит).

## Структура файла

Top-level: массив объектов.

```json
[
  {
    "id": "atk_logic_m1",
    "category": "Атака",
    "effect": "logic",
    "damage": 2,
    "heal": 0,
    "shield": 0,
    "modifier": 1.0,
    "usesLeft": 2,
    "combo_tags": ["pressure"],
    "name": "Логический довод",
    "desc": "Средний урон логике"
  }
]
```

## Поля

| Поле | Тип | Назначение |
|---|---|---|
| `id` | string | Стабильный snake_case идентификатор. Никогда не меняется (на него ссылаются темы и колоды). |
| `category` | string | `"Атака"` / `"Защита"` / `"Уклонение"` (русские строки, парсятся в `CardCategory`) |
| `effect` | string | `"logic"` / `"emotion"` / `"shield"` / `"cancel"` / `"mirror"` / `"reflect"` / `"random"` / `"burst"` |
| `damage` | int | Базовый урон (для атак) |
| `heal` | int | Базовый хил (для защит) |
| `shield` | int | Размер щита |
| `modifier` | float | Множитель (для mirror = 0.75) |
| `usesLeft` | int | Max uses карты (название историческое, парсится как `max_uses`) |
| `combo_tags` | array<string> | Хинты для комбо-рецептов: `starter`/`linker`/`finisher`/`interrupt`/`bait`/`pressure` |
| `name` | string | Дефолтное имя (используется если тема не оверрайдит) |
| `desc` | string | Дефолтное описание |

## Соглашения по `id`

Префикс по категории:
- `atk_*` — атаки
- `def_*` — защита
- `evd_*` — уклонение
- `special_*` — специальные карты (repeat и т.п.)

Для атак — `<категория>_<эффект>_<сила><индекс>`:
- `m` (medium): damage 2, uses 2
- `s` (strong): damage 3, uses 1
- `h` (heavy): damage 4, uses 1 (обычно `random`)
- `xl` (extra): damage 5+, uses 1

Индекс `1/2/3` — для случаев, когда нужно несколько слотов одной механической сигнатуры
(например, колода Coffee использует 3 medium-logic атаки разными формулировками).

## Что НЕ хранится здесь

- Текстовые варианты (`textVariants`) — это флейвор, лежит в темах
- `text` для конкретной реплики — тоже в темах
- Арт, sfx — будущие слои в темах
