extends RefCounted

## DUELOGUE — ЗАПИСЬ КАТКИ: файловый writer транскрипта (markdown) и JSONL-лога плейтеста.
## Не знает модели и нарратива: контроллер передаёт готовые строки и словари. Вынесен из
## battle_controller, чтобы оркестратор не владел файловыми побочными эффектами.
## Оба файла append-only, читаются инструментами из tools/.

const LOG_PATH := "res://duelogue/tools/playtest_log.jsonl"
const TX_PATH := "res://duelogue/tools/narrative_transcript.md"

var enabled := true   ## smoke/preview могут выключить файловые побочные эффекты
var match_id := 0     ## подмешивается в каждую JSONL-строку как "m"


## Строка общего транскрипта (нарратив ↔ действия в одном файле, в порядке исполнения).
func tx_write(s: String) -> void:
	if not enabled:
		return
	var f := _open_append(TX_PATH)
	if f == null:
		return
	f.store_line(s)
	f.close()


## Событие JSONL-лога катки.
func emit(d: Dictionary) -> void:
	if not enabled:
		return
	d["m"] = match_id
	var f := _open_append(LOG_PATH)
	if f == null:
		return
	f.store_line(JSON.stringify(d))
	f.close()


func _open_append(path: String) -> FileAccess:
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	return f
