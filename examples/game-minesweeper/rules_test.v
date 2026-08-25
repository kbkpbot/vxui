module main

import time
// Unit tests for the backend-authoritative minesweeper rules.

fn mk() App {
	mut app := App{}
	app.generate(8, 8) // first click at centre
	return app
}

fn test_generation_place_exactly_40_mines() {
	app := mk()
	mut n := 0
	for m in app.mines {
		if m {
			n++
		}
	}
	assert n == mine_count
}

fn test_generation_keeps_first_click_safe() {
	app := mk()
	for dy in -1 .. 2 {
		for dx in -1 .. 2 {
			i := idx(8 + dx, 8 + dy)
			assert !app.mines[i], 'mine inside the first-click safety zone'
		}
	}
	assert app.generated
	assert app.start_ms > 0
}

fn test_counts_match_neighbour_mines() {
	app := mk()
	for y in 0 .. bh {
		for x in 0 .. bw {
			if app.mines[idx(x, y)] {
				continue
			}
			mut n := 0
			for dy in -1 .. 2 {
				for dx in -1 .. 2 {
					if dx == 0 && dy == 0 {
						continue
					}
					xx := x + dx
					yy := y + dy
					if xx >= 0 && xx < bw && yy >= 0 && yy < bh && app.mines[idx(xx, yy)] {
						n++
					}
				}
			}
			assert app.counts[idx(x, y)] == n
		}
	}
}

fn test_reveal_opening_flood_fills_zeros() {
	mut app := mk()
	// find a zero cell (40 mines on 256 cells guarantees plenty)
	mut zero := -1
	for i in 0 .. bw * bh {
		if app.counts[i] == 0 && !app.mines[i] {
			zero = i
			break
		}
	}
	assert zero >= 0
	before := app.opened
	app.reveal(zero % bw, zero / bw)
	assert app.opened > before
	// every revealed cell must be either a zero cell or a bordering number
	for i in 0 .. bw * bh {
		if app.revealed[i] && !app.mines[i] {
			x := i % bw
			y := i / bw
			// a numbered cell may only appear adjacent to a revealed zero
			if app.counts[i] > 0 {
				mut touches_zero := false
				for dy in -1 .. 2 {
					for dx in -1 .. 2 {
						xx := x + dx
						yy := y + dy
						if xx >= 0 && xx < bw && yy >= 0 && yy < bh {
							j := idx(xx, yy)
							if app.revealed[j] && app.counts[j] == 0 && !app.mines[j] {
								touches_zero = true
							}
						}
					}
				}
				assert touches_zero, 'numbered cell revealed without adjacent zero'
			}
		}
	}
}

fn test_flag_toggles_and_blocks_reveal() {
	mut app := mk()
	app.toggle_flag(3, 3)
	assert app.flagged[idx(3, 3)]
	assert app.flags == 1
	app.toggle_flag(3, 3)
	assert !app.flagged[idx(3, 3)]
	assert app.flags == 0

	app.toggle_flag(5, 5)
	app.reveal(5, 5)
	assert !app.revealed[idx(5, 5)]
	assert app.place_err == 'Cell is flagged — unflag it first'
}

fn test_reveal_on_mine_ends_the_game() {
	mut app := mk()
	// find a mine and force-reveal through the public path by unflagging logic:
	// reveal() on a mine sets over=false win — locate one
	mut mi := -1
	for i in 0 .. bw * bh {
		if app.mines[i] {
			mi = i
			break
		}
	}
	assert mi >= 0
	app.reveal(mi % bw, mi / bw)
	assert app.over
	assert !app.win
	assert app.end_ms > 0
}

fn test_win_when_all_safe_cells_open() {
	mut app := mk()
	// pretend flood-fill opened every non-mine cell
	for i in 0 .. bw * bh {
		if !app.mines[i] {
			app.revealed[i] = true
			app.opened++
		}
	}
	app.check_win()
	assert app.over
	assert app.win
	assert app.end_ms > 0
}

fn test_reset_clears_everything() {
	mut app := mk()
	app.toggle_flag(2, 2)
	app.reveal(9, 9)
	app.reset()
	assert !app.generated
	assert app.flags == 0
	assert app.opened == 0
	assert app.start_ms == 0
	assert !app.over
}
