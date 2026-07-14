extends SceneTree

## Детерминированный постпроцесс генеративных атласов: независимо от размера, который
## вернул генератор, проект всегда получает квадрат 2048×2048 и сетку 2×2 по 1024 px.

const TARGET_SIZE := 2048


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Использование: normalize_card_atlas.gd -- <input> <output>")
		quit(2)
		return
	var source_path := ProjectSettings.globalize_path(String(args[0]))
	var output_path := ProjectSettings.globalize_path(String(args[1]))
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		push_error("Не удалось загрузить atlas: %s" % source_path)
		quit(3)
		return
	image.convert(Image.FORMAT_RGBA8)
	image.resize(TARGET_SIZE, TARGET_SIZE, Image.INTERPOLATE_LANCZOS)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Не удалось сохранить atlas: %s (%s)" % [output_path, error])
	quit(error)
