extends RefCounted

## Набор калибровочных профилей отношений «доска ↔ зал ↔ раздражение».
## Это данные, а не реализация: AudienceCore читает audience, RulesCore — links/terminal,
## OutcomeEvaluator — board/victory. Новый эксперимент добавляется одной записью.

const DEFAULT_ID := "vector_reaction"

const REACTION_VALUES := {
	"audience_check": 1,
	"snap": 1,
	"personal_jab": -1,
	"crack": -1,
}

const PROFILES := [
	{
		"id": "vector_reaction",
		"label": "Вектор: доска решает",
		"description": "Победитель — по логике; зал и раздражение остаются отдельными итогами.",
		"board": {"frame_weight": 3, "thesis_weight": 1},
		"audience": {
			"mode": "pendulum", "lean_cap": 5, "heat_max": 3,
			"valence_mode": "reaction_priority", "spectacle_threshold": 2,
			"quiet_cool": 1, "lean_friction": 0, "heat_amplifies": true,
			"reaction_values": REACTION_VALUES, "parry_value": 1,
		},
		"links": {"gate_x": 0, "gate_y": 0, "crowd_ko": 0, "crowd_hold": 1},
		"terminal": {"board_ko": false},
		"victory": {"mode": "board", "audience_weight": 0},
	},
	{
		"id": "vector_gate",
		"label": "Вектор + гейт 2/4",
		"description": "Доска решает; зал косвенно влияет на будущие захваты.",
		"board": {"frame_weight": 3, "thesis_weight": 1},
		"audience": {
			"mode": "pendulum", "lean_cap": 5, "heat_max": 3,
			"valence_mode": "reaction_priority", "spectacle_threshold": 2,
			"quiet_cool": 1, "lean_friction": 0, "heat_amplifies": true,
			"reaction_values": REACTION_VALUES, "parry_value": 1,
		},
		"links": {"gate_x": 2, "gate_y": 4, "crowd_ko": 0, "crowd_hold": 1},
		"terminal": {"board_ko": false},
		"victory": {"mode": "board", "audience_weight": 0},
	},
	{
		"id": "mandate_diagnostic",
		"label": "Диагностика: логика + мандат",
		"description": "Экспериментальный итог B + sign(Lean)×Heat.",
		"board": {"frame_weight": 3, "thesis_weight": 1},
		"audience": {
			"mode": "pendulum", "lean_cap": 5, "heat_max": 3,
			"valence_mode": "reaction_priority", "spectacle_threshold": 2,
			"quiet_cool": 1, "lean_friction": 0, "heat_amplifies": true,
			"reaction_values": REACTION_VALUES, "parry_value": 1,
		},
		"links": {"gate_x": 0, "gate_y": 0, "crowd_ko": 0, "crowd_hold": 1},
		"terminal": {"board_ko": false},
		"victory": {"mode": "mandate", "audience_weight": 1},
	},
	{
		"id": "additive_diagnostic",
		"label": "Диагностика: логика + Lean",
		"description": "Старый тип суммы, но с независимым маятником зала.",
		"board": {"frame_weight": 3, "thesis_weight": 1},
		"audience": {
			"mode": "pendulum", "lean_cap": 5, "heat_max": 3,
			"valence_mode": "reaction_priority", "spectacle_threshold": 2,
			"quiet_cool": 1, "lean_friction": 0, "heat_amplifies": true,
			"reaction_values": REACTION_VALUES, "parry_value": 1,
		},
		"links": {"gate_x": 0, "gate_y": 0, "crowd_ko": 0, "crowd_hold": 1},
		"terminal": {"board_ko": false},
		"victory": {"mode": "additive", "audience_weight": 1},
	},
	{
		"id": "legacy",
		"label": "Legacy: ширина → старый зал",
		"description": "Контроль прежних правил, включая производный зал, гейт и TKO.",
		"board": {"frame_weight": 1, "thesis_weight": 1},
		"audience": {"mode": "derived", "lean_cap": 10, "heat_max": 0},
		"links": {"gate_x": 2, "gate_y": 4, "crowd_ko": 10, "crowd_hold": 3},
		"terminal": {"board_ko": true},
		"victory": {"mode": "legacy", "audience_weight": 1},
	},
]


static func all() -> Array:
	return PROFILES.duplicate(true)


static func get_profile(profile_id: String) -> Dictionary:
	for profile in PROFILES:
		if String(profile.id) == profile_id:
			return (profile as Dictionary).duplicate(true)
	return (PROFILES[0] as Dictionary).duplicate(true)


static func has_profile(profile_id: String) -> bool:
	for profile in PROFILES:
		if String(profile.id) == profile_id:
			return true
	return false
