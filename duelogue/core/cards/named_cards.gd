extends RefCounted

## DUELOGUE — ИМЕННЫЕ ПРИЁМЫ (zal_run_v0.1 §2): реестр карт «базовый тип + твист правила».
## Прогрессия правилами, не числами (§1.3, инвариант §8.2): каждый твист написан на карте
## и виден на столе. Источник пула — context/rhetoric/ (Шопенгауэр, уловки, схемы Уолтона).
##
## Разделение труда: здесь ДАННЫЕ (пространство для добавления новых приёмов — одна запись
## в CARDS); исполнение твистов — guarded-ветки rules_core (play_named + хуки, ваниль не
## тронута); политика розыгрыша ботом — ai.gd (_apply_named); подача игроку — battle_controller
## (маршрут play_hand) + тултипы debate_screen.
##
## Карта-словарь совместима с ванильной ({type, name, steals}) плюс поля:
##   named — id приёма (диспатч твиста), text — правило на столе,
##   targeted — атака с выбором цели (UI ведёт таргетинг), clinch — открывает клинч
##   (прочие именные атаки в V1 бьют БЕЗ клинча — «выстрел», не ралли).

const C := preload("res://duelogue/core/cards/card_types.gd")

const CARDS := {
	"gish_gallop": {
		"name": "Гиш-галоп", "base": C.TYPE_RAZBOR, "steals": false,
		"targeted": true, "clinch": false,
		"text": "Снимает по 1 тезису с ДВУХ разных рамок (цель + самая толстая другая). Клинч не открывается: поток, не дуэль.",
	},
	"socratic": {
		"name": "Сократический вопрос", "base": C.TYPE_RAZBOR, "steals": false,
		"targeted": true, "clinch": true,
		"text": "Открывает клинч. Ловушка: если защитник отвечал тезисами — первый защитный тезис уходит вам.",
	},
	"ad_hominem": {
		"name": "Ad hominem", "base": C.TYPE_RAZBOR, "steals": false,
		"targeted": true, "clinch": false,
		"text": "Снимает 2 тезиса с рамки, но зал −1 против вас (грязный приём, §4). Клинч не открывается.",
	},
	"strawman": {
		"name": "Соломенное чучело", "base": C.TYPE_RAZBOR, "steals": true,
		"targeted": true, "clinch": false,
		"text": "Кража с длинной рукой: порог захвата +1 (дотягивается до рамок толще), но добыча приходит с −1 тезисом (мин. 1).",
	},
	"burden_shift": {
		"name": "Перенос бремени", "base": C.TYPE_TEZIS, "steals": false,
		"targeted": false, "clinch": false,
		"text": "Тезис на активную рамку; до начала вашего следующего хода эту рамку нельзя ЗАХВАТИТЬ (маркер «шатается» снят).",
	},
	"axiom": {
		"name": "Аксиома", "base": C.TYPE_USTANOVKA, "steals": false,
		"targeted": false, "clinch": false,
		"text": "Рамка открывается сразу с 2 тезисами, но её нельзя оборонять в клинче (аксиомы не обсуждаются).",
	},
}


static func ids() -> Array:
	return CARDS.keys()


static func get_def(id: String) -> Dictionary:
	return CARDS.get(id, {})


## Карта-словарь приёма (совместима с ванильным контрактом колоды).
static func make(id: String) -> Dictionary:
	var d: Dictionary = CARDS.get(id, {})
	if d.is_empty():
		return {}
	return {
		"type": String(d.base), "name": String(d.name), "steals": bool(d.get("steals", false)),
		"named": id, "text": String(d.text),
		"targeted": bool(d.get("targeted", false)), "clinch": bool(d.get("clinch", false)),
	}


## ЗАМЕНА (§1): именная карта ВЫТЕСНЯЕТ из колоды добора ванильную того же базового типа
## (и той же steals-природы у атак) — размер обоймы неизменен, соотношение типов не плывёт.
## Кладётся в случайную позицию добора. Дубли id разрешены (сим проверяет развилку §10.2).
static func inject(side: Dictionary, card_ids: Array) -> void:
	var draw: Array = side.draw
	for id in card_ids:
		var nc := make(String(id))
		if nc.is_empty():
			continue
		# Вытесняем ванильную: сперва точное совпадение (тип + steals-природа), затем
		# любую ванильную той же базы — размер обоймы не раздувается, даже если, скажем,
		# кража-приём взят при 0 ванильных Краж в счётчиках.
		var removed := false
		for exact in [true, false]:
			for i in draw.size():
				var c: Dictionary = draw[i]
				if String(c.type) != String(nc.type) or c.has("named"):
					continue
				if exact and bool(c.get("steals", false)) != bool(nc.steals):
					continue
				draw.remove_at(i)
				removed = true
				break
			if removed:
				break
		draw.insert(randi() % (draw.size() + 1), nc)
