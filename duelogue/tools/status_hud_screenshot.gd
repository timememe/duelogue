extends Node

## DUELOGUE — ВРЕМЕННЫЙ инструмент визуальной проверки (не боевой код, удалить после
## ручной сверки перк-иконок над кафедрами). Инстанцирует настоящий debate_screen.tscn,
## ждёт несколько кадров (пока start_match()/_refresh() реально отрисуют status-row), делает
## скриншот вьюпорта в PNG. НЕ подключено ни к чему боевому.

const DebateScreen := preload("res://duelogue/ui/debate_screen.tscn")

func _ready() -> void:
	var screen: Control = DebateScreen.instantiate()
	add_child(screen)
	for i in 10:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out_path := "C:/Users/Nurdaulet/AppData/Local/Temp/claude/D--NEUROMKA-GAMED-DUELOGUE-duelogue/10c53ce2-66a6-43c2-bef5-ce18959f0635/scratchpad/status_hud_screenshot.png"
	var err := img.save_png(out_path)
	print("SCREENSHOT save err=%d size=%s path=%s" % [err, str(img.get_size()), out_path])
	get_tree().quit()
