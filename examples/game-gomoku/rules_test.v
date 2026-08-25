module main
// Unit tests for the backend-authoritative gomoku rules.

fn mk_app() App {
	mut app := App{}
	app.black_id = 'p-black'
	app.white_id = 'p-white'
	return app
}

fn test_role_mapping() {
	app := mk_app()
	assert app.role_of('p-black') == 1
	assert app.role_of('p-white') == 2
	assert app.role_of('someone-else') == 0 // spectator
	assert app.role_of('') == 0
}

fn test_place_requires_turn_order() {
	mut app := mk_app()
	app.place(7, 7, 2) // white tries first
	assert app.place_err == 'Not your turn'
	assert app.board[7][7] == 0

	app.place(7, 7, 1) // black opens
	assert app.place_err == ''
	assert app.board[7][7] == 1
	assert app.turn == 2
}

fn test_place_rejects_spectator_and_occupied() {
	mut app := mk_app()
	app.place(7, 7, 1)

	app.place(7, 8, 0) // spectator
	assert app.place_err == 'You are a spectator'

	app.place(7, 7, 2) // occupied cell
	assert app.place_err == 'Cell occupied'
}

fn test_five_in_a_row_wins_horizontally() {
	mut app := mk_app()
	app.turn = 1
	// black stones at y=7, x=3..6; winning stone at x=7
	for x in 3 .. 7 {
		app.place(x, 7, 1)
		app.place(x, 8, 2) // white replies elsewhere
		app.turn = 1
	}
	app.place(7, 7, 1)
	assert app.over
	assert app.winner == 1
}

fn test_five_diagonal_wins() {
	mut app := mk_app()
	app.turn = 2
	// white diagonal (2,2)..(6,6); interleaved black stones never reach 5
	for i in 0 .. 4 {
		app.place(2 + i, 2 + i, 2)
		app.place(2 + i, 3 + i, 1)
		app.turn = 2
	}
	app.place(6, 6, 2)
	assert app.over
	assert app.winner == 2
}

fn test_four_does_not_win() {
	mut app := mk_app()
	app.turn = 1
	for x in 3 .. 6 {
		app.place(x, 7, 1)
		app.place(x, 8, 2)
		app.turn = 1
	}
	app.place(6, 7, 1) // 4 in a row only
	assert !app.over
	assert app.winner == 0
}

fn test_win_counts_through_the_stone_both_ways() {
	mut app := mk_app()
	app.turn = 1
	// stones at x=2..3 and x=5..6 on y=7; placing at x=4 bridges to five
	app.board[7][2] = 1
	app.board[7][3] = 1
	app.board[7][5] = 1
	app.board[7][6] = 1
	app.place(4, 7, 1)
	assert app.over
	assert app.winner == 1
}

fn test_game_over_locks_the_board() {
	mut app := mk_app()
	app.turn = 1
	app.board[7][2] = 1
	app.board[7][3] = 1
	app.board[7][4] = 1
	app.board[7][5] = 1
	app.place(6, 7, 1) // black wins
	assert app.over

	app.place(9, 9, 2)
	assert app.place_err == 'Game over — start a new match'
	assert app.board[9][9] == 0
}

fn test_reset_keeps_seats_and_clears_board() {
	mut app := mk_app()
	app.place(7, 7, 1)
	app.reset()
	assert app.board[7][7] == 0
	assert app.turn == 1
	assert app.black_id == 'p-black' // seats survive a reset
	assert !app.over
}

fn test_seat_refuses_empty_client_id() {
	mut app := App{}
	assert app.seat('') == 0
	assert app.black_id == '' // empty caller must NOT claim BLACK
}

fn test_seat_assigns_black_then_white_then_spectator() {
	mut app := App{} // fresh app: no pre-seeded seats
	assert app.seat('c1') == 1
	assert app.black_id == 'c1'
	assert app.seat('c2') == 2
	assert app.white_id == 'c2'
	assert app.seat('c3') == 0 // spectator
	assert app.role_of('c3') == 0
}

fn test_seated_client_can_place_and_alternate() {
	mut app := App{}
	black := app.seat('c1')
	white := app.seat('c2')

	app.place(7, 7, black)
	assert app.place_err == ''
	app.place(7, 8, white)
	assert app.place_err == ''
	assert app.board[7][7] == 1 && app.board[8][7] == 2
	assert app.turn == black // back to black after two moves
}
