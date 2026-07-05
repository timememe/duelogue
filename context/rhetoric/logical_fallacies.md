# Логические ошибки (Logical Fallacies)

Каталог из ~40 ошибок, классифицированных по типу. Пересекается с уловками Шопенгауэра и
общей риторикой — здесь акцент на строгой логической природе. Каждая ошибка =
потенциальный приём оппонента или специальная карта.

---

## I. Формальные (ошибки структуры вывода)

**Affirming the consequent (утверждение следствия).** «Если дождь — улица мокрая. Улица мокрая → дождь». **game**: ATK/LOGIC, trap.

**Denying the antecedent (отрицание основания).** «Дождя нет → улица сухая».

**Undistributed middle (нераспределённый средний термин).** «Все собаки — млекопитающие. Все коты — млекопитающие → собаки = коты».

**Affirming a disjunct.** «А или Б. А → значит не Б» (хотя могло быть и то, и другое).

**Existential fallacy.** Вывод о существовании из общего утверждения без подтверждения базиса.

---

## II. Релевантности (атака мимо тезиса)

| Ошибка | Суть | Game |
|---|---|---|
| **Ad hominem** | Атака на личность | ATK/EMOTION |
| **Tu quoque** | «Сам такой» | ATK/EMOTION |
| **Ad populum** | «Все так считают» | ATK/EMOTION |
| **Ad verecundiam** | «Эксперт сказал» | ATK через щит |
| **Ad baculum** | «Угроза силой» | ATK/EMOTION, страх |
| **Ad misericordiam** | «К жалости» | DEFENSE/EMOTION |
| **Ad ignorantiam** | «Никто не доказал обратное → значит, верно» | ATK/LOGIC, blef |
| **Ad antiquitatem** | «Так делали тысячу лет» | ATK/EMOTION |
| **Ad novitatem** | «Это современный подход» | ATK/EMOTION |
| **Ad consequentiam** | «Следствие нежелательно → тезис ложен» | ATK/EMOTION |
| **Genetic fallacy** | Атака происхождения идеи | ATK/EMOTION |
| **Guilt by association** | «Так считали и нацисты» | ATK/EMOTION |
| **Appeal to nature** | «Естественное = хорошее» | ATK/EMOTION |
| **Poisoning the well** | Заранее дискредитировать | дебафф первого хода |
| **Red herring** | Отвлечение на постороннее | EVASION |

---

## III. Индукции (неправильное обобщение)

**Hasty generalization.** Поспешное обобщение из малой выборки. **game**: ATK/LOGIC, слабая.

**Cherry picking.** Выборочное цитирование удобных данных. **game**: ATK/LOGIC.

**Anecdotal evidence.** Один случай как доказательство. **game**: ATK/EMOTION (личная история).

**Survivorship bias.** Выводы только по «выжившим» данным. **game**: ATK/LOGIC, trap.

**Texas sharpshooter.** Подгонка критериев под уже случившийся результат. **game**: ATK/LOGIC.

**Biased sample.** Нерепрезентативная выборка.

---

## IV. Двусмысленности

**Equivocation.** Игра на разных значениях слова (Шопенгауэр #2). **game**: ATK/RANDOM.

**Amphiboly.** Грамматическая двусмысленность («Видел человека на холме с биноклем»).

**Composition.** От части — к целому. «Каждый игрок хорош → команда хороша».

**Division.** От целого — к части.

**Reification.** Овеществление абстракции. «Общество требует...»

**Accent fallacy.** Сдвиг смысла через интонацию/выделение.

---

## V. Причинности

**Post hoc ergo propter hoc.** «После — значит вследствие». **game**: ATK/LOGIC.

**Cum hoc ergo propter hoc.** «Корреляция — значит причина». **game**: ATK/LOGIC.

**Single cause (oversimplification).** Сведение многофакторного к одной причине. **game**: ATK/LOGIC.

**Slippery slope.** «Если А — то цепочкой дойдём до Я». **game**: ATK/EMOTION, страх.

**Gambler's fallacy.** «Долго выпадал орёл → теперь точно решка».

**Regression fallacy.** Игнорирование возврата к среднему.

---

## VI. Предположения и манипуляции тезисом

**Begging the question (petitio principii).** Тезис включён в посылку. **game**: ATK/LOGIC, blef.

**Loaded question.** «Ты перестал бить жену?» **game**: ATK/EMOTION, ловушка.

**False dilemma.** Ложная дилемма (Шопенгауэр #13). **game**: ATK/LOGIC.

**Straw man.** Соломенное чучело — упрощённая версия позиции оппонента. **game**: ATK/LOGIC.

**No true Scotsman.** «Настоящий X так бы не поступил» — спасение тезиса исключением случая. **game**: DEFENSE.

**Special pleading.** Введение специального исключения только для своего случая. **game**: DEFENSE.

**Middle ground.** «Истина всегда посередине» — необязательно. **game**: DEFENSE/EVASION.

**Moving the goalposts.** Сдвиг критериев, когда первые выполнены. **game**: DEFENSE, бесконечная.

**Kafka trap.** «Отрицание — это и есть подтверждение». **game**: ATK/EMOTION, ловушка.

**Motte and bailey.** Защищать сильный тезис слабым: атакуют сильное — отступаешь к слабому, после паузы возвращаешься к сильному. **game**: DEFENSE с переключением.

**Goalpost-keeper.** Бесконечно требовать «ещё одно доказательство».

---

## Группировка для геймдизайна

**Атакующее ядро колоды** (массовые карты):
- false dilemma, straw man, slippery slope, ad hominem, ad populum, post hoc, hasty generalization

**Защитное ядро**:
- no true Scotsman, special pleading, moving the goalposts, middle ground, motte and bailey

**Уклонения**:
- red herring, tu quoque, kafka trap

**Редкие/«грязные» карты** (риск + репутационный штраф):
- ad baculum, loaded question, kafka trap, poisoning the well

**Маппинг на эвенты**:
- hasty generalization, ad hominem → HEATED_EXCHANGE (эмоции зашкаливают)
- equivocation, amphiboly → MIND_GAMES (тактический спор)
- ad populum, ad verecundiam → CRITICAL_TURNING_POINT (апелляция к толпе на переломе)
