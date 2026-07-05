class_name DeckData
extends Resource

## Pure data holder for a deck. Populated by CardDatabase by resolving card_ids from
## the deck JSON against universal_cards.json + theme overrides.

@export var deck_name: String
@export var player_attack_cards: Array[CardData]
@export var enemy_attack_cards: Array[CardData]
@export var defense_cards: Array[CardData]
@export var evasion_cards: Array[CardData]
@export var rare_attack_cards: Array[CardData]
@export var repeat_card: CardData
@export var burst_card: CardData
@export var rage_card: CardData
