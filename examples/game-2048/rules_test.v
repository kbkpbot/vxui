module main

// Unit tests for the backend-authoritative 2048 rules.

// set_board fills app.board from a literal (avoids V 0.5.2 codegen bug on
// fixed-size array assignment).
fn set_board(mut app App, vals [][]int) {
	for r in 0 .. board_size {
		for c in 0 .. board_size {
			app.board[r][c] = vals[r][c]
		}
	}
}

fn test_slide_row_left_merges_once_per_pair() {
	mut row := [2, 2, 4, 4]
	gain := slide_row_left(mut row)
	assert row == [4, 8, 0, 0]
	assert gain == 12
}

fn test_slide_row_left_no_merge_when_separated() {
	mut row := [2, 0, 2, 4]
	gain := slide_row_left(mut row)
	assert row == [4, 4, 0, 0] // the two 2s merge; 4 stays separate
	assert gain == 4
}

fn test_slide_row_left_triple_merges_lowest_first() {
	mut row := [2, 2, 2, 0]
	gain := slide_row_left(mut row)
	assert row == [4, 2, 0, 0] // leftmost pair merges first
	assert gain == 4
}

fn test_slide_row_left_all_zero_and_no_change() {
	mut row := [0, 0, 0, 0]
	_ := slide_row_left(mut row)
	assert row == [0, 0, 0, 0]

	mut fixed := [2, 4, 2, 4]
	_ := slide_row_left(mut fixed)
	assert fixed == [2, 4, 2, 4]
}

fn test_apply_move_left_moves_everything_left() {
	mut app := App{}
	set_board(mut app, [
		[0, 0, 0, 2],
		[0, 0, 0, 0],
		[0, 2, 0, 0],
		[0, 0, 0, 0],
	])
	app.apply_move('left')
	assert app.board[0][0] == 2
	assert app.board[2][0] == 2
}

fn test_apply_move_down_pulls_column_down() {
	mut app := App{}
	app.reset()
	set_board(mut app, [
		[2, 0, 0, 0],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
	])
	app.apply_move('down')
	assert app.board[3][0] == 2
}

fn test_game_over_detection() {
	mut app := App{}
	set_board(mut app, [
		[2, 4, 2, 4],
		[4, 2, 4, 2],
		[2, 4, 2, 4],
		[4, 2, 4, 2],
	])
	app.check_endgame()
	assert app.over
}

fn test_not_game_over_when_merge_available() {
	mut app := App{}
	set_board(mut app, [
		[2, 4, 2, 4],
		[4, 2, 4, 2],
		[2, 4, 2, 4],
		[4, 2, 4, 4], // last row has a mergeable pair
	])
	app.check_endgame()
	assert !app.over
}

fn test_win_flag_at_2048() {
	mut app := App{}
	set_board(mut app, [
		[2048, 4, 2, 4],
		[4, 2, 4, 2],
		[2, 4, 2, 4],
		[4, 2, 4, 2],
	])
	app.check_endgame()
	assert app.won
}
