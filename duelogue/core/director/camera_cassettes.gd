extends RefCounted

## DUELOGUE — КАТАЛОГ КАМЕРА-КАССЕТ v0.1. Это ДАННЫЕ, не правила: ShotDirector решает, когда
## и какую кассету вытянуть, каталог задаёт набор и характер. Черновик — не провалидирован в
## движке/на арте (context/director_core_v0.1.md §5-6). Ракурс и рельс комбинированы в
## КУРИРОВАННЫЕ пары (не полный кросс 5×4 — избегаем кросс-таблицы, см. риск в §2 спеки).
##
## fx_profile сознательно НЕ поле кассеты: фон-спидлайны уже ключуются по mood напрямую
## (MOOD_FX в reaction_scene.gd) — кассета его не трогает и не дублирует.
##
## compatible_states — тег РЕГИСТРА (§16 narrative_engine.md), не эксклюзивная привязка:
## несколько кассет могут делить стейт (иначе мешку из одного элемента нечего мешать).

const DATA := {
	"id": "camera_cassettes_v0.1",
	"cassettes": [
		{
			"id": "steady_approach", "camera_angle": "push_in_front", "transition_in": "straight_dolly",
			"duration_mult": 1.0, "weight": 1,
			"compatible_states": ["idle", "declare", "hold"],
		},
		{
			"id": "favored_arc", "camera_angle": "three_quarter_favor", "transition_in": "diagonal_sweep",
			"duration_mult": 1.0, "weight": 1,
			"compatible_states": ["swagger", "gotcha", "declare"],
		},
		{
			"id": "cornered_drift", "camera_angle": "low_creep", "transition_in": "slow_drift",
			"duration_mult": 1.15, "weight": 1,
			"compatible_states": ["panic", "evade"],
		},
		{
			"id": "shock_snap", "camera_angle": "tight_snap", "transition_in": "whip_snap",
			"duration_mult": 0.7, "weight": 1,
			"compatible_states": ["burst", "stagger", "attack"],
		},
		{
			"id": "planted_hold", "camera_angle": "hold_steady", "transition_in": "straight_dolly",
			"duration_mult": 0.9, "weight": 1,
			"compatible_states": ["hold", "idle"],
		},
	],
}


static func data() -> Dictionary:
	return DATA.duplicate(true)
