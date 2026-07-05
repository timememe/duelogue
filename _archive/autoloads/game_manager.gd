extends Node

var selected_deck_name: String = ""
var current_game_state: GameState = null

signal screen_change_requested(screen_name: String)
signal match_started()
signal match_ended(player_won: bool)
