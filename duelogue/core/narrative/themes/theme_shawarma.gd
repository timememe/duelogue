extends RefCounted

## DUELOGUE — тема: «Шаурма: сырный лаваш vs обычный» (модель ОСЕЙ, v0.3).
## Намеренно оставлена на v0.3: проверяет fallback без takes/supports в Theme v0.4-движке.
## Полюса универсальны: contra/pro — просто две стороны; смысл несут label'ы.
##   contra = за обычный лаваш, pro = за сырный лаваш.
## FILL-SAFE требования к полям:
##   headline.text / take = ЦЕЛАЯ фраза, наст. время, строчная, без точки в конце.
##   headline.preferred_axes = мягкий семантический биас доводов этой рамки.
##   motif = именительный нос. (вставляется только в безопасную позицию; не склоняется).
##   v0.3: tag = именительный, 1–2 слова (референция); appeal = logos|pathos|ethos (биас).

static func data() -> Dictionary:
	return {
		"id": "shawarma",
		"topic": "Шаурма: сырный лаваш или обычный",
		"stances": {
			"contra": {
				"label": "за обычный лаваш",
				"headlines": [
					{"id": "contra_plain", "text": "шаурма живёт в обычном лаваше", "preferred_axes": ["tradition", "identity"]},
					{"id": "contra_marketing", "text": "сырный лаваш — это маркетинг", "preferred_axes": ["price", "identity"]},
					{"id": "contra_classic", "text": "классику не надо «улучшать»", "preferred_axes": ["tradition", "identity"]},
					{"id": "contra_honest", "text": "обычный лаваш честнее", "preferred_axes": ["price", "tradition"]},
					{"id": "contra_extra", "text": "сыр тут лишний", "preferred_axes": ["taste", "health"]},
					{"id": "contra_showoff", "text": "не порть шаурму понтами", "preferred_axes": ["price", "identity"]},
				],
			},
			"pro": {
				"label": "за сырный лаваш",
				"headlines": [
					{"id": "pro_level", "text": "сырный лаваш выводит шаурму на новый уровень", "preferred_axes": ["taste", "texture"]},
					{"id": "pro_genius", "text": "сыр в тесте — это гениально", "preferred_axes": ["taste", "texture"]},
					{"id": "pro_boring", "text": "обычный лаваш скучен", "preferred_axes": ["taste", "identity"]},
					{"id": "pro_care", "text": "сырный — это забота о вкусе", "preferred_axes": ["taste", "health"]},
					{"id": "pro_future", "text": "за сырным лавашом будущее", "preferred_axes": ["tradition", "identity"]},
					{"id": "pro_no_return", "text": "попробуешь сырный — не вернёшься", "preferred_axes": ["taste", "texture"]},
				],
			},
		},
		"axes": [
			{
				"id": "taste",
				"tag": "вкус",
				"appeal": "logos",
				"contra": "сыр забивает вкус мяса и соуса",
				"pro": "расплавленный сыр обогащает каждый кусок",
				"motifs": ["мясо", "чесночный соус", "вкусовой баланс"],
			},
			{
				"id": "price",
				"tag": "ценник",
				"appeal": "logos",
				"contra": "сырный — это просто дороже за те же продукты",
				"pro": "доплата за сыр честно того стоит",
				"motifs": ["ценник", "лишние сто рублей", "кошелёк"],
			},
			{
				"id": "texture",
				"tag": "текстура",
				"appeal": "logos",
				"contra": "сырный лаваш размокает и расползается",
				"pro": "сырная корочка держит форму куда лучше",
				"motifs": ["соус", "края лаваша", "первый укус"],
			},
			{
				"id": "tradition",
				"tag": "классика",
				"appeal": "ethos",
				"contra": "настоящая шаурма всегда была на обычном лаваше",
				"pro": "уличная еда обязана развиваться",
				"motifs": ["ларёк у вокзала", "старый рецепт", "уличная классика"],
			},
			{
				"id": "health",
				"tag": "здоровье",
				"appeal": "pathos",
				"contra": "сыр делает шаурму неподъёмно жирной",
				"pro": "немного сыра погоды не делает",
				"motifs": ["лишние калории", "тяжесть в желудке", "режим"],
			},
			{
				"id": "identity",
				"tag": "жанр",
				"appeal": "ethos",
				"contra": "с сыром это уже не шаурма, а что-то другое",
				"pro": "шаурма от обёртки шаурмой быть не перестаёт",
				"motifs": ["чистота рецепта", "границы жанра", "снобы"],
			},
		],
		"shared_motifs": ["здравый смысл", "любой нормальный человек", "вечный спор у ларька"],
		"voices": {"contra": "брюзга-традиционалист", "pro": "гедонист-новатор"},
	}
