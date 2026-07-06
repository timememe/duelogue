# DUELOGUE — промпты генерации поз по стейтам реакций (контракт §16)

**Назначение:** image-gen / video-gen промпты под **наш** словарь стейтов персонажа
(`narrative_engine.md` §16, `character_core.gd` STATE_TEX) — 9 стейтов + idle.
База — [ace_attorney_state_prompts.md](ace_attorney_state_prompts.md), но с двумя правками:

1. **Эмоция гипертрофирована.** Не «лёгкое напряжение», а театр до карикатуры: эмоция должна
   читаться С СИЛУЭТА, без лица. Сценический актёр, играющий на последний ряд.
2. **Анти-статик директива.** Проблема: с безэмоциональной заготовкой-референсом нейронка
   по умолчанию НЕ меняет позу. Поэтому в каждый промпт вшита инструкция: референс задаёт
   только личность/костюм/стиль рендера, а поза — с чистого листа, всё тело пересобирается
   под эмоцию. При этом **конкретные позы намеренно НЕ прописаны** (никаких «указывает
   пальцем» / «бьёт по столу») — чтобы не цитировать Ace Attorney и оставить нейронке
   свободу мизансцены: промпт задаёт ЭНЕРГИЮ и НАПРАВЛЕНИЕ тела, не анатомию.

**Стилистика:** в конце каждого промпта вшит стилистический хвост `visual novel courtroom
drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast
mood lighting`. Если понадобится сменить стиль — искать этот хвост и заменить одной операцией
find-replace во всех промптах файла.

**Технический каркас (не стилистика, не менять):** белый фон под вырезание спрайта +
поясной кадр (лейаут reaction_scene) + анти-статик директива — уже вшиты в промпты.

---

## 0. idle — нейтраль

**В игре:** дефолт; пас без крена зала; фолбэк для стейтов без арта.

**Image prompt:**
> A debater between exchanges — composed, self-assured neutral presence, energy coiled but at
> rest, quietly certain they are right. Even this calm is STAGED: poised like a stage actor
> holding the audience's attention without saying a word, presence turned up louder than real
> life. The character reference defines identity, outfit and rendering style only — ignore its
> pose completely and restage the entire body from scratch for this mood: new stance, new
> silhouette, theatrical full-body acting, the emotion readable from the silhouette alone.
> Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> Subtle idle loop — slow confident breathing, a light sway of weight, an occasional unhurried
> blink; coiled stillness, like a held note before the orchestra starts. Full-body acting, not
> just facial animation — the posture itself performs the calm. Character faces right toward an
> unseen opponent just off-screen (never left, never the audience). Plain solid white background,
> no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 1. declare — заявляю

**В игре:** Установка (новая рамка), нейтральный тезис; открытие партии.

**Image prompt:**
> Grand proclamation energy — announcing a position to the entire hall like an opening night
> at the opera. The body opens up and claims maximum space, chest lifted, weight rising,
> radiating pompous unshakable certainty; a living monument to being right, theatrical to the
> edge of caricature. The character reference defines identity, outfit and rendering style
> only — ignore its pose completely and restage the entire body from scratch for this emotion:
> new expansive stance, new silhouette, full-body acting pushed far past realism, the emotion
> readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white
> background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A rising proclamation — the figure swells upward and outward into a grand held pose, then
> micro-sways with self-importance, savoring its own words. Motion is broad, ceremonial,
> unhurried; playing to the last row of the hall. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience).
> Plain solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 2. swagger — кураж

**В игре:** тезис или пас, когда зал кренится ЗА говорящего (фаворит вальяжничает).

**Image prompt:**
> Insufferable smugness dialed to caricature — the lazy, luxurious ease of someone who has
> already won and wants the whole room to feel it. Loose and unhurried, draped in
> self-satisfaction, mocking superiority so thick it fills the air; a peacock admiring its own
> reflection while the opponent drowns. The character reference defines identity, outfit and
> rendering style only — ignore its pose completely and restage the entire body from scratch
> for this emotion: new relaxed dominant silhouette, theatrical full-body acting far past
> realism, the smugness readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience),
> plain solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A slow, luxurious settle into satisfied ease — unhurried weight shifts, tiny self-delighted
> bounces, the rhythm of someone savoring victory in advance. No urgency anywhere in the body;
> mockery radiates from sheer relaxation. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain
> solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 3. panic — паника

**В игре:** redeploy-страховка (рамки рухнули, спасается запасной Установкой); тезис/пас,
когда зал сильно ПРОТИВ говорящего.

**Image prompt:**
> Full-body alarm, caricature-level panic — composure collapsing in real time. The figure
> scrambles: weight thrown off balance, energy jerking in three directions at once, cold sweat
> flying off in drops, the cornered look of someone whose entire plan just caught fire behind
> them. Comic desperation pushed to the limit. The character reference defines identity,
> outfit and rendering style only — ignore its pose completely and restage the entire body
> from scratch for this emotion: unstable chaotic silhouette, theatrical full-body acting far
> past realism, the panic readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience),
> plain solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> Jittery multi-directional scramble — trembling, quick darting glances, weight never settling,
> hands and shoulders in restless disarray; the rhythm of a mind racing through bad options.
> Fast, unstable, no rest anywhere. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain solid
> white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 4. hold — держу удар

**В игре:** защита тезисом в клинче (обычная, без висящего вопроса).

**Image prompt:**
> Immovable defensive resolve — braced like a wall against a storm. Weight dropped low and
> planted, jaw set, every line of the body committed to not giving a single step; stubborn,
> heavy, monumental effort made visible and exaggerated, holding a door shut against a flood.
> The character reference defines identity, outfit and rendering style only — ignore its pose
> completely and restage the entire body from scratch for this emotion: grounded fortress
> silhouette, theatrical full-body acting far past realism, the stubbornness readable from the
> silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white background, no scenery,
> visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A tension hum — the planted stance vibrates with effort, small resistant jolts as if
> absorbing invisible blows, breath heavy and controlled; the motion of enduring, not moving.
> Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain solid white background, no scenery,
> visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 5. evade — юлю

**В игре:** защита при ВИСЯЩЕЙ зацепке — критический вопрос прозвучал, ответа нет,
приходится съезжать («Вопрос слышал. Но по сути…»).

**Image prompt:**
> Squirming evasion — caught in the spotlight and visibly wriggling out of it. The body twists
> away and shrinks, a too-wide unconvincing grin, sweat beading, eyes darting anywhere but
> forward; slippery cornered charm stretched to its comic breaking point, a person physically
> sliding out from under a question. The character reference defines identity, outfit and
> rendering style only — ignore its pose completely and restage the entire body from scratch
> for this emotion: twisting shrinking silhouette, theatrical full-body acting far past
> realism, the evasion readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain
> solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> Shifty weight transfers and twisting micro-retreats — the body keeps angling away, nervous
> glances flick sideways, a bead of sweat wiped mid-motion; wriggling, slippery rhythm, never
> facing the question head-on. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain solid white
> background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 6. attack — атакую

**В игре:** Разбор MISS — генерическая атака на чужой довод (без попадания в зацепку).

**Image prompt:**
> A verbal strike made flesh — the whole body lunges into the accusation, energy shooting
> forward at the unseen opponent like a fencing thrust. Sharp, explosive, confrontational; the
> silhouette itself an arrow loosed across the stage, aggression compressed into one decisive
> forward beat. The character reference defines identity, outfit and rendering style only —
> ignore its pose completely and restage the entire body from scratch for this emotion:
> forward-driving attacking silhouette, theatrical full-body acting far past realism, the
> aggression readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid
> white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A sharp wind-up and a hard forward snap — the strike lands and the body holds its aggressive
> line, tension ringing like a struck blade; short, punchy, high-impact, then unwavering
> hostile stillness. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain solid white
> background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 7. gotcha — подловил

**В игре:** HIT зацепки (атака попала в форму чужой схемы: «А цифры — откуда?») и Кража
(присвоение чужого довода: «Спасибо — забираю!»).

**Image prompt:**
> Predatory triumph — the trap has just snapped shut and the prey knows it. Leaning into the
> kill with a razor-thin grin, delight and menace in equal measure, savoring the moment with
> theatrical villainous glee; the cat with the canary, turned up to eleven. The character
> reference defines identity, outfit and rendering style only — ignore its pose completely and
> restage the entire body from scratch for this emotion: looming predatory silhouette,
> theatrical full-body acting far past realism, the gloating readable from the silhouette
> alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A slow lean-in as the grin widens — a savoring pause, a quiet chuckle rippling through the
> shoulders, the unhurried confidence of a hunter standing over a sprung trap. Tension is all
> pleasure, no urgency. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain solid white
> background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 8. burst — вспышка

**В игре:** панч-регистр — третий+ удар ралли, аффект-выкрик («Пруфы! Пруфы где?!»,
«Сколько можно повторять?!»).

**Image prompt:**
> An emotional detonation — the loudest single moment of the entire debate, a shout that bends
> the air around it. The whole figure erupts: maximum energy, maximum volume, a full-body
> exclamation mark; explosive, jarring, impossible to ignore, composure blown off like a lid.
> The character reference defines identity, outfit and rendering style only — ignore its pose
> completely and restage the entire body from scratch for this emotion: erupting explosive
> silhouette, theatrical full-body acting far past realism, the shout readable from the
> silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white background, no scenery,
> visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A violent eruption — fast wind-up, hard release, a shockwave shudder through the whole
> frame, then the peak held ringing in the air like a thunderclap that refuses to fade.
> Abrupt, deafening, total commitment. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain
> solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## 9. stagger — пошатнулся

**В игре:** событийный (impact): его довод снят (интенсивность 0.65) или рамка рухнула (1.0);
играет со спидлайнами на фоне.

**Image prompt:**
> Struck by an invisible freight train of an argument — reeling, the world tilting, composure
> shattering like dropped glass. The body recoils hard and hangs off balance, eyes wide with
> raw disbelief, one step from falling over; a manga impact panel of pure shock, damage made
> theatrical. The character reference defines identity, outfit and rendering style only —
> ignore its pose completely and restage the entire body from scratch for this emotion:
> recoiling off-balance silhouette, theatrical full-body acting far past realism, the shock
> readable from the silhouette alone. Half-body character portrait, facing right toward an unseen opponent just off-screen (never facing left, never facing the audience), plain solid white
> background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

**Video prompt:**
> A hard recoil snap-back as the invisible hit lands — unsteady wobble, a frozen beat of
> disbelief, the whole body ringing from the blow before it even starts to recover. Fast
> involuntary onset, slow shaken settle. Full-body acting, not just facial animation. Character faces right toward an unseen opponent just off-screen (never left, never the audience). Plain
> solid white background, no scenery, visual novel courtroom drama style, bold clean linework, dramatic rim lighting, anime key-art shading, high contrast mood lighting, 16:9 aspect ratio.

---

## Заметки по использованию

- **Стилистический хвост** (`visual novel courtroom drama style, bold clean linework, dramatic
  rim lighting, anime key-art shading, high contrast mood lighting`) — единственное место
  стилистики, вшито в конец каждого промпта. Смена стиля = один find-replace этой фразы по
  всему файлу. Всё остальное (белый фон, поясной кадр, анти-статик директива) — технический
  каркас, его не трогать.
- **Референс** прикладывается изображением и задаёт личность/костюм/рендер. Промпты
  сознательно повторяют «ignore its pose completely / restage the entire body» — это лекарство
  от «нейронка оставила позу заготовки». Если конкретная модель всё равно липнет к позе
  референса — усилить: снизить вес image-референса (IP-adapter weight / image strength) или
  добавить в начало промпта `dynamic action pose, completely different pose from reference`.
- **Поз нет намеренно**: промпт задаёт энергию, направление веса и силуэт — мизансцену
  нейронка ставит сама, поэтому набор не цитирует Ace Attorney по жестам.
- Проверка результата — **тест силуэта**: залей спрайт чёрным; если стейт всё ещё угадывается
  (заявляет / юлит / рушится...) — поза правильная. Если силуэты двух стейтов совпали —
  перегенерить более контрастной парой (обычно путаются hold↔declare и attack↔burst).
- Соответствие стейтов игре: `narrative_engine.md` §16 (словарь и драйверы),
  `character_core.gd` STATE_TEX (какие позы сейчас на плейсхолдерах — burst, evade, swagger,
  panic, stagger ждут арт в первую очередь).
- Talking-оверлеи и one-shot переходы (AA-модель двух слоёв, см.
  [ace_attorney_animation_states.md](ace_attorney_animation_states.md) §1, §3) — следующий
  слой после статичных поз: video-промпты выше уже написаны под него (idle-лупы у поз,
  импульсные клипы у burst/stagger/attack).
