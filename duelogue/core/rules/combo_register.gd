extends RefCounted

## DUELOGUE — COMBO REGISTER v0.1: шаги R2–R4 лестницы (context/combo_register_architecture_v0.1.md §9).
## Один регистр на матч внутри RulesCore: декларативный Pattern-каталог + derived PatternRun'ы
## над relation trace R1. Route names здесь НЕ ветвят механику: constraint'ы читают Grammar и
## факты (play/relation/outcome/доска), вердикты выводятся из runs, а не хранятся mutable-полями.
## Интерпретатор намеренно покрывает ровно те типы constraint'ов, которые нужны текущему
## каталогу (§8: без wildcards, рекурсии и backtracking); сам каталог — данные.
##
## R3: две стороны. Кроме структурного G-01 GUARD каталог держит X-01 TRAP (owner —
## атакующий, та же тройка T₀–R₀–T₁) и P-01 RTR-PRESSURE (R₀–T₁–R₂, НЕ читает схему T₀).
## Оба вооружаются только при подтверждающей content-RelationFact (шов §7 вариант 2:
## controller добавляет её ПОСЛЕ физического play). Отсутствие семантики — не отрицательный
## факт: структурно полный кандидат без content-ребра терминализируется UNRESOLVED.
## R4: общий arbitration-channel, tier-supersede без fallback, explicit CONTESTED
## G-04/X-04 и frame-scoped one-shot F3. Численный payoff по-прежнему НЕ применяется:
## наружу уходят только combo_events[], а подключение награды начинается после R4.
##
## Легаси-поля combo_*/closer_* клинча и info — ПРОЕКЦИЯ legacy_view() (§7 переходная
## совместимость): после перевода UI/AI на combo_events они исчезнут.

const Grammar := preload("res://duelogue/core/cards/grammar.gd")

## G-01 GUARD — защитная тройка §4 v0.2. Роли символические: A — атакующий, B — защитник.
## LINK: eligible-якорь с маршрутом ANSWER_OF; ARMED: первый ответ, парирующий exact опенер
## правильной схемой; CONFIRM: owner выстоял, exact closer held и его тезис стоит на рамке.
## Остаётся структурным (без content-гейта): 20 маршрутов ANSWER_OF — guard-only резерв
## до отдельной миграции (combo_a3_topologies §11).
const P_G01_GUARD := {
	"id": "g01_guard", "version": 1, "family": "GUARD", "topology": "trt_guard",
	"scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 0},
	"path": [
		{"slot": "$open", "role": "A", "card": {"type": "R"}, "selector": "first"},
		{"slot": "$close", "role": "B", "card": {"type": "T"}, "selector": "first_response"},
	],
	"where": [
		{"kind": "anchor_route", "setup": "$anchor", "attack": "$open"},
		{"kind": "responds_to", "from": "$close", "to": "$open"},
		{"kind": "bind", "slot": "$closer_thesis", "rel": "materializes_as", "from": "$close"},
		{"kind": "grammar_answers", "setup": "$anchor", "attack": "$open", "answer": "$close"},
	],
	"claim": {
		"owner": "B",
		"confirm": [
			{"kind": "winner", "role": "B"},
			{"kind": "outcome", "slot": "$close", "result": "held"},
			{"kind": "board_contains", "bind": "$closer_thesis"},
		],
	},
}

## Semantic G-01 для уже мигрированной пары source_backed/false_independence.
## Старый structural G-01 остаётся legacy-view остальных 18 маршрутов, но на этой
## exact тройке становится shadow: independent lineage подтверждает этот run,
## dependent lineage — X-01, неизвестность — ни один.
const P_G01_SOURCE := {
	"id": "g01_source_backed", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Источник подтверждён", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}

## X-01 «Ложная независимость» (combo_a3_topologies §4) — TRAP над той же тройкой, что
## G-01 source_backed: опора предъявлена как независимое подтверждение, но лишь
## воспроизводит исходное свидетельство. Owner — владелец Разбора. Content-гейт:
## supports($reply → claim) с attrs {claimed_lineage: independent, lineage: dependent}.
const P_X01_TRAP := {
	"id": "x01_false_independence", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Ложная независимость",
	"scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {
		"owner": "A",
		"confirm": [
			{"kind": "winner", "role": "A"},
			{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
			{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
			{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
		],
	},
}

## P-01 «Эксперт по делу?» (combo_a3_topologies §5) — RTR-PRESSURE R₀–T₁–R₂: требование
## основания → ссылка на эксперта → CQ о компетенции. НЕ читает схему T₀ (работает и над
## технической Базой), owner — атакующий. Content-гейт: undercuts($press → $reply)
## с attrs {reason: domain_mismatch}.
const P_P01_PRESSURE := {
	"id": "p01_expert_domain", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Эксперт по делу?",
	"scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {
		"owner": "A",
		"confirm": [
			{"kind": "winner", "role": "A"},
			{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
			{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
			{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
		],
	},
}

## G-04/X-04 — explicit CONTESTED над одной структурной тройкой
## Аналогия → Ложная аналогия → Определение. Обе ветви требуют собственную exact
## semantic basis: заранее обоснованный общий признак для GUARD и post-hoc qualifier
## для TRAP. CONTESTED не хранится: это проекция двух armed runs разных владельцев.
const P_G04_GUARD := {
	"id": "g04_shared_core", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Суть сходства", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Аналогия"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "сходство"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}

const P_X04_TRAP := {
	"id": "x04_redrawn_similarity", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Сходство дорисовано", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Аналогия"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "сходство"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

## Остальные 16 из 20 маршрутов ANSWER_OF раскрыты той же формой, что source_backed/
## shared_core выше: GUARD и TRAP над одной тройкой — гонка за один и тот же exact
## $reply без content-гейта. Оба вооружаются чисто структурно (тот же setup+hook+ответ,
## что и generic G-01); какой из них реально подтвердится на settlement, решает не
## авторская разметка, а физика клинча — held vs removed/stolen exact $reply. Это тот же
## contested-по-факту принцип, что уже был у explicit G-04/X-04, просто без ручного
## authored $basis: тут различать нечего заранее, потому что сама тройка уже узкая
## (exact setup-схема + exact hook + exact ответ-схема). exception_noted и about_people
## осознанно не мигрируют (combo_a3_topologies §3: «остаются guard-only… не входят в
## первый тест»).
const P_DOMAIN_MATCH_GUARD := {
	"id": "domain_match_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Эксперт по делу", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_DOMAIN_MATCH_TRAP := {
	"id": "domain_match_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Область подогнана", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_EXPERT_CONSENSUS_GUARD := {
	"id": "expert_consensus_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Консенсус сильнее", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_EXPERT_CONSENSUS_TRAP := {
	"id": "expert_consensus_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Голоса не по делу", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_VOUCHED_NUMBERS_GUARD := {
	"id": "vouched_numbers_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Цифры с подписью", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_VOUCHED_NUMBERS_TRAP := {
	"id": "vouched_numbers_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Подпись без проверки", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_MECHANISM_SHOWN_GUARD := {
	"id": "mechanism_shown_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Механизм на столе", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_MECHANISM_SHOWN_TRAP := {
	"id": "mechanism_shown_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Иллюстрация вместо механизма", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_OUTLIER_DISMISSED_GUARD := {
	"id": "outlier_dismissed_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Исключение — не правило", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_OUTLIER_DISMISSED_TRAP := {
	"id": "outlier_dismissed_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Отмахнулись нормой", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_TYPICAL_CASE_GUARD := {
	"id": "typical_case_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Пример типичен", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_TYPICAL_CASE_TRAP := {
	"id": "typical_case_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Выборка мимо тезиса", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_DOCUMENTED_CASE_GUARD := {
	"id": "documented_case_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Случай задокументирован", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_DOCUMENTED_CASE_TRAP := {
	"id": "documented_case_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Свидетель понаслышке", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_SAME_CLASS_GUARD := {
	"id": "same_class_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Тот же класс", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "сходство"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_SAME_CLASS_TRAP := {
	"id": "same_class_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Класс подогнан", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Пример"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "сходство"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_BORDERS_RESTORED_GUARD := {
	"id": "borders_restored_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Возвращаю границы", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_BORDERS_RESTORED_TRAP := {
	"id": "borders_restored_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Граница после удара", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_LIVING_TRADITION_GUARD := {
	"id": "living_tradition_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Традиция жива", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_LIVING_TRADITION_TRAP := {
	"id": "living_tradition_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Ностальгия вместо довода", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_COMMONLY_MEASURED_GUARD := {
	"id": "commonly_measured_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Общее место измерено", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_COMMONLY_MEASURED_TRAP := {
	"id": "commonly_measured_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Опрос не о том", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_MEASURED_SENSE_GUARD := {
	"id": "measured_sense_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Здравая мера", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_MEASURED_SENSE_TRAP := {
	"id": "measured_sense_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Мера на словах", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_GROUNDED_FEELING_GUARD := {
	"id": "grounded_feeling_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Чувство с фактурой", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Эмоция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_GROUNDED_FEELING_TRAP := {
	"id": "grounded_feeling_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Цифры для вида", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Эмоция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_BY_THE_BOOK_GUARD := {
	"id": "by_the_book_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "По словарю", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_BY_THE_BOOK_TRAP := {
	"id": "by_the_book_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Не тот словарь", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_SANE_BOUNDS_GUARD := {
	"id": "sane_bounds_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Границы очевидны", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_SANE_BOUNDS_TRAP := {
	"id": "sane_bounds_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Придуманная граница", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_ESTABLISHED_USAGE_GUARD := {
	"id": "established_usage_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Устоявшееся значение", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Традиция"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_ESTABLISHED_USAGE_TRAP := {
	"id": "established_usage_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Личная привычка", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Определение"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Традиция"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

## Второй принятый ответ у четырёх маршрутов: ANSWER_OF в grammar.gd изначально
## разрешает две закрывающие схемы, но первый проход миграции взял только первую
## (не трогать интерпретатор _card_matches). Тот же route_id/combo_name — это то же
## риторическое чтение, просто ещё одна карта, которая его честно закрывает.
const P_MECHANISM_SHOWN_ANALOGY_GUARD := {
	"id": "mechanism_shown_analogy_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Механизм на столе", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_MECHANISM_SHOWN_ANALOGY_TRAP := {
	"id": "mechanism_shown_analogy_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Иллюстрация вместо механизма", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_OUTLIER_DISMISSED_STATS_GUARD := {
	"id": "outlier_dismissed_stats_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Исключение — не правило", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_OUTLIER_DISMISSED_STATS_TRAP := {
	"id": "outlier_dismissed_stats_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Отмахнулись нормой", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_LIVING_TRADITION_EMOTION_GUARD := {
	"id": "living_tradition_emotion_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Традиция жива", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Эмоция"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_LIVING_TRADITION_EMOTION_TRAP := {
	"id": "living_tradition_emotion_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Ностальгия вместо довода", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Эмоция"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

const P_MEASURED_SENSE_COMMONSENSE_GUARD := {
	"id": "measured_sense_commonsense_guard", "version": 1, "family": "A3", "topology": "trt_guard",
	"combo_name": "Здравая мера", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": [
		{"kind": "winner", "role": "B"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
		{"kind": "board_contains", "bind": "$reply_thesis"},
	]},
}
const P_MEASURED_SENSE_COMMONSENSE_TRAP := {
	"id": "measured_sense_commonsense_trap", "version": 1, "family": "A3", "topology": "trt_trap",
	"combo_name": "Мера на словах", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
		{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
		{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
	]},
}

## P-06 закрывает документированный upgrade X-01 → PRESSURE: та же первая пара
## Источник? → Статистика, затем Корреляция по exact T₁. Tier 3 навсегда supersede'ит
## tier-2 TRAP того же владельца; BREAK верхней ставки не возвращает нижнюю.
const P_P06_PRESSURE := {
	"id": "p06_double_audit", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Двойной аудит", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 25},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}

## P-02…P-05 из каталога combo_a3_topologies §5 — та же content-free гонка: путь узкий
## (exact hook → exact scheme → exact hook), settlement решает через уже отработавшие
## outcome/effect/affected_is confirm-атомы P-01/P-06.
const P_P02_PRESSURE := {
	"id": "p02_moving_goalposts", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Определение на ходу", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}

const P_P03_PRESSURE := {
	"id": "p03_reductio_check", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Закрепил — проверил предел", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "подмена"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Определение"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}

## Два варианта одного «Механизм не выдержал кейса»: T₁ может быть Примером или
## Аналогией, у каждого свой правильный контр-hook (§5 таблицы).
const P_P04A_PRESSURE := {
	"id": "p04a_mechanism_example", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Механизм не выдержал кейса", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}
const P_P04B_PRESSURE := {
	"id": "p04b_mechanism_analogy", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Механизм не выдержал кейса", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "сходство"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}

const P_P05_PRESSURE := {
	"id": "p05_show_the_sample", "version": 1, "family": "A3", "topology": "rtr_pressure",
	"combo_name": "Покажи выборку", "scope": "action",
	"arbitration": {"channel": "clinch", "tier": 3, "priority": 20},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Статистика"},
			"selector": "next"},
		{"slot": "$press", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "next"},
	],
	"where": [
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
		{"kind": "targets", "from": "$press", "to": "$reply_thesis"},
	],
	"claim": {"owner": "A", "confirm": [
		{"kind": "winner", "role": "A"},
		{"kind": "outcome_in", "slot": "$press", "results": ["landed"]},
		{"kind": "effect_in", "slot": "$press", "effects": ["breakdown", "steal_thesis"]},
		{"kind": "affected_is", "slot": "$press", "bind": "$reply_thesis"},
	]},
}

## F3-10 «Вверх и обратно»: frame-scoped snapshot-рецепт. Случайное совпадение трёх
## схем недостаточно — exact authored-карты несут rhetoric.frame_recipe_id. Matcher
## проверяет только новый верхний суффикс на board_stable и платит one-shot по frame_id.
const P_F310_FRAME := {
	"id": "f3_10_ascent_return", "version": 1, "family": "F3", "topology": "ttt_frame",
	"combo_name": "Вверх и обратно", "scope": "frame", "match_mode": "snapshot",
	"arbitration": {"channel": "frame", "tier": 3, "priority": 10},
	"path": [
		{"slot": "$t0", "card": {"type": "T", "scheme": "Пример"}},
		{"slot": "$t1", "card": {"type": "T", "scheme": "Определение"}},
		{"slot": "$t2", "card": {"type": "T", "scheme": "Пример"}},
	],
	"claim": {"owner": "A"},
	"one_shot": true,
}

## A3-вахты, открываемые опенером (G-01 создаётся отдельной старой дорожкой).
const A3_CATALOG := [
	P_G01_SOURCE, P_X01_TRAP, P_P01_PRESSURE, P_G04_GUARD, P_X04_TRAP, P_P06_PRESSURE,
	P_DOMAIN_MATCH_GUARD, P_DOMAIN_MATCH_TRAP,
	P_EXPERT_CONSENSUS_GUARD, P_EXPERT_CONSENSUS_TRAP,
	P_VOUCHED_NUMBERS_GUARD, P_VOUCHED_NUMBERS_TRAP,
	P_MECHANISM_SHOWN_GUARD, P_MECHANISM_SHOWN_TRAP,
	P_OUTLIER_DISMISSED_GUARD, P_OUTLIER_DISMISSED_TRAP,
	P_TYPICAL_CASE_GUARD, P_TYPICAL_CASE_TRAP,
	P_DOCUMENTED_CASE_GUARD, P_DOCUMENTED_CASE_TRAP,
	P_SAME_CLASS_GUARD, P_SAME_CLASS_TRAP,
	P_BORDERS_RESTORED_GUARD, P_BORDERS_RESTORED_TRAP,
	P_LIVING_TRADITION_GUARD, P_LIVING_TRADITION_TRAP,
	P_COMMONLY_MEASURED_GUARD, P_COMMONLY_MEASURED_TRAP,
	P_MEASURED_SENSE_GUARD, P_MEASURED_SENSE_TRAP,
	P_GROUNDED_FEELING_GUARD, P_GROUNDED_FEELING_TRAP,
	P_BY_THE_BOOK_GUARD, P_BY_THE_BOOK_TRAP,
	P_SANE_BOUNDS_GUARD, P_SANE_BOUNDS_TRAP,
	P_ESTABLISHED_USAGE_GUARD, P_ESTABLISHED_USAGE_TRAP,
	P_MECHANISM_SHOWN_ANALOGY_GUARD, P_MECHANISM_SHOWN_ANALOGY_TRAP,
	P_OUTLIER_DISMISSED_STATS_GUARD, P_OUTLIER_DISMISSED_STATS_TRAP,
	P_LIVING_TRADITION_EMOTION_GUARD, P_LIVING_TRADITION_EMOTION_TRAP,
	P_MEASURED_SENSE_COMMONSENSE_GUARD, P_MEASURED_SENSE_COMMONSENSE_TRAP,
	P_P02_PRESSURE, P_P03_PRESSURE, P_P04A_PRESSURE, P_P04B_PRESSURE, P_P05_PRESSURE,
]
const FRAME_CATALOG := [P_F310_FRAME]

## Все runs матча (append-only, терминальные остаются как доказательство для телеметрии).
var runs := {}
## Контекст action-scope: g01 run + a3-вахты + стороны (аналог by_scope-индекса §3).
var scopes := {}
## Frame-scope one-shot и происхождение materialized T. Это не копия доски:
## authoritative thesis_stack приходит снапшотом только на board_stable.
var completions := {}
var thesis_origins := {}
var _events_by_action := {}
var _run_serial := 0
## Тестовый seam: пустой по умолчанию, ничего не меняет ни в одном существующем пути.
## Изолированные эксперименты (см. tools/combo_archetype_probe.gd) подсаживают сюда
## recipe-словари той же формы, что A3_CATALOG, до первого open_action_run.
var extra_a3_catalog: Array = []


func _pattern(pattern_id: String) -> Dictionary:
	match pattern_id:
		"g01_guard":
			return P_G01_GUARD
		"g01_source_backed":
			return P_G01_SOURCE
		"x01_false_independence":
			return P_X01_TRAP
		"p01_expert_domain":
			return P_P01_PRESSURE
		"g04_shared_core":
			return P_G04_GUARD
		"x04_redrawn_similarity":
			return P_X04_TRAP
		"p06_double_audit":
			return P_P06_PRESSURE
		"domain_match_guard":
			return P_DOMAIN_MATCH_GUARD
		"domain_match_trap":
			return P_DOMAIN_MATCH_TRAP
		"expert_consensus_guard":
			return P_EXPERT_CONSENSUS_GUARD
		"expert_consensus_trap":
			return P_EXPERT_CONSENSUS_TRAP
		"vouched_numbers_guard":
			return P_VOUCHED_NUMBERS_GUARD
		"vouched_numbers_trap":
			return P_VOUCHED_NUMBERS_TRAP
		"mechanism_shown_guard":
			return P_MECHANISM_SHOWN_GUARD
		"mechanism_shown_trap":
			return P_MECHANISM_SHOWN_TRAP
		"outlier_dismissed_guard":
			return P_OUTLIER_DISMISSED_GUARD
		"outlier_dismissed_trap":
			return P_OUTLIER_DISMISSED_TRAP
		"typical_case_guard":
			return P_TYPICAL_CASE_GUARD
		"typical_case_trap":
			return P_TYPICAL_CASE_TRAP
		"documented_case_guard":
			return P_DOCUMENTED_CASE_GUARD
		"documented_case_trap":
			return P_DOCUMENTED_CASE_TRAP
		"same_class_guard":
			return P_SAME_CLASS_GUARD
		"same_class_trap":
			return P_SAME_CLASS_TRAP
		"borders_restored_guard":
			return P_BORDERS_RESTORED_GUARD
		"borders_restored_trap":
			return P_BORDERS_RESTORED_TRAP
		"living_tradition_guard":
			return P_LIVING_TRADITION_GUARD
		"living_tradition_trap":
			return P_LIVING_TRADITION_TRAP
		"commonly_measured_guard":
			return P_COMMONLY_MEASURED_GUARD
		"commonly_measured_trap":
			return P_COMMONLY_MEASURED_TRAP
		"measured_sense_guard":
			return P_MEASURED_SENSE_GUARD
		"measured_sense_trap":
			return P_MEASURED_SENSE_TRAP
		"grounded_feeling_guard":
			return P_GROUNDED_FEELING_GUARD
		"grounded_feeling_trap":
			return P_GROUNDED_FEELING_TRAP
		"by_the_book_guard":
			return P_BY_THE_BOOK_GUARD
		"by_the_book_trap":
			return P_BY_THE_BOOK_TRAP
		"sane_bounds_guard":
			return P_SANE_BOUNDS_GUARD
		"sane_bounds_trap":
			return P_SANE_BOUNDS_TRAP
		"established_usage_guard":
			return P_ESTABLISHED_USAGE_GUARD
		"established_usage_trap":
			return P_ESTABLISHED_USAGE_TRAP
		"mechanism_shown_analogy_guard":
			return P_MECHANISM_SHOWN_ANALOGY_GUARD
		"mechanism_shown_analogy_trap":
			return P_MECHANISM_SHOWN_ANALOGY_TRAP
		"outlier_dismissed_stats_guard":
			return P_OUTLIER_DISMISSED_STATS_GUARD
		"outlier_dismissed_stats_trap":
			return P_OUTLIER_DISMISSED_STATS_TRAP
		"living_tradition_emotion_guard":
			return P_LIVING_TRADITION_EMOTION_GUARD
		"living_tradition_emotion_trap":
			return P_LIVING_TRADITION_EMOTION_TRAP
		"measured_sense_commonsense_guard":
			return P_MEASURED_SENSE_COMMONSENSE_GUARD
		"measured_sense_commonsense_trap":
			return P_MEASURED_SENSE_COMMONSENSE_TRAP
		"p02_moving_goalposts":
			return P_P02_PRESSURE
		"p03_reductio_check":
			return P_P03_PRESSURE
		"p04a_mechanism_example":
			return P_P04A_PRESSURE
		"p04b_mechanism_analogy":
			return P_P04B_PRESSURE
		"p05_show_the_sample":
			return P_P05_PRESSURE
		"f3_10_ascent_return":
			return P_F310_FRAME
	for raw in extra_a3_catalog:
		var extra: Dictionary = raw
		if String(extra.get("id", "")) == pattern_id:
			return extra
	return {}


## Карта соответствует card-спеке атома path/seed. Кража и safe poke отсеиваются сами:
## у них hook_of == "" и combo_eligible=false.
func _card_matches(card: Dictionary, spec: Dictionary) -> bool:
	if String(card.get("type", "")) != String(spec.get("type", "")):
		return false
	match String(spec.get("type", "")):
		"R":
			var hook := String(spec.get("hook", ""))
			return hook == "" or Grammar.hook_of(card) == hook
		"T":
			if not Grammar.eligible(card):
				return false
			var scheme := String(spec.get("scheme", ""))
			return scheme == "" or String(card.get("scheme", "")) == scheme
	return false


func _content_atoms(pattern: Dictionary) -> Array:
	var out: Array = []
	for raw in pattern.get("where", []):
		if String((raw as Dictionary).get("kind", "")) == "content":
			out.append(raw)
	return out


func _scope_run_ids(scope: Dictionary) -> Array:
	var out: Array = []
	if String(scope.get("g01", "")) != "":
		out.append(String(scope.g01))
	out.append_array(scope.get("a3", []))
	return out


func _owner_of(run: Dictionary) -> String:
	var pattern := _pattern(String(run.get("pattern_id", "")))
	return String((run.get("roles", {}) as Dictionary).get(
		String((pattern.get("claim", {}) as Dictionary).get("owner", "")), ""))


func _arbitration_of(run: Dictionary) -> Dictionary:
	return (_pattern(String(run.get("pattern_id", ""))).get(
		"arbitration", {}) as Dictionary)


## Вооружение — единственная точка tier-supersede. Более высокий tier того же owner/channel
## навсегда подавляет нижнюю ставку; если верхняя позднее ломается, fallback не возникает.
func _arm_run(run: Dictionary, scope: Dictionary) -> void:
	if run.is_empty() or String(run.get("state", "")) == "terminal":
		return
	run["armed_once"] = true
	var arb := _arbitration_of(run)
	var owner := _owner_of(run)
	var tier := int(arb.get("tier", 0))
	var channel := String(arb.get("channel", ""))
	for other_id in _scope_run_ids(scope):
		var other: Dictionary = runs.get(other_id, {})
		if other.is_empty() or String(other.get("id", "")) == String(run.get("id", "")) or \
				String(other.get("state", "")) != "armed":
			continue
		var other_arb := _arbitration_of(other)
		if _owner_of(other) != owner or String(other_arb.get("channel", "")) != channel:
			continue
		var other_tier := int(other_arb.get("tier", 0))
		if other_tier < tier:
			other["state"] = "terminal"
			other["terminal"] = "superseded"
			other["superseded_by"] = String(run.get("id", ""))
		elif other_tier > tier:
			run["state"] = "terminal"
			run["terminal"] = "superseded"
			run["superseded_by"] = String(other.get("id", ""))
			return
	run["state"] = "armed"


## Milestone «открытие action-scope»: G-01 по старому контракту (возвращает его run_id
## для legacy_view) плюс A3-вахты по path[0]/seed. Вахта без продолжения истечёт молча.
func open_action_run(action_id: String, frame_id: String, attacker: String,
		defender: String, anchor: Dictionary, opener_play: Dictionary) -> String:
	var scope := {"g01": "", "a3": [], "attacker": attacker, "defender": defender,
		"frame_id": frame_id, "relations": []}
	scopes[action_id] = scope
	if not anchor.is_empty():
		var route := Grammar.route(anchor.get("card", {}), opener_play)
		if not route.is_empty():
			_run_serial += 1
			var run_id := "run_%d" % _run_serial
			runs[run_id] = {
				"id": run_id,
				"pattern_id": String(P_G01_GUARD.id),
				"pattern_version": int(P_G01_GUARD.version),
				"scope": {"kind": "action", "id": action_id},
				"roles": {"A": attacker, "B": defender},
				"slots": {"$open": String(opener_play.get("play_id", "")), "$close": ""},
				"anchor_thesis": String(anchor.get("thesis_id", "")),
				"closer_thesis": "",
				"closer_step": -1,
				"frame_id": frame_id,
				"route": route,
				"armed_once": false,
				"superseded_by": "",
				"state": "link",       # link | armed | terminal
				"terminal": "",        # confirmed | break | expired | superseded
			}
			scope.g01 = run_id
	for raw_pattern in (A3_CATALOG + extra_a3_catalog):
		var pattern: Dictionary = raw_pattern
		var path: Array = pattern.get("path", [])
		if not _card_matches(opener_play, (path[0] as Dictionary).get("card", {})):
			continue
		if pattern.has("seed"):
			# Board-atom $setup: exact верхний тезис в момент объявления. Требуемая схема
			# читается со снапшота якоря; техтезис/не та схема — вахта не открывается.
			var seed_spec: Dictionary = (pattern.seed as Dictionary).get("$setup", {})
			var anchor_card: Dictionary = anchor.get("card", {})
			if anchor_card.is_empty() or not _card_matches(anchor_card,
					seed_spec.get("card", {})):
				continue
		_run_serial += 1
		var a3_id := "run_%d" % _run_serial
		runs[a3_id] = {
			"id": a3_id,
			"pattern_id": String(pattern.id),
			"pattern_version": int(pattern.version),
			"scope": {"kind": "action", "id": action_id},
			"roles": {"A": attacker, "B": defender},
			"slots": {"$ask": String(opener_play.get("play_id", "")),
				"$reply": "", "$press": ""},
			"bindings": {},
			"reply_thesis": "",
			"frame_id": frame_id,
			"structural_complete": false,
			# Паттерн без content-атомов не ждёт add_content_relation — вооружается чисто структурно.
			"content_ok": _content_atoms(pattern).is_empty(),
			"armed_once": false,
			"superseded_by": "",
			"state": "watching",   # watching | link | armed | terminal
			"terminal": "",        # confirmed | break | expired | unresolved | superseded
		}
		(scope.a3 as Array).append(a3_id)
	return String(scope.g01)


## Milestone «защитный ответ»: G-01 вооружает только ребро responds_to на exact опенер
## (факт-эквивалент старого «t_added == 1»); A3-окно жёсткое — $reply это ровно step 1
## (§2 топологий: matcher читает только два стартовых окна, T₃+ новых claims не создаёт).
func on_response(action_id: String, play: Dictionary, new_relations: Array,
		anchor_card: Dictionary, opener_card: Dictionary) -> void:
	var scope: Dictionary = scopes.get(action_id, {})
	if scope.is_empty():
		return
	var responds_to_id := ""
	var materialized := ""
	for raw in new_relations:
		var rel: Dictionary = raw
		var to: Dictionary = rel.get("to", {})
		match String(rel.get("type", "")):
			"responds_to":
				responds_to_id = String(to.get("id", ""))
			"materializes_as":
				materialized = String(to.get("id", ""))
	var g01: Dictionary = runs.get(String(scope.get("g01", "")), {})
	if not g01.is_empty() and String(g01.state) == "link" and \
			responds_to_id == String((g01.slots as Dictionary).get("$open", "")) and \
			Grammar.answers(anchor_card, opener_card, play):
		g01.slots["$close"] = String(play.get("play_id", ""))
		g01["closer_step"] = int(play.get("step", -1))
		g01["closer_thesis"] = materialized
		_arm_run(g01, scope)
	if materialized != "":
		record_thesis_origin(action_id, String(play.get("play_id", "")),
			String(play.get("actor", "")), String(scope.get("frame_id", "")), materialized)
	if int(play.get("step", -1)) != 1:
		return
	for a3_id in scope.get("a3", []):
		var run: Dictionary = runs[a3_id]
		if String(run.state) != "watching":
			continue
		var pattern := _pattern(String(run.pattern_id))
		var reply_spec: Dictionary = (pattern.path[1] as Dictionary).get("card", {})
		if not _card_matches(play, reply_spec):
			continue
		if responds_to_id != String((run.slots as Dictionary).get("$ask", "")):
			continue
		run.slots["$reply"] = String(play.get("play_id", ""))
		run["reply_thesis"] = materialized
		run["state"] = "link"
		# Двухзвенный path (TRAP) структурно полон уже здесь; ARMED ждёт content-ребра.
		run["structural_complete"] = (pattern.path as Array).size() == 2
		if bool(run.structural_complete) and bool(run.content_ok):
			_arm_run(run, scope)


## Milestone «press»: только exact step 2 может закрыть трёхзвенный path (RTR).
## Структурная полнота ≠ ARMED: без content-ребра кандидат уйдёт в UNRESOLVED.
func on_press(action_id: String, play: Dictionary, new_relations: Array) -> void:
	var scope: Dictionary = scopes.get(action_id, {})
	if scope.is_empty() or int(play.get("step", -1)) != 2:
		return
	var targeted_thesis := ""
	for raw in new_relations:
		var rel: Dictionary = raw
		if String(rel.get("type", "")) == "targets":
			targeted_thesis = String((rel.get("to", {}) as Dictionary).get("id", ""))
	# TRT-TRAP остаётся двухзвенным recipe, но settlement может требовать доказательство
	# exact press по semantic basis. Первый press лишь связывается как proof-slot и не
	# открывает нового скользящего окна.
	for a3_id in scope.get("a3", []):
		var trap_run: Dictionary = runs[a3_id]
		var trap_pattern := _pattern(String(trap_run.pattern_id))
		if String(trap_run.get("state", "")) == "terminal" or \
				String(trap_pattern.get("topology", "")) != "trt_trap" or \
				(trap_pattern.get("path", []) as Array).size() != 2:
			continue
		if targeted_thesis == String(trap_run.get("reply_thesis", "")):
			trap_run.slots["$press"] = String(play.get("play_id", ""))
	for a3_id in scope.get("a3", []):
		var run: Dictionary = runs[a3_id]
		var pattern := _pattern(String(run.pattern_id))
		if String(run.state) != "link" or (pattern.path as Array).size() != 3:
			continue
		if not _card_matches(play, (pattern.path[2] as Dictionary).get("card", {})):
			continue
		if targeted_thesis == "" or targeted_thesis != String(run.get("reply_thesis", "")):
			continue
		run.slots["$press"] = String(play.get("play_id", ""))
		run["structural_complete"] = true
		if bool(run.content_ok):
			_arm_run(run, scope)


func _content_relation_matches(run: Dictionary, atom: Dictionary,
		rel: Dictionary) -> bool:
	if String(rel.get("type", "")) != String(atom.get("rel", "")):
		return false
	var from: Dictionary = rel.get("from", {})
	var from_pid := String((run.slots as Dictionary).get(String(atom.get("from", "")), ""))
	if from_pid == "" or String(from.get("kind", "")) != "play" or \
			String(from.get("id", "")) != from_pid:
		return false
	var to: Dictionary = rel.get("to", {})
	if atom.has("to_kind") and String(to.get("kind", "")) != String(atom.to_kind):
		return false
	if atom.has("to_slot"):
		var to_pid := String((run.slots as Dictionary).get(String(atom.to_slot), ""))
		if String(to.get("kind", "")) != "play" or String(to.get("id", "")) != to_pid:
			return false
	var wanted: Dictionary = atom.get("attrs", {})
	var given: Dictionary = rel.get("attrs", {})
	for key in wanted:
		if given.get(key) != wanted[key]:
			return false
	return true


func _refresh_content_match(run: Dictionary, scope: Dictionary) -> bool:
	var atoms := _content_atoms(_pattern(String(run.pattern_id)))
	if atoms.is_empty():
		return true
	for raw_atom in atoms:
		var atom: Dictionary = raw_atom
		var found := false
		for raw_rel in scope.get("relations", []):
			var rel: Dictionary = raw_rel
			if not _content_relation_matches(run, atom, rel):
				continue
			found = true
			if atom.has("bind_to"):
				var to: Dictionary = rel.get("to", {})
				(run.get("bindings", {}) as Dictionary)[String(atom.bind_to)] = \
					String(to.get("id", ""))
			break
		if not found:
			return false
	return true


## Шов §7 (вариант 2): content-RelationFact от controller'а, строго после физического
## play и до settlement. Факты сохраняются в scope-proof (включая exact target
## subclaim), а все content-atoms recipe проверяются декларативно.
func on_content_relation(action_id: String, rel: Dictionary) -> void:
	var scope: Dictionary = scopes.get(action_id, {})
	if scope.is_empty():
		return
	(scope.get("relations", []) as Array).append(rel)
	for a3_id in scope.get("a3", []):
		var run: Dictionary = runs[a3_id]
		if String(run.state) == "terminal" or bool(run.content_ok):
			continue
		if not _refresh_content_match(run, scope):
			continue
		run["content_ok"] = true
		if bool(run.get("structural_complete", false)):
			_arm_run(run, scope)


## Settlement всего action-scope (§5, без payoff): G-01 по прежнему контракту; armed A3
## проверяет claim.confirm по outcome'ам sequence; структурно полный кандидат без
## content-ребра — UNRESOLVED (не BREAK: неизвестность не наказывается), недостроенный —
## expired. Терминалы single-assignment.
func settle_action(action_id: String, attacker_won: bool, sequence: Array,
		frame_thesis_ids: Array) -> void:
	var scope: Dictionary = scopes.get(action_id, {})
	if scope.is_empty():
		return
	var g01: Dictionary = runs.get(String(scope.get("g01", "")), {})
	if not g01.is_empty() and String(g01.state) != "terminal":
		if String(g01.state) != "armed":
			g01["state"] = "terminal"
			g01["terminal"] = "expired"
		else:
			var confirmed := true
			for raw in (P_G01_GUARD.claim as Dictionary).get("confirm", []):
				var atom: Dictionary = raw
				match String(atom.get("kind", "")):
					"winner":
						confirmed = confirmed and \
							(attacker_won == (String(atom.get("role", "")) == "A"))
					"outcome":
						var step := int(g01.get("closer_step", -1))
						confirmed = confirmed and step >= 0 and step < sequence.size() and \
							String((sequence[step] as Dictionary).get("result", "")) == \
							String(atom.get("result", ""))
					"board_contains":
						confirmed = confirmed and \
							frame_thesis_ids.has(String(g01.get("closer_thesis", "")))
			g01["state"] = "terminal"
			g01["terminal"] = "confirmed" if confirmed else "break"
	var by_pid := {}
	for raw in sequence:
		by_pid[String((raw as Dictionary).get("play_id", ""))] = raw
	for a3_id in scope.get("a3", []):
		var run: Dictionary = runs[a3_id]
		if String(run.state) == "terminal":
			continue
		var terminal := "expired"
		if String(run.state) == "armed":
			terminal = "confirmed" if _a3_confirm_ok(run, attacker_won, by_pid,
				frame_thesis_ids, scope.get("relations", [])) else "break"
		elif bool(run.get("structural_complete", false)):
			terminal = "unresolved"
		run["state"] = "terminal"
		run["terminal"] = terminal
	_shadow_migrated_legacy_guard(scope)
	_arbitrate_action(scope)


func _binding_of(run: Dictionary, bind: String) -> String:
	match bind:
		"$reply_thesis":
			return String(run.get("reply_thesis", ""))
		"$closer_thesis":
			return String(run.get("closer_thesis", ""))
	return String((run.get("bindings", {}) as Dictionary).get(bind, ""))


func _relation_confirmed(run: Dictionary, atom: Dictionary, relations: Array) -> bool:
	var from_pid := String((run.get("slots", {}) as Dictionary).get(
		String(atom.get("from", "")), ""))
	var to_id := _binding_of(run, String(atom.get("to_bind", "")))
	if from_pid == "" or to_id == "":
		return false
	for raw in relations:
		var rel: Dictionary = raw
		var from: Dictionary = rel.get("from", {})
		var to: Dictionary = rel.get("to", {})
		if String(rel.get("type", "")) == String(atom.get("rel", "")) and \
				String(from.get("kind", "")) == "play" and \
				String(from.get("id", "")) == from_pid and \
				String(to.get("id", "")) == to_id and \
				(not atom.has("provenance") or String(rel.get("provenance", "")) == \
					String(atom.get("provenance", ""))):
			return true
	return false


func _a3_confirm_ok(run: Dictionary, attacker_won: bool, by_pid: Dictionary,
		frame_thesis_ids: Array, relations: Array) -> bool:
	var pattern := _pattern(String(run.pattern_id))
	for raw in (pattern.claim as Dictionary).get("confirm", []):
		var atom: Dictionary = raw
		match String(atom.get("kind", "")):
			"winner":
				if attacker_won != (String(atom.get("role", "")) == "A"):
					return false
			"outcome_in":
				var outcome := _slot_outcome(run, atom, by_pid)
				if not String(outcome.get("result", "")) in (atom.get("results", []) as Array):
					return false
			"effect_in":
				var outcome := _slot_outcome(run, atom, by_pid)
				if not String(outcome.get("effect", "")) in (atom.get("effects", []) as Array):
					return false
			"affected_is":
				var outcome := _slot_outcome(run, atom, by_pid)
				var affected: Dictionary = outcome.get("affected", {})
				if String(affected.get("id", "")) != _binding_of(run,
						String(atom.get("bind", ""))):
					return false
			"board_contains":
				if not frame_thesis_ids.has(_binding_of(run, String(atom.get("bind", "")))):
					return false
			"relation":
				if not _relation_confirmed(run, atom, relations):
					return false
	return true


## После confirm выбирается максимум один run на payoff-channel. Это пока только
## арбитражный факт: payoff остаётся пустым до следующего этапа.
func _arbitrate_action(scope: Dictionary) -> void:
	var winners := {}
	for run_id in _scope_run_ids(scope):
		var run: Dictionary = runs.get(run_id, {})
		if String(run.get("terminal", "")) != "confirmed":
			continue
		var arb := _arbitration_of(run)
		var channel := String(arb.get("channel", ""))
		var incumbent: Dictionary = winners.get(channel, {})
		if incumbent.is_empty():
			winners[channel] = run
			continue
		var incumbent_arb := _arbitration_of(incumbent)
		var outranks := int(arb.get("tier", 0)) > int(incumbent_arb.get("tier", 0)) or \
			(int(arb.get("tier", 0)) == int(incumbent_arb.get("tier", 0)) and \
			int(arb.get("priority", 0)) > int(incumbent_arb.get("priority", 0)))
		if outranks:
			incumbent["terminal"] = "superseded"
			incumbent["superseded_by"] = String(run.get("id", ""))
			winners[channel] = run
		else:
			run["terminal"] = "superseded"
			run["superseded_by"] = String(incumbent.get("id", ""))
	for channel in winners:
		(winners[channel] as Dictionary)["arbitration_winner"] = true


## На мигрированной TRT-тройке generic G-01 — только переходная UI-проекция.
## Семантический GUARD получает его legacy route/closer; если валиден только TRAP или
## данных не хватает, structural run не может самовольно подтвердиться.
func _shadow_migrated_legacy_guard(scope: Dictionary) -> void:
	var g01: Dictionary = runs.get(String(scope.get("g01", "")), {})
	if g01.is_empty() or String(g01.get("closer_thesis", "")) == "":
		return
	var open_pid := String((g01.get("slots", {}) as Dictionary).get("$open", ""))
	var close_pid := String((g01.get("slots", {}) as Dictionary).get("$close", ""))
	var migrated := false
	var semantic_guard := {}
	for a3_id in scope.get("a3", []):
		var run: Dictionary = runs.get(a3_id, {})
		var pattern := _pattern(String(run.get("pattern_id", "")))
		if not bool(run.get("structural_complete", false)) or \
				String((run.get("slots", {}) as Dictionary).get("$ask", "")) != open_pid or \
				String((run.get("slots", {}) as Dictionary).get("$reply", "")) != close_pid or \
				not String(pattern.get("topology", "")) in ["trt_guard", "trt_trap"]:
			continue
		migrated = true
		if String(pattern.get("topology", "")) == "trt_guard":
			semantic_guard = run
	if not migrated:
		return
	g01["shadowed"] = true
	if not semantic_guard.is_empty() and String(semantic_guard.get("terminal", "")) in \
			["confirmed", "break", "superseded"]:
		g01["state"] = "terminal"
		g01["terminal"] = "superseded"
		g01["superseded_by"] = String(semantic_guard.get("id", ""))
	else:
		g01["state"] = "terminal"
		g01["terminal"] = "unresolved"


func _slot_outcome(run: Dictionary, atom: Dictionary, by_pid: Dictionary) -> Dictionary:
	var pid := String((run.slots as Dictionary).get(String(atom.get("slot", "")), ""))
	return (by_pid.get(pid, {}) as Dictionary).get("outcome", {})


## Единственная постоянная память, нужная frame-scope: какой exact play материализовал T.
## Нахождение тезиса и порядок рамки здесь не хранятся — их даёт board_stable snapshot.
func record_thesis_origin(action_id: String, play_id: String, actor: String,
		frame_id: String, thesis_id: String) -> void:
	if thesis_id == "" or thesis_origins.has(thesis_id):
		return
	thesis_origins[thesis_id] = {"action_id": action_id, "play_id": play_id,
		"actor": actor, "frame_id": frame_id}


func _frame_card_matches(card: Dictionary, spec: Dictionary, pattern_id: String) -> bool:
	if not _card_matches(card, spec):
		return false
	var rhetoric: Dictionary = card.get("rhetoric", {})
	return String(rhetoric.get("frame_recipe_id", "")) == pattern_id


## Stable-board pass R4. frames — authoritative snapshots {frame_id, owner, thesis_stack}.
## Проверяется только целый новый top-suffix; хотя бы один его T обязан родиться в
## closing action, поэтому снятие/захват не разоблачает старую тройку как новую.
func board_stable(action_id: String, frames: Array) -> void:
	for raw_frame in frames:
		var frame: Dictionary = raw_frame
		var frame_id := String(frame.get("frame_id", ""))
		var owner := String(frame.get("owner", ""))
		var stack: Array = frame.get("thesis_stack", [])
		if frame_id == "" or stack.size() < 3:
			continue
		for raw_pattern in FRAME_CATALOG:
			var pattern: Dictionary = raw_pattern
			var completion_key := "%s::%s" % [frame_id, String(pattern.id)]
			if completions.has(completion_key):
				continue
			var path: Array = pattern.get("path", [])
			var suffix: Array = stack.slice(stack.size() - path.size(), stack.size())
			if suffix.size() != path.size():
				continue
			var matched := true
			var added_now := false
			var slots := {}
			var entities := {}
			for i in path.size():
				var atom: Dictionary = path[i]
				var thesis: Dictionary = suffix[i]
				var thesis_id := String(thesis.get("thesis_id", ""))
				var origin: Dictionary = thesis_origins.get(thesis_id, {})
				if not _frame_card_matches(thesis, atom.get("card", {}), String(pattern.id)) or \
						origin.is_empty() or String(origin.get("actor", "")) != owner or \
						String(origin.get("frame_id", "")) != frame_id:
					matched = false
					break
				var slot := String(atom.get("slot", ""))
				slots[slot] = String(origin.get("play_id", ""))
				entities[slot] = thesis_id
				added_now = added_now or String(origin.get("action_id", "")) == action_id
			if not matched or not added_now:
				continue
			_run_serial += 1
			var run_id := "run_%d" % _run_serial
			runs[run_id] = {"id": run_id, "pattern_id": String(pattern.id),
				"pattern_version": int(pattern.version),
				"scope": {"kind": "frame", "id": frame_id}, "roles": {"A": owner},
				"slots": slots, "entities": entities, "closing_action_id": action_id,
				"armed_once": true, "arbitration_winner": true,
				"state": "terminal", "terminal": "confirmed", "superseded_by": ""}
			completions[completion_key] = run_id
			if not _events_by_action.has(action_id):
				_events_by_action[action_id] = []
			(_events_by_action[action_id] as Array).append(run_id)


## combo_events[] — единственное, что уходит наружу ядра (§7): по одному событию на run
## scope, читаемая ставка (владелец/имя/топология), arbitration и терминал.
func _event_for_run(run: Dictionary, contested: bool = false) -> Dictionary:
	var pattern := _pattern(String(run.pattern_id))
	var combo_name := String(pattern.get("combo_name", ""))
	if combo_name == "":
		combo_name = String((run.get("route", {}) as Dictionary).get("combo_name", ""))
	var arb := _arbitration_of(run)
	return {
		"run_id": String(run.id),
		"pattern_id": String(run.pattern_id),
		"family": String(pattern.get("family", "")),
		"topology": String(pattern.get("topology", "")),
		"combo_name": combo_name,
		"owner": _owner_of(run),
		"terminal": String(run.get("terminal", "")),
		"slots": (run.get("slots", {}) as Dictionary).duplicate(true),
		"bindings": (run.get("bindings", {}) as Dictionary).duplicate(true),
		"arbitration": {"channel": String(arb.get("channel", "")),
			"tier": int(arb.get("tier", 0)), "priority": int(arb.get("priority", 0)),
			"winner": bool(run.get("arbitration_winner", false))},
		"contested": contested,
		"shadowed": bool(run.get("shadowed", false)),
		"superseded_by": String(run.get("superseded_by", "")),
		"payoff": "",
	}


func events_for_action(action_id: String) -> Array:
	var scope: Dictionary = scopes.get(action_id, {})
	var out: Array = []
	var ordered: Array = []
	if not scope.is_empty():
		ordered = _scope_run_ids(scope)
	ordered.append_array(_events_by_action.get(action_id, []))
	for run_id in ordered:
		var run: Dictionary = runs.get(run_id, {})
		if run.is_empty():
			continue
		var contested := false
		if not scope.is_empty() and bool(run.get("armed_once", false)) and \
				not bool(run.get("shadowed", false)):
			var channel := String(_arbitration_of(run).get("channel", ""))
			for other_id in _scope_run_ids(scope):
				var other: Dictionary = runs.get(other_id, {})
				if String(other.get("id", "")) != String(run.get("id", "")) and \
						bool(other.get("armed_once", false)) and not bool(other.get("shadowed", false)) and \
						_owner_of(other) != _owner_of(run) and \
						String(_arbitration_of(other).get("channel", "")) == channel:
					contested = true
					break
		out.append(_event_for_run(run, contested))
	return out


## Проекция легаси-контракта (только G-01). Маппинг терминала на прежние состояния:
## expired истекает из LINK, confirmed/break — из ARMED; до settlement state напрямую.
func legacy_view(run_id: String) -> Dictionary:
	var run: Dictionary = runs.get(run_id, {})
	if run.is_empty():
		return {"combo_route": {}, "combo_state": "none", "combo_owner": "",
			"closer_step": -1, "closer_thesis_id": "", "combo_result": "none"}
	# Семантически точный run может выиграть arbitration у legacy G-01. Проекция сохраняет
	# прежний route/closer, но читает терминал победителя, поэтому UI/AI не видят миграцию.
	var resolved := run
	var seen := {}
	while String(resolved.get("terminal", "")) == "superseded" and \
			String(resolved.get("superseded_by", "")) != "" and not seen.has(String(resolved.id)):
		seen[String(resolved.id)] = true
		resolved = runs.get(String(resolved.superseded_by), resolved)
	var terminal := String(resolved.get("terminal", ""))
	var armed: bool = bool(run.get("armed_once", false)) or String(run.state) == "armed" or \
		terminal in ["confirmed", "break"]
	return {
		"combo_route": (run.get("route", {}) as Dictionary).duplicate(true),
		"combo_state": "armed" if armed else "link",
		"combo_owner": String((run.roles as Dictionary).get("B", "")) if armed else "",
		"closer_step": int(run.get("closer_step", -1)) if armed else -1,
		"closer_thesis_id": String(run.get("closer_thesis", "")) if armed else "",
		"combo_result": terminal if terminal in ["confirmed", "break"] else "none",
	}


## Копия run'а для телеметрии (info.combo_run) — читается smoke и combo_events.
func run_view(run_id: String) -> Dictionary:
	return (runs.get(run_id, {}) as Dictionary).duplicate(true)
