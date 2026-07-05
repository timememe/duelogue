extends Node

## Тестовая сцена: прогоняет матч ИИ против ИИ и печатает каждый ход в консоль.
## Повесь этот скрипт на root node test/test_match.tscn.


func _ready() -> void:
	# Ждём один кадр, чтобы autoload успели инициализироваться.
	await get_tree().process_frame
	run_test_match()


func run_test_match() -> void:
	print("=== DUELOGUE: ТЕСТ-МАТЧ ИИ ПРОТИВ ИИ ===")
	print("")

	var deck := CardDatabase.get_deck("Кофе")
	if deck == null:
		push_error("Не удалось загрузить колоду 'Кофе'")
		return

	print("Колода: %s" % deck.deck_name)
	print("Атаки игрока: %d, атаки оппонента: %d, защита: %d, уклонения: %d" % [
		deck.player_attack_cards.size(),
		deck.enemy_attack_cards.size(),
		deck.defense_cards.size(),
		deck.evasion_cards.size()
	])
	print("")

	var state := GameState.new()
	var ai_player := AIBasic.new()
	var ai_opponent := AIBasic.new()
	state.ai = ai_opponent
	state.initialize(deck, ai_opponent)

	# Для теста игроком тоже управляет ИИ.
	print("Рука игрока: %s" % _hand_str(state.player.hand))
	print("Рука оппонента: %s" % _hand_str(state.opponent.hand))
	print("Колода игрока: %d карт, колода оппонента: %d карт" % [state.player.deck.size(), state.opponent.deck.size()])
	print("Игрок начинает: %s" % str(state.is_player_turn))
	print("")

	var max_turns := 100
	var turn := 0

	while state.phase != Enums.GamePhase.MATCH_OVER and turn < max_turns:
		turn += 1
		print("--- Ход %d ---" % turn)

		# ИИ выбирает карту за игрока.
		var player_card := ai_player.choose_card(state.player.hand, state.player, state.opponent)
		if player_card == null:
			print("Игроку нечего играть!")
			break

		var log := state.play_turn(player_card)
		for line in log:
			print("  %s" % line)

		print("  Статы: И[Л:%d Э:%d оч:%d щ:%d] против О[Л:%d Э:%d оч:%d щ:%d] Весы:%d" % [
			state.player.logic, state.player.emotion, state.player.points, state.player.shield,
			state.opponent.logic, state.opponent.emotion, state.opponent.points, state.opponent.shield,
			state.scales_mgr.scales
		])
		print("  Руки: И:%d О:%d | Колоды: И:%d О:%d" % [
			state.player.hand.size(), state.opponent.hand.size(),
			state.player.deck.size(), state.opponent.deck.size()
		])
		print("")

		if state.phase == Enums.GamePhase.MATCH_OVER:
			break

	if state.phase == Enums.GamePhase.MATCH_OVER:
		var winner := "Игрок" if state.player.points >= 3 else "Оппонент"
		print("=== МАТЧ ОКОНЧЕН: %s побеждает ===" % winner)
		print("Итоговый счёт: Игрок %d - %d Оппонент" % [state.player.points, state.opponent.points])
	else:
		print("=== МАТЧ ОСТАНОВЛЕН после %d ходов ===" % max_turns)

	print("")
	print("=== ТЕСТ ЗАВЕРШЁН ===")


func _hand_str(hand: Array[CardInstance]) -> String:
	var names: PackedStringArray
	for c in hand:
		names.append("%s(%d)" % [c.data.card_name, c.uses_left])
	return ", ".join(names)
