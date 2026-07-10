extends RefCounted

## DUELOGUE — общий контракт слоя забега (нейтральный, без зависимостей; как card_types).
## Типы комнат карты «Сезона» (zal_run_v0.1 §6): каждый узел карты — ангажемент.
## Здесь только данные-словарь (id/лейблы/глифы); цвета и стили — забота view.

const ROOM_EFIR := "efir"        ## обычные дебаты по контракту (бой)
const ROOM_ELITE := "elite"      ## именитый спорщик (элитка: архетип со спец-правилом)
const ROOM_SHOP := "shop"        ## кулуары (лавка: покупка приёмов, замены в обойме)
const ROOM_PREP := "prep"        ## подготовка (костёр: заготовка/порядок колоды/разведка)
const ROOM_EVENT := "event"      ## скандал/интервью (не-боевая сцена с выбором)
const ROOM_BOSS := "boss"        ## финал акта (архетип-экзамен с твист-правилом)

## Комнаты, узел которых несёт ангажемент (афиша §6: тема × сторона × оппонент × гонорар).
const BATTLE_ROOMS := [ROOM_EFIR, ROOM_ELITE, ROOM_BOSS]

const LABELS := {
	ROOM_EFIR: "Эфир",
	ROOM_ELITE: "Именитый спорщик",
	ROOM_SHOP: "Кулуары",
	ROOM_PREP: "Подготовка",
	ROOM_EVENT: "Скандал",
	ROOM_BOSS: "Финал акта",
}

## Короткие лейблы для узла на карте (полные — в панели комнаты).
const SHORT := {
	ROOM_EFIR: "Эфир",
	ROOM_ELITE: "Именитый",
	ROOM_SHOP: "Кулуары",
	ROOM_PREP: "Подготовка",
	ROOM_EVENT: "Скандал",
	ROOM_BOSS: "Финал",
}

## Однознаковые глифы узлов (карта + легенда).
const GLYPHS := {
	ROOM_EFIR: "Э",
	ROOM_ELITE: "★",
	ROOM_SHOP: "К",
	ROOM_PREP: "П",
	ROOM_EVENT: "?",
	ROOM_BOSS: "Ф",
}


static func is_battle(type: String) -> bool:
	return BATTLE_ROOMS.has(type)
