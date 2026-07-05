# Themes Schema

`data/themes/<theme_id>/theme.json` — пакет «фантика»: имена, описания и текст-варианты
для универсальных карт. Если тема не оверрайдит карту — берётся дефолт из
`universal_cards.json`.

## Структура файла

```json
{
  "id": "coffee",
  "display_name": "Кофе",
  "card_overrides": {
    "atk_logic_m1": {
      "name": "Факт о кофеине",
      "desc": "Средний урон логике",
      "text": "Кофеин улучшает когнитивные функции!",
      "textVariants": [
        "Кофеин улучшает когнитивные функции!",
        "Научно доказано: кофеин повышает концентрацию!"
      ]
    },
    "atk_emotion_m1": {
      "name": "Любовь к кофе",
      "text": "Кофе приносит радость миллионам!"
    }
  }
}
```

## Поля

| Поле | Тип | Назначение |
|---|---|---|
| `id` | string | Стабильный идентификатор темы (snake_case) |
| `display_name` | string | Имя темы, отображаемое в UI |
| `card_overrides` | object | Карта `card_id` → словарь оверрайдов |

## Поля внутри `card_overrides[card_id]`

Все поля опциональны. Если поле отсутствует — используется дефолт из universal_cards.json.

| Поле | Тип | Что переопределяет |
|---|---|---|
| `name` | string | `card_name` |
| `desc` | string | `description` |
| `text` | string | `text` |
| `textVariants` | array<string> | `text_variants` |

## Что НЕ переопределяется темой

Механические числа (`damage`, `heal`, `shield`, `usesLeft`, `category`, `effect`, `combo_tags`).
Тема — это **только флейвор**. Хочешь поменять числа — это новый универсальный card_id.

## Будущие расширения

- `art_path` — путь к арту карты
- `sfx_path` — звуковой эффект при розыгрыше
- `portrait` — портрет оппонента
- `music` — фоновая музыка темы
