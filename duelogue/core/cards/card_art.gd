extends RefCounted

## Реестр карточных эмблем. Все рабочие атласы имеют единый формат 2048×2048,
## 2×2 ячейки по 1024 px. Шаблон карты получает только готовую Texture2D-ячейку.

const C := preload("res://duelogue/core/cards/card_types.gd")
const TYPES := preload("res://duelogue/assets/cards/art/types_atlas_v2.png")
const THESIS_A := preload("res://duelogue/assets/cards/art/thesis_atlas_a_v2.png")
const THESIS_B := preload("res://duelogue/assets/cards/art/thesis_atlas_b_v2.png")
const RAZBOR_A := preload("res://duelogue/assets/cards/art/razbor_atlas_a_v2.png")
const RAZBOR_B := preload("res://duelogue/assets/cards/art/razbor_atlas_b_v2.png")
const THEFT_SETUP_A := preload("res://duelogue/assets/cards/art/theft_setup_atlas_a_v2.png")
const SETUP_B := preload("res://duelogue/assets/cards/art/setup_atlas_b_v2.png")
const NAMED_A := preload("res://duelogue/assets/cards/art/named_atlas_a_v2.png")
const NAMED_B := preload("res://duelogue/assets/cards/art/named_atlas_b_v2.png")

# Vector3i: страница (A = 0, B = 1), колонка, строка.
const THESIS_CELLS := {
	"Здравый смысл": Vector3i(0, 0, 0), "Статистика": Vector3i(0, 1, 0),
	"Определение": Vector3i(0, 0, 1), "Аналогия": Vector3i(0, 1, 1),
	"Пример": Vector3i(1, 0, 0), "Авторитет": Vector3i(1, 1, 0),
	"Традиция": Vector3i(1, 0, 1), "Эмоция": Vector3i(1, 1, 1),
}
const RAZBOR_CELLS := {
	"Не в кассу": Vector3i(0, 0, 0), "Передёрг": Vector3i(0, 1, 0),
	"Контрпример": Vector3i(0, 0, 1), "До абсурда": Vector3i(0, 1, 1),
	"Источник?": Vector3i(1, 0, 0), "Корреляция": Vector3i(1, 1, 0),
	"Ложная аналогия": Vector3i(1, 0, 1), "А докажи": Vector3i(1, 1, 1),
}
const SETUP_CELLS := {
	"Рамка": Vector3i(0, 0, 1), "Тезис дня": Vector3i(0, 1, 1),
	"Позиция": Vector3i(1, 0, 0), "Постулат": Vector3i(1, 1, 0),
	"Принцип": Vector3i(1, 0, 1), "Аксиома": Vector3i(1, 1, 1),
}
const NAMED_CELLS := {
	"gish_gallop": Vector3i(0, 0, 0), "socratic": Vector3i(0, 1, 0),
	"ad_hominem": Vector3i(0, 0, 1), "strawman": Vector3i(0, 1, 1),
	"burden_shift": Vector3i(1, 0, 0), "axiom": Vector3i(1, 1, 0),
}

const GRID_SIZE := 2.0
const CELL_INSET_PX := 15.0
const BOARD_ICON_INSET_PX := 130.0
static var _cache: Dictionary = {}


static func type_icon_for(card: Dictionary, board_crop: bool = false) -> Texture2D:
	var pos := Vector2i.ZERO
	if bool(card.get("steals", false)):
		pos = Vector2i(0, 1)
	else:
		match String(card.get("type", "")):
			C.TYPE_TEZIS: pos = Vector2i(0, 0)
			C.TYPE_RAZBOR: pos = Vector2i(1, 0)
			C.TYPE_USTANOVKA: pos = Vector2i(1, 1)
	var suffix := "board" if board_crop else "card"
	var inset := BOARD_ICON_INSET_PX if board_crop else CELL_INSET_PX
	return _cell("type_%s_%d_%d" % [suffix, pos.x, pos.y], TYPES, pos, inset)


static func art_for(card: Dictionary, display_title: String) -> Texture2D:
	var named_id := String(card.get("named", ""))
	if named_id != "":
		var named_cell: Vector3i = NAMED_CELLS.get(named_id, Vector3i.ZERO)
		var named_atlas: Texture2D = NAMED_A if named_cell.x == 0 else NAMED_B
		return _cell("named_%s" % named_id, named_atlas,
			Vector2i(named_cell.y, named_cell.z))

	match String(card.get("type", "")):
		C.TYPE_TEZIS:
			var thesis_cell: Vector3i = THESIS_CELLS.get(display_title, Vector3i(1, 0, 0))
			var thesis_atlas: Texture2D = THESIS_A if thesis_cell.x == 0 else THESIS_B
			return _cell("thesis_%s" % display_title, thesis_atlas,
				Vector2i(thesis_cell.y, thesis_cell.z))
		C.TYPE_RAZBOR:
			if bool(card.get("steals", false)):
				var is_reversal := display_title == "Разворот" or String(card.get("name", "")) == "Разворот"
				var theft_pos := Vector2i(0, 0) if is_reversal else Vector2i(1, 0)
				return _cell("theft_%d" % theft_pos.x, THEFT_SETUP_A, theft_pos)
			var key := "А докажи" if String(card.get("name", "")) == "А докажи" else display_title
			var razbor_cell: Vector3i = RAZBOR_CELLS.get(key, Vector3i(0, 0, 1))
			var razbor_atlas: Texture2D = RAZBOR_A if razbor_cell.x == 0 else RAZBOR_B
			return _cell("razbor_%s" % key, razbor_atlas,
				Vector2i(razbor_cell.y, razbor_cell.z))
		C.TYPE_USTANOVKA:
			var setup_name := String(card.get("name", ""))
			var setup_cell: Vector3i = SETUP_CELLS.get(setup_name, Vector3i(0, 0, 1))
			var setup_atlas: Texture2D = THEFT_SETUP_A if setup_cell.x == 0 else SETUP_B
			return _cell("setup_%s" % setup_name, setup_atlas,
				Vector2i(setup_cell.y, setup_cell.z))
	return null


static func _cell(key: String, atlas: Texture2D, pos: Vector2i,
	inset_px: float = CELL_INSET_PX) -> AtlasTexture:
	if _cache.has(key):
		return _cache[key] as AtlasTexture
	var cell_size := Vector2(atlas.get_width(), atlas.get_height()) / GRID_SIZE
	# Разделитель нарисован прямо по границе клетки. Уводим регион на 15 px внутрь:
	# при размере 1024 px это незаметно на карте, но гарантированно исключает линию,
	# внешний контур и их выборку линейным фильтром.
	var inset := Vector2(inset_px, inset_px)
	var result := AtlasTexture.new()
	result.atlas = atlas
	result.region = Rect2(Vector2(pos) * cell_size + inset, cell_size - inset * 2.0)
	result.filter_clip = true
	_cache[key] = result
	return result
