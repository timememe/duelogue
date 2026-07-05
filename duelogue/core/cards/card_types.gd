extends RefCounted

## DUELOGUE — общий карточный контракт (нейтральный, без зависимостей).
## Сюда вынесены константы, которые делят между собой rules_core / deck / ai,
## чтобы не плодить циклы preload. Нарративный слой держит свои строковые копии
## ("T"/"R"/"U") намеренно — он развязан от ядра правил.

const TYPE_TEZIS := "T"
const TYPE_RAZBOR := "R"
const TYPE_USTANOVKA := "U"

const SIDE_YOU := "you"
const SIDE_OPP := "opp"

const ZAL_MAX := 20
