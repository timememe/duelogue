extends RefCounted

## DUELOGUE — СОСТОЯНИЕ ЗАБЕГА («Сезон», zal_run_v0.1): чистые данные прогресса и
## переходы/эффекты над ними. Правил потока здесь НЕТ (владелец — run_controller, как
## battle_controller у боя). Сериализуемо в Dictionary — контракт будущего сейва.
##
## Ресурсы дистанции: репутация (§4, «HP кампании») и гонорары (валюта кулуаров §6) —
## пока СТАБЫ-числа, чтобы пайплайн эффектов (события/исходы) работал end-to-end;
## механики (крен зала от репутации и т.д.) — по лестнице §9.

const RoomTypes := preload("res://duelogue/core/run/room_types.gd")

var run_seed := 0
var act := 1
var acts_total := 3
var map := {}            ## карта ТЕКУЩЕГО акта (run_map.generate; акты генерятся по одному)
var current_id := -1     ## узел, в котором стоим (-1 — старт акта, перед первым слоем)
var room_open := false   ## комната текущего узла не закрыта — по карте идти нельзя
var path: Array = []     ## пройденное за весь забег: [{act, id, type, outcome}]
var reputation := 5
var fees := 0
var over := false
var outcome := ""        ## "" | victory | cancelled | abandoned


func node(id: int) -> Dictionary:
	return (map.get("nodes", {}) as Dictionary).get(id, {})


## Куда можно шагнуть сейчас: со старта акта — весь первый слой, из узла — его next.
func reachable_ids() -> Array:
	if over or room_open:
		return []
	if current_id == -1:
		var out: Array = []
		for id in map.get("nodes", {}):
			if int(map.nodes[id].layer) == 0:
				out.append(id)
		out.sort()
		return out
	return (node(current_id).get("next", []) as Array).duplicate()


## Статус узла для рендера карты: current | cleared | open | locked.
func node_status(id: int) -> String:
	if id == current_id:
		return "current"
	for p in path:
		if int(p.act) == act and int(p.id) == id:
			return "cleared"
	if reachable_ids().has(id):
		return "open"
	return "locked"


## Рёбра, пройденные в текущем акте (для подсветки маршрута): [[from, to], ...].
func walked_edges() -> Array:
	var ids: Array = []
	for p in path:
		if int(p.act) == act:
			ids.append(int(p.id))
	if current_id != -1 and (ids.is_empty() or ids.back() != current_id):
		ids.append(current_id)
	var out: Array = []
	for i in range(ids.size() - 1):
		out.append([ids[i], ids[i + 1]])
	return out


func enter(id: int) -> void:
	current_id = id
	room_open = true


func resolve(room_outcome: String) -> void:
	room_open = false
	var nd := node(current_id)
	path.append({"act": act, "id": current_id, "type": String(nd.get("type", "")), "outcome": room_outcome})


## Эффекты комнат/событий: rep (репутация §4), fee (гонорар). Зарезервировано контрактом,
## не реализовано: card (замена в обойме §1), intel (разведка §3.4), zal (стартовый крен §3.1).
func apply_effects(fx: Dictionary) -> void:
	reputation = maxi(0, reputation + int(fx.get("rep", 0)))  # дно 0 = «отменён» (§4)
	fees = maxi(0, fees + int(fx.get("fee", 0)))


# --- сейв-контракт ---

func to_dict() -> Dictionary:
	return {
		"run_seed": run_seed, "act": act, "acts_total": acts_total,
		"current_id": current_id, "room_open": room_open,
		"path": path.duplicate(true),
		"reputation": reputation, "fees": fees,
		"over": over, "outcome": outcome,
		# Карта не сериализуется: она детерминирована (run_seed + act) и перегенерится.
	}


func from_dict(d: Dictionary, regenerated_map: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	act = int(d.get("act", 1))
	acts_total = int(d.get("acts_total", 3))
	current_id = int(d.get("current_id", -1))
	room_open = bool(d.get("room_open", false))
	path = (d.get("path", []) as Array).duplicate(true)
	reputation = int(d.get("reputation", 5))
	fees = int(d.get("fees", 0))
	over = bool(d.get("over", false))
	outcome = String(d.get("outcome", ""))
	map = regenerated_map
