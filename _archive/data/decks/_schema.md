# Decks Schema v2

`data/decks/<deck>.json` — определение колоды как **списка card_id** + ссылка на тему.

Никакого карточного контента в файле колоды нет — только ссылки.

## Структура файла

```json
{
  "id": "default_kofe",
  "display_name": "Кофе",
  "theme_id": "coffee",
  "cards": {
    "player_attack_cards": ["atk_logic_m1", "atk_emotion_m1", "atk_logic_m2", ...],
    "enemy_attack_cards": ["atk_logic_m3", "atk_emotion_m2", ...],
    "defense_cards": ["def_heal_logic", "def_heal_emotion", "def_shield"],
    "evasion_cards": ["evd_cancel", "evd_mirror", "evd_reflect"],
    "rare_attack_cards": [],
    "repeat_card": "special_repeat"
  }
}
```

## Поля

| Поле | Тип | Назначение |
|---|---|---|
| `id` | string | Стабильный идентификатор колоды |
| `display_name` | string | Имя колоды в UI (часто совпадает с темой) |
| `theme_id` | string | Какую тему применять для оверрайдов |
| `cards.player_attack_cards` | array<string> | card_id для атак игрока |
| `cards.enemy_attack_cards` | array<string> | card_id для атак противника |
| `cards.defense_cards` | array<string> | card_id защитных карт |
| `cards.evasion_cards` | array<string> | card_id evasion-карт |
| `cards.rare_attack_cards` | array<string> | card_id редких/мощных атак (опционально) |
| `cards.repeat_card` | string | card_id «карты повторения» (опционально) |

## Как ассемблируется CardData

1. Для каждого card_id из колоды CardDatabase резолвит карту:
   - Берёт базовый `CardData` из `universal_cards.json` (по id)
   - Применяет оверрайды из темы (если есть)
   - Возвращает готовый `CardData` instance
2. Карты складываются в соответствующие списки `DeckData`

## Соглашения

- Card_id может повторяться в одном списке (если колода использует одну механику в нескольких формулировках)
- Если universal_cards.json не содержит указанный card_id — лог ошибки, карта пропускается
- Если theme.json не имеет оверрайда для card_id — используется дефолт из universal
